module net.cmdserver;

import common.common;
import common.task;
import framework.commandline;
import framework.timesource;
import gui.label;
import gui.widget;
import gui.wm;
import game.gamepublic;
import game.setup;
import game.gameshell : cFrameLength;  //lol
import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;

import tango.core.Thread;
import tango.io.Stdout : Stdout;

enum CmdServerState {
    lobby,
    loading,
    playing,
}

class CmdNetServer : Thread {
    private {
        GameConfig mConfig;
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
    }

    //create the server thread object
    //to actually run the server, call CmdNetServer.start()
    this(GameConfig cfg, ConfigNode serverConfig) {
        super(&run);
        mConfig = cfg;
        mConfig.teams = null;

        mClients = new typeof(mClients);

        mPort = serverConfig.getValue("port", 12499);
        mServerName = serverConfig["name"];
        if (mServerName.length == 0)
            mServerName = "Unnamed server";
        mMaxPlayers = serverConfig.getValue("max_players", 4);
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

        try {

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

        } catch (Exception e) {
            //seems this is the only way to be notified about thread errors
            Stdout.formatln("Exception {} at {}({})", e.toString(),
                e.file, e.line);
        }

        //shutdown
        foreach (cl; mClients) {
            cl.closeWithReason("server_shutdown");
        }
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
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientRemove(CmdNetClientConnection client) {
        Stdout.formatln("Client from {} ({}) disconnected",
            client.address.hostName, client.playerName);
        mClients.remove(client.client_node);
        mPlayerCount--;
        //player disconnecting in lobby
        if (mState == CmdServerState.lobby)
            updateLobbyInfo();
        //player disconnecting while loading
        if (mState == CmdServerState.loading)
            checkLoading();
    }

    private void ccStartGame(CmdNetClientConnection client) {
        if (mState != CmdServerState.lobby)
            return;
        mState = CmdServerState.loading;
        //assemble teams
        mConfig.teams = new ConfigNode();
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected) {
                cl.close();
                continue;
            }
            ConfigNode ct = cl.mMyTeamInfo;
            if (ct) {
                ct["id"] = cl.playerName ~ ":" ~ ct["id"];
                mConfig.teams.add(ct);
            }
        }
        ubyte[] confBuf = gConf.saveConfigGzBuf(mConfig.save());
        //distribute game config
        foreach (cl; mClients) {
            cl.loadDone = false;
            if (cl.state != ClientConState.connected)
                continue;
            cl.doStartLoading(confBuf);
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
            info.players ~= cl.mPlayerName;
            if (cl.mMyTeamInfo)
                info.teamIds ~= cl.mMyTeamInfo["id"];
            else
                info.teamIds ~= "";
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
        Stdout.formatln("New connection from {}", address.hostName);
        if (mOwner.state != CmdServerState.lobby) {
            closeWithReason("error_gamestarted");
        }
    }

    private void initCmds() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();
        mCmds.register(Command("start", &cmdStart, "-"));
        mCmds.bind(mCmd);
    }

    //for now, anyone can type start to run the game
    private void cmdStart(MyBox[] params, Output o) {
        if (mOwner.state != CmdServerState.lobby)
            throw new CCError("ccerror_wrongstate");
        mOwner.ccStartGame(this);
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
    }

    private void send(T)(ServerPacket pid, T data, ubyte channelId = 0,
        bool now = false)
    {
        scope marshal = new MarshalBuffer();
        marshal.write(pid);
        marshal.write(data);
        ubyte[] buf = marshal.data();
        mPeer.send(buf.ptr, buf.length, channelId, now);
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
        try {
            //packet structure: 2 bytes message id + data
            if (dataLen < 2) {
                closeWithReason("error_protocol");
                return;
            }
            scope unmarshal = new UnmarshalBuffer(data[0..dataLen]);
            receive(channelId, unmarshal);
        } catch (Exception e) {
            Stdout.formatln("Unhandled exception: {} at {}({})", e.toString(),
                e.file, e.line);
            closeWithReason("error_internal", [e.msg]);
        }
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender) {
        assert(sender is mPeer);
        state(ClientConState.closed);
    }

    private void doUpdateGameInfo(SPGameInfo info) {
        send(ServerPacket.gameInfo, info);
    }

    private void doStartLoading(ubyte[] confBuf) {
        SPStartLoading p;
        p.gameConfig = confBuf;
        send(ServerPacket.startLoading, p);
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

        ConfigNode node = gConf.loadConfig("newgame");
        auto srvConf = gConf.loadConfigDef("server");
        mServer = new CmdNetServer(loadGameConfig(node, null, false), srvConf);

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
