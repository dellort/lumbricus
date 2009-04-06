module net.cmdserver;

import common.common;
import common.task;
import framework.commandline;
import framework.timesource;
import gui.label;
import gui.widget;
import gui.wm;
import game.gameshell : cFrameLength;  //lol
import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;
import utils.log;
debug import utils.random;

import tango.core.Thread;
import tango.io.Stdout : Stdout;

enum CmdServerState {
    lobby,
    loading,
    playing,
}

class CmdNetServer : Thread {
    private {
        ushort mPort;
        int mMaxPlayers, mPlayerCount;
        char[] mServerName;
        List2!(CmdNetClientConnection) mClients;
        bool mClose;
        CmdServerState mState;

        NetBase mBase;
        NetHost mHost;

        struct PendingCommand {
            CmdNetClientConnection client;
            char[] cmd;
        }
        PendingCommand[] mPendingCommands;
        TimeSource mMasterTime;
        TimeSourceFixFramerate mGameTime;
        uint mTimeStamp;
        debug int mSimLagMs, mSimJitterMs;
    }

    //create the server thread object
    //to actually run the server, call CmdNetServer.start()
    this(ConfigNode serverConfig) {
        super(&run);

        mClients = new typeof(mClients);

        mPort = serverConfig.getValue("port", 12499);
        mServerName = serverConfig["name"];
        if (mServerName.length == 0)
            mServerName = "Unnamed server";
        mMaxPlayers = serverConfig.getValue("max_players", 4);
        debug {
            mSimLagMs = serverConfig.getValue("sim_lag", 0);
            mSimJitterMs = serverConfig.getValue("sim_jitter", 0);
        }

        mMasterTime = new TimeSource("ServerMasterTime");
        mMasterTime.paused = true;
        mGameTime = new TimeSourceFixFramerate("ServerGameTime", mMasterTime,
            cFrameLength);
    }

    //shutdown the server (delayed)
    void close() {
        mClose = true;
    }

    int playerCount() {
        return mPlayerCount;
    }

    CmdServerState state() {
        return mState;
    }

    //main thread function
    private void run() {
        //create and open server
        mBase = new NetBase();
        mHost = mBase.createServer(mPort, mMaxPlayers);
        mHost.onConnect = &onConnect;

        //try {

        while (!mClose) {
            //check for messages
            mHost.serviceAll();
            foreach (cl; mClients) {
                if (cl.state == ClientConState.closed) {
                    clientRemove(cl);
                } else {
                    cl.tick();
                }
            }
            if (mState == CmdServerState.playing) {
                mMasterTime.update();
                mGameTime.update(&gameTick);
            }
            yield();
        }

        //} catch (Exception e) { <- catching the type Exception is always a bug
        //    //seems this is the only way to be notified about thread errors
        //    Stdout.formatln("Exception {} at {}({})", e.toString(),
        //        e.file, e.line);
        //}

        //shutdown
        foreach (cl; mClients) {
            cl.closeWithReason("server_shutdown");
        }
        mHost.serviceAll();
        delete mHost;
        delete mBase;
    }

    //validate (and possibly change) the nickname of a connecting player
    private bool checkNewNick(ref char[] nick) {
        //no empty nicks, minimum length 3
        if (nick.length < 3)
            return false;
        //xxx check for invalid chars (e.g. space)
        //check for names already in use
        foreach (cl; mClients) {
            if (cl.state != ClientConState.establish && cl.playerName == nick) {
                return false;
            }
        }
        return true;
    }

    //new client is trying to connect
    private void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        auto cl = new CmdNetClientConnection(this, peer);
        cl.client_node = mClients.add(cl);
        mPlayerCount++;
        printClients();
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientRemove(CmdNetClientConnection client) {
        Stdout.formatln("Client from {} ({}) disconnected",
            client.address, client.playerName);
        mClients.remove(client.client_node);
        mPlayerCount--;
        printClients();
        //player disconnecting in lobby
        if (mState == CmdServerState.lobby)
            updateLobbyInfo();
        //player disconnecting while loading
        if (mState == CmdServerState.loading)
            checkLoading();
    }

    private void ccStartGame(CmdNetClientConnection client, CPStartLoading msg)
    {
        if (mState != CmdServerState.lobby)
            return;
        mState = CmdServerState.loading;
        //xxx: teams should be assembled on client?
        //then decompressing-parsing-writing-compressing cfg is unneeded
        //(the garbage below could be removed)
        auto cfg = gConf.loadConfigGzBuf(msg.gameConfig);
        auto teams = cfg.getSubNode("teams");
        teams.clear();
        SPStartLoading reply;
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected) {
                cl.close();
                continue;
            }
            ConfigNode ct = cl.mMyTeamInfo;
            if (ct) {
                teams.add(ct);
            }
        }
        reply.gameConfig = gConf.saveConfigGzBuf(cfg);
        //distribute game config
        registerLog("netserver")("debug dump!");
        gConf.saveConfig(cfg, "dump.conf");
        foreach (cl; mClients) {
            cl.loadDone = false;
            if (cl.state != ClientConState.connected)
                continue;
            cl.doStartLoading(reply);
        }
        checkLoading();
    }

    private void updateLobbyInfo() {
        SPGameInfo info;
        //get info about players and their teams
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            info.players ~= cl.playerName;
            if (cl.mMyTeamInfo)
                info.teams ~= cl.mMyTeamInfo.name;
            else
                info.teams ~= "";
        }
        //send to every connected player
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            cl.doUpdateGameInfo(info);
        }
    }

    //check how far loading the game progressed on all clients
    private void checkLoading() {
        SPLoadStatus st;
        //when all clients are done, we can continue
        bool allDone = true;
        foreach (cl; mClients) {
            //assemble load status info for update packet
            st.players ~= cl.playerName;
            st.done ~= cl.loadDone;
            allDone &= cl.loadDone;
        }
        SPGameStart info;
        foreach (cl; mClients) {
            //distribute status info
            cl.doLoadStatus(st);
            //prepare game start packet with player->team assignment info
            SPGameStart.Player_Team map;
            map.player = cl.mPlayerName;
            if (cl.mMyTeamInfo)
                map.team ~= cl.mMyTeamInfo.name;
            info.mapping ~= map;
        }
        if (allDone) {
            //when all are done loading, start the game
            mState = CmdServerState.playing;
            foreach (cl; mClients) {
                cl.doGameStart(info);
            }
            //initialize and start server time
            mGameTime.resetTime();
            mMasterTime.paused = false;
            mMasterTime.initTime();
            mTimeStamp = 0;
        }
    }

    //incoming game command from a client
    private void gameCommand(CmdNetClientConnection client, char[] cmd) {
        //Stdout.formatln("Gamecommand({}): {}",client.playerName, cmd);
        assert(mState == CmdServerState.playing);
        //add to queue, for sending with next server frame
        PendingCommand pc;
        pc.client = client;
        pc.cmd = cmd;
        mPendingCommands ~= pc;
    }

    //execute a server frame
    private void gameTick() {
        //Stdout.formatln("Tick, {} commands", mPendingCommands.length);
        SPGameCommands p;
        //one packet (with one timestamp) for all commands
        //Note: this also means an empty packet will be sent when nothing
        //      has happended
        p.timestamp = mTimeStamp;
        foreach (pc; mPendingCommands) {
            GameCommandEntry e;
            e.cmd = pc.cmd;
            e.player = pc.client.playerName;
            p.commands ~= e;
        }
        //transmit
        foreach (cl; mClients) {
            cl.doGameCommands(p);
        }
        mPendingCommands = null;
        mTimeStamp++;
    }

    void printClients() {
        auto log = registerLog("netserver");
        log("Connected:");
        foreach (CmdNetClientConnection c; mClients) {
            log("  address {} state {} name '{}'", c.address, c.state,
                c.playerName);
        }
        log("playerCount={}", mPlayerCount);
    }
}

private class CCError : Exception {
    this(char[] msg) { super(msg); }
}

//peer connection state for CmdNetClientConnection
private enum ClientConState {
    establish,
    authenticate,
    connected,
    closed,
}

//Represents a connected client, also accepts/rejects connection attempts
private class CmdNetClientConnection {
    private {
        ListNode client_node;
        CmdNetServer mOwner;
        NetPeer mPeer;
        ClientConState mState;
        Time mStateEnter;
        char[] mPlayerName;
        CommandBucket mCmds;
        CommandLine mCmd;
        StringOutput mCmdOutBuffer;
        ConfigNode mMyTeamInfo;
        bool loadDone;
    }

    this(CmdNetServer owner, NetPeer peer) {
        assert(!!peer);
        mOwner = owner;
        mPeer = peer;
        mPeer.onDisconnect = &onDisconnect;
        mPeer.onReceive = &onReceive;
        mCmdOutBuffer = new StringOutput();
        state(ClientConState.establish);
        Stdout.formatln("New connection from {}", address);
        if (mOwner.state != CmdServerState.lobby) {
            closeWithReason("error_gamestarted");
        }
    }

    private void initCmds() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();
        mCmds.bind(mCmd);
    }

    NetAddress address() {
        return mPeer.address();
    }

    void close() {
        mPeer.disconnect();
    }

    void closeWithReason(char[] errorCode, char[][] args = null) {
        SPError p;
        p.errMsg = errorCode;
        p.args = args;
        send(ServerPacket.error, p, 0, true);
        close();
    }

    //enter a new state, and reset timer
    private void state(ClientConState newState) {
        mState = newState;
        mStateEnter = timeCurrentTime();
        switch (newState) {
            case ClientConState.connected:
                initCmds();
                break;
            default:
        }
    }

    ClientConState state() {
        return mState;
    }

    char[] playerName() {
        return mPlayerName;
    }

    void tick() {
        Time t = timeCurrentTime();
        switch (mState) {
            case ClientConState.authenticate:
            case ClientConState.establish:
                //only allow clients to stay 5secs in wait/auth states
                if (t - mStateEnter > timeSecs(5)) {
                    closeWithReason("error_timeout");
                }
                break;
            default:
        }
        debug if (mOutputQueue.length > 0) {
            //lag simulation
            int jitter = rngShared.next(-mOwner.mSimJitterMs,
                mOwner.mSimJitterMs);
            if (t - mOutputQueue[0].created > timeMsecs(mOwner.mSimLagMs
                + jitter))
            {
                mPeer.send(mOutputQueue[0].buf.ptr, mOutputQueue[0].buf.length,
                    mOutputQueue[0].channelId);
                mOutputQueue = mOutputQueue[1..$];
            }
        }
    }

    struct Packet {
        ubyte[] buf;
        Time created;
        ubyte channelId;
    }
    Packet[] mOutputQueue;

    private void send(T)(ServerPacket pid, T data, ubyte channelId = 0,
        bool now = false)
    {
        scope marshal = new MarshalBuffer();
        marshal.write(pid);
        marshal.write(data);
        ubyte[] buf = marshal.data();
        debug {
            if (mOwner.mSimLagMs > 0)
                //lag simulation, queue packet
                mOutputQueue ~= Packet(buf, timeCurrentTime(), channelId);
            else
                mPeer.send(buf.ptr, buf.length, channelId, now);
        } else {
            mPeer.send(buf.ptr, buf.length, channelId, now);
        }
    }

    //incoming client packet, all data (including id) is in unmarshal buffer
    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ClientPacket)();

        switch (pid) {
            case ClientPacket.error:
                auto p = unmarshal.read!(CPError)();
                Stdout.formatln("Client reported error: {}", p.errMsg);
                close();
                break;
            case ClientPacket.hello:
                    closeWithReason("error_wtf");
                    return;
                //this is the first packet a client should send after connecting
                if (mState != ClientConState.establish) {
                    closeWithReason("error_protocol");
                    return;
                }
                auto p = unmarshal.read!(CPHello)();
                //check version
                if (p.protocolVersion != cProtocolVersion) {
                    closeWithReason("error_wrongversion");
                    return;
                }
                //verify nickname and connect player (nick might be changed)
                if (!mOwner.checkNewNick(p.playerName)) {
                    closeWithReason("error_invalidnick");
                    return;
                }
                mPlayerName = p.playerName;
                //xxx no authentication for now
                state(ClientConState.connected);
                SPConAccept p_res;
                p_res.playerName = mPlayerName;
                send(ServerPacket.conAccept, p_res);
                mOwner.updateLobbyInfo();
                break;
            case ClientPacket.lobbyCmd:
                //client issued a command into the server console
                if (mState != ClientConState.connected) {
                    closeWithReason("error_protocol");
                    return;
                }
                auto p = unmarshal.read!(CPLobbyCmd)();
                SPCmdResult p_res;
                try {
                    //execute and buffer output
                    mCmdOutBuffer.text = "";
                    mCmd.execute(p.cmd);
                    p_res.success = true;
                    p_res.msg = mCmdOutBuffer.text;
                } catch (CCError e) {
                    //on fatal errors (e.g. wrong state), commands will
                    //  throw CCError; all command output is discarded
                    p_res.success = false;
                    p_res.msg = "Error: " ~ e.msg;
                }
                //transmit command result
                send(ServerPacket.cmdResult, p_res);
                break;
            case ClientPacket.startLoading:
                if (mOwner.state != CmdServerState.lobby) {
                    closeWithReason("ccerror_wrongstate");
                    return;
                }
                auto p = unmarshal.read!(CPStartLoading)();
                mOwner.ccStartGame(this, p);
                break;
            case ClientPacket.deployTeam:
                if (mState != ClientConState.connected) {
                    closeWithReason("error_protocol");
                    return;
                }
                if (mOwner.state != CmdServerState.lobby) {
                    //closeWithReason("error_gamestarted");
                    return;
                }
                auto p = unmarshal.read!(CPDeployTeam)();
                mMyTeamInfo = gConf.loadConfigGzBuf(p.teamConf);
                mMyTeamInfo.rename(p.teamName);
                mOwner.updateLobbyInfo();
                break;
            case ClientPacket.loadDone:
                if (mState != ClientConState.connected) {
                    closeWithReason("error_protocol");
                    return;
                }
                if (mOwner.state != CmdServerState.loading) {
                    return;
                }
                if (!loadDone) {
                    loadDone = true;
                    mOwner.checkLoading();
                }
                break;
            case ClientPacket.gameCommand:
                if (mState != ClientConState.connected) {
                    closeWithReason("error_protocol");
                    return;
                }
                if (mOwner.state != CmdServerState.playing) {
                    return;
                }
                auto p = unmarshal.read!(CPGameCommand)();
                mOwner.gameCommand(this, p.cmd);
                break;
            default:
                //we have reliable networking, so the client did something wrong
                closeWithReason("error_protocol");
        }
    }

    //NetPeer.onReceive
    private void onReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        assert(sender is mPeer);
        //try {
            //packet structure: 2 bytes message id + data
            if (dataLen < 2) {
                closeWithReason("error_protocol");
                return;
            }
            scope unmarshal = new UnmarshalBuffer(data[0..dataLen]);
            receive(channelId, unmarshal);
        //} catch (Exception e) {
        //    Stdout.formatln("Unhandled exception: {} at {}({})", e.toString(),
        //        e.file, e.line);
        //    closeWithReason("error_internal", [e.msg]);
        //}
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender) {
        assert(sender is mPeer);
        state(ClientConState.closed);
    }

    private void doUpdateGameInfo(SPGameInfo info) {
        send(ServerPacket.gameInfo, info);
    }

    private void doStartLoading(SPStartLoading msg) {
        send(ServerPacket.startLoading, msg);
    }

    private void doLoadStatus(SPLoadStatus st) {
        send(ServerPacket.loadStatus, st);
    }

    private void doGameStart(SPGameStart info) {
        send(ServerPacket.gameStart, info);
    }

    private void doGameCommands(SPGameCommands cmds) {
        send(ServerPacket.gameCommands, cmds);
    }
}


class CmdNetServerTask : Task {
    private {
        CmdNetServer mServer;
        Label mLabel;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        auto srvConf = gConf.loadConfigDef("server");
        mServer = new CmdNetServer(srvConf);

        mLabel = new Label();
        gWindowManager.createWindow(this, mLabel, "Server");

        mServer.start();
    }

    override protected void onKill() {
        mServer.close();
    }

    override protected void onFrame() {
        mLabel.text = myformat("Clients: {}", mServer.playerCount);
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdserver");
    }
}
