module net.cmdserver;

import common.config;
import framework.commandline;
import framework.timesource;
public import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import net.announce;
import net.announce_irc;
import net.announce_php;
import net.announce_lan;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;
import utils.log;
debug import utils.random;

import tango.util.Convert;

enum CmdServerState {
    lobby,
    loading,
    playing,
}

//xxx synchronize with GameShell; maybe transmit with GameConfig
const Time cFrameLength = timeMsecs(20);

class CmdNetServer {
    private {
        LogStruct!("netserver") log;

        ushort mPort;
        int mMaxPlayers, mPlayerCount;
        char[] mServerName;
        uint mMaxLag;
        List2!(CmdNetClientConnection) mClients;
        CmdServerState mState;

        NetBase mBase;
        NetHost mHost;
        NetAnnounce mAnnounce;

        struct PendingCommand {
            CmdNetClientConnection client;
            char[] cmd;
        }
        PendingCommand[] mPendingCommands;
        TimeSource mMasterTime;
        TimeSourceFixFramerate mGameTime;
        uint mTimeStamp;
        debug int mSimLagMs, mSimJitterMs;
        AnnounceInfo mAnnounceInfo;
        Time mLastInfo;
        uint[] mRecentDisconnects;

        const cInfoInterval = timeSecs(2);
        int mWormHP = 150;
        int mWormCount = 4;
        char[] mWeaponSet = "set1";
    }

    //create the server thread object
    //to actually run the server, call CmdNetServer.start()
    this(ConfigNode serverConfig) {
        mClients = new typeof(mClients);

        mPort = serverConfig.getValue("port", 12499);
        mServerName = serverConfig["name"];
        if (mServerName.length == 0)
            mServerName = "Unnamed server";
        mMaxPlayers = serverConfig.getValue("max_players", 4);
        mMaxLag = serverConfig.getValue("max_lag", 50);
        mWormHP = serverConfig.getValue("worm_hp", mWormHP);
        mWormCount = serverConfig.getValue("worm_count", mWormCount);
        mWeaponSet = serverConfig.getValue("weapon_set", mWeaponSet);
        debug {
            mSimLagMs = serverConfig.getValue("sim_lag", 0);
            mSimJitterMs = serverConfig.getValue("sim_jitter", 0);
        }

        mMasterTime = new TimeSource("ServerMasterTime");
        mMasterTime.paused = true;
        mGameTime = new TimeSourceFixFramerate("ServerGameTime", mMasterTime,
            cFrameLength);

        //create and open server
        log("Server listening on port {}", mPort);
        mBase = new NetBase();
        mHost = mBase.createServer(mPort, mMaxPlayers+1);
        mHost.onConnect = &onConnect;

        mAnnounce = new NetAnnounce(serverConfig.getSubNode("announce"));
        updateAnnounce();

        state = CmdServerState.lobby;
    }

    int playerCount() {
        return mPlayerCount;
    }

    CmdServerState state() {
        return mState;
    }
    private void state(CmdServerState newState) {
        mState = newState;
        //only announce in lobby
        mAnnounce.active = (mState == CmdServerState.lobby);
    }

    void frame() {
        //check for messages
        mHost.serviceAll();
        foreach (cl; mClients) {
            if (cl.state == ClientConState.closed) {
                clientRemove(cl);
            } else {
                cl.tick();
            }
        }
        Time t = timeCurrentTime();
        if (t - mLastInfo > cInfoInterval) {
            updatePlayerInfo();
            mLastInfo = t;
        }
        if (mState == CmdServerState.playing) {
            mMasterTime.update();
            mGameTime.update(&gameTick);
        }
        mAnnounce.tick();
    }

    //disconnect, free memory
    void shutdown() {
        foreach (cl; mClients) {
            cl.close(DiscReason.serverShutdown);
        }
        mHost.serviceAll();
        delete mAnnounce;
        delete mHost;
        delete mBase;
    }

    //validate (and possibly change) the nickname of a connecting player
    private bool checkNewNick(ref char[] nick, bool allowChange = true) {
        //no empty nicks, minimum length 3
        if (nick.length < 3)
            return false;
        //xxx check for invalid chars (e.g. space)
        //check for names already in use
        char[] curNick = nick;
        int idx = 2;
        while (true) {
            foreach (cl; mClients) {
                if (cl.state != ClientConState.establish
                    && cl.playerName == curNick)
                {
                    if (allowChange) {
                        //name is in use, append "_x" with incr. number to it
                        curNick = nick ~ "_" ~ to!(char[])(idx);
                        idx++;
                        continue;
                    } else {
                        //no modification of nick allowed, error
                        return false;
                    }
                }
            }
            break;
        }
        nick = curNick;
        return true;
    }

    //new client is trying to connect
    private void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        int newId = 0;
        ListNode insertBefore;
        //keep clients list sorted by id, and ids unique
        foreach (cl; mClients) {
            if (cl.id == newId) {
                newId++;
            } else {
                insertBefore = cl.client_node;
                break;
            }
        }
        auto cl = new CmdNetClientConnection(this, peer, newId);
        if (mPlayerCount >= mMaxPlayers)
            cl.close(DiscReason.serverFull);
        if (cl.state != ClientConState.establish)
            //connection was rejected
            return;
        Trace.formatln("New connection from {}, id = {}", cl.address, cl.id);
        cl.client_node = mClients.insert_before(cl, insertBefore);
        mPlayerCount++;
        updateAnnounce();
        printClients();
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientRemove(CmdNetClientConnection client) {
        Trace.formatln("Client from {} ({}) disconnected",
            client.address, client.playerName);
        //store id, to notify other players
        if (mState == CmdServerState.playing)
            mRecentDisconnects ~= client.id;
        mClients.remove(client.client_node);
        mPlayerCount--;
        updateAnnounce();
        printClients();
        //update client's player list
        updatePlayerList();
        //player disconnecting while loading
        if (mState == CmdServerState.loading)
            checkLoading();
    }

    private void ccStartGame(CmdNetClientConnection client, CPStartLoading msg)
    {
        if (mState != CmdServerState.lobby)
            return;
        state = CmdServerState.loading;
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
                //xxx this whole function is one giant hack, this just adds a little
                //  more hackiness -->
                char[][] wormNames;
                foreach (ConfigNode sub; ct.getSubNode("member_names")) {
                    wormNames ~= sub.value;
                }
                if (wormNames.length > mWormCount)
                    wormNames.length = mWormCount;
                else if (wormNames.length < mWormCount) {
                    for (int i = wormNames.length; i < mWormCount; i++) {
                        wormNames ~= myformat("Worm {}", i);
                    }
                }
                ct.remove("member_names");
                foreach (wn; wormNames) {
                    ct.getSubNode("member_names").add("", wn);
                }
                ct.setValue("power", mWormHP);
                ct["weapon_set"] = mWeaponSet;
                //<-- big hack end
                teams.addNode(ct);
            }
        }
        reply.gameConfig = gConf.saveConfigGzBuf(cfg);
        //distribute game config
        log("debug dump!");
        gConf.saveConfig(cfg, "dump.conf");
        foreach (cl; mClients) {
            cl.loadDone = false;
            if (cl.state != ClientConState.connected)
                continue;
            cl.doStartLoading(reply);
        }
        checkLoading();
    }

    int opApply(int delegate(ref CmdNetClientConnection cl) del) {
        foreach (cl; mClients) {
            int res = del(cl);
            if (res)
                return res;
        }
        return 0;
    }

    //send a packet to every connected player
    private void sendAll(T)(ServerPacket pid, T data, ubyte channelId = 0) {
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            cl.send(pid, data, channelId);
        }
    }

    //send the current player list to all clients
    private void updatePlayerList() {
        SPPlayerList plist;
        //get info about players
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            auto p = SPPlayerList.Player(cl.id, cl.playerName);
            if (cl.mMyTeamInfo)
                p.teamName = cl.mMyTeamInfo.name;
            plist.players ~= p;
        }
        sendAll(ServerPacket.playerList, plist);
    }

    //send some player information to clients
    private void updatePlayerInfo() {
        //we can assume that id->playerName mapping on client is correct,
        //because updatePlayerList() is called on connection/disconnection
        SPPlayerInfo info;
        info.updateFlags = SPPlayerInfo.Flags.ping;
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            SPPlayerInfo.Details det;
            det.id = cl.id;
            det.ping = cl.ping;
            info.players ~= det;
        }
        sendAll(ServerPacket.playerInfo, info);
    }

    //check how far loading the game progressed on all clients
    private void checkLoading() {
        SPLoadStatus st;
        //when all clients are done, we can continue
        bool allDone = true;
        foreach (cl; mClients) {
            //assemble load status info for update packet
            st.playerIds ~= cl.id;
            st.done ~= cl.loadDone;
            allDone &= cl.loadDone;
        }
        SPGameStart info;
        foreach (cl; mClients) {
            //distribute status info
            cl.doLoadStatus(st);
            //prepare game start packet with player->team assignment info
            SPGameStart.Player_Team map;
            map.playerId = cl.id;
            if (cl.mMyTeamInfo)
                map.team ~= cl.mMyTeamInfo.name;
            info.mapping ~= map;
        }
        if (allDone) {
            //when all are done loading, start the game
            state = CmdServerState.playing;
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
        //Trace.formatln("Gamecommand({}): {}",client.playerName, cmd);
        assert(mState == CmdServerState.playing);
        //add to queue, for sending with next server frame
        PendingCommand pc;
        pc.client = client;
        pc.cmd = cmd;
        mPendingCommands ~= pc;
    }

    //execute a server frame
    private void gameTick() {
        //Trace.formatln("Tick, {} commands", mPendingCommands.length);
        CmdNetClientConnection[] lagClients;
        foreach (cl; mClients) {
            if (mTimeStamp - cl.lastAckTS > mMaxLag)
                lagClients ~= cl;
        }
        if (lagClients.length > 0) {
            //don't execute frame
            //xxx inform players
            //    also, is it ok to let mGameTime continue?
            return;
        }
        SPGameCommands p;
        //one packet (with one timestamp) for all commands
        //Note: this also means an empty packet will be sent when nothing
        //      has happended
        p.timestamp = mTimeStamp;
        if (mRecentDisconnects.length > 0) {
            //notify players about disconnected clients
            //affects gameplay, so with timestamp
            p.disconnectIds = mRecentDisconnects;
            mRecentDisconnects.length = 0;
        }
        foreach (pc; mPendingCommands) {
            GameCommandEntry e;
            e.cmd = pc.cmd;
            e.playerId = pc.client.id;
            p.commands ~= e;
        }
        //transmit
        sendAll(ServerPacket.gameCommands, p);
        mPendingCommands = null;
        mTimeStamp++;
    }

    void updateAnnounce() {
        mAnnounceInfo.serverName = mServerName;
        mAnnounceInfo.port = mPort;
        mAnnounceInfo.maxPlayers = mMaxPlayers;
        mAnnounceInfo.curPlayers = mPlayerCount;
        mAnnounce.update(mAnnounceInfo);
    }

    void printClients() {
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
enum ClientConState {
    establish,
    authenticate,
    connected,
    closed,
}

//Represents a connected client, also accepts/rejects connection attempts
class CmdNetClientConnection {
    private {
        ListNode client_node;
        CmdNetServer mOwner;
        NetPeer mPeer;
        ClientConState mState;
        Time mStateEnter, mLastPing;
        char[] mPlayerName;
        CommandBucket mCmds;
        CommandLine mCmd;
        StringOutput mCmdOutBuffer;
        ConfigNode mMyTeamInfo;
        bool loadDone;
        uint mId;  //immutable during lifetime

        const cPingInterval = timeSecs(1.5); //ping every x seconds...
        const cPingAvgOver = timeSecs(9); //and average the result over y

        struct PongEntry {
            Time cur = Time.Never, rtt = Time.Never;
        }
        PongEntry[10] mPongs; //enough room for all pings in cPingAvgOver
        int mPongIdx;
        Time mAvgPing = timeMsecs(100);
        uint mLastAckTS;
    }

    private this(CmdNetServer owner, NetPeer peer, uint id) {
        assert(!!peer);
        mOwner = owner;
        mId = id;
        mPeer = peer;
        mPeer.onDisconnect = &onDisconnect;
        mPeer.onReceive = &onReceive;
        mCmdOutBuffer = new StringOutput();
        state(ClientConState.establish);
        if (mOwner.state != CmdServerState.lobby) {
            close(DiscReason.gameStarted);
        }
    }

    private void initCmds() {
        mCmd = new CommandLine(mCmdOutBuffer);
        mCmd.setPrefix("/", "say"); //code duplication in client
        mCmds = new CommandBucket();
        mCmds.registerCommand("name", &cmdName, "Change your nickname",
            ["text:new nickname"]);
        mCmds.bind(mCmd);
    }

    private void cmdName(MyBox[] args, Output write) {
        char[] newName = args[0].unbox!(char[]);
        if (newName == mPlayerName) {
            throw new CCError("Your nickname already is " ~ mPlayerName ~ ".");
        }
        if (!mOwner.checkNewNick(newName, false)) {
            throw new CCError("Invalid nickname or name already in use.");
        }
        mPlayerName = newName;
        write.writefln("Your new nickname is {}", mPlayerName);
        mOwner.updatePlayerList();
    }

    NetAddress address() {
        return mPeer.address();
    }

    uint id() {
        return mId;
    }

    void close(DiscReason why = DiscReason.none) {
        mPeer.disconnect(why);
        state(ClientConState.closed);
    }

    //transmit a non-fatal error message
    private void sendError(char[] errorCode, char[][] args = null) {
        SPError p;
        p.errMsg = errorCode;
        p.args = args;
        send(ServerPacket.error, p, 0, true);
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

    private void tick() {
        Time t = timeCurrentTime();
        if (t - mLastPing > cPingInterval) {
            //ping clients every cPingInterval (internal enet ping is crap)
            SPPing p = SPPing(t);
            send(ServerPacket.ping, p, 1, true, false);
            mLastPing = t;
        }
        switch (mState) {
            case ClientConState.authenticate:
            case ClientConState.establish:
                //only allow clients to stay 5secs in wait/auth states
                if (t - mStateEnter > timeSecs(5)) {
                    close(DiscReason.timeout);
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
                    mOutputQueue[0].channelId, false, mOutputQueue[0].reliable,
                    mOutputQueue[0].reliable);
                mOutputQueue = mOutputQueue[1..$];
            }
        }
    }

    debug {
        struct Packet {
            ubyte[] buf;
            Time created;
            ubyte channelId;
            bool reliable;
        }
        Packet[] mOutputQueue;
    }

    private void send(T)(ServerPacket pid, T data, ubyte channelId = 0,
        bool now = false, bool reliable = true)
    {
        scope marshal = new MarshalBuffer();
        marshal.write(pid);
        marshal.write(data);
        ubyte[] buf = marshal.data();
        debug {
            if (mOwner.mSimLagMs > 0)
                //lag simulation, queue packet
                mOutputQueue ~= Packet(buf, timeCurrentTime(), channelId,
                    reliable);
            else
                mPeer.send(buf.ptr, buf.length, channelId, now, reliable,
                    reliable);
        } else {
            mPeer.send(buf.ptr, buf.length, channelId, now, reliable, reliable);
        }
    }

    //incoming client packet, all data (including id) is in unmarshal buffer
    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ClientPacket)();

        switch (pid) {
            case ClientPacket.error:
                auto p = unmarshal.read!(CPError)();
                Trace.formatln("Client reported error: {}", p.errMsg);
                break;
            case ClientPacket.hello:
                //this is the first packet a client should send after connecting
                if (mState != ClientConState.establish) {
                    close(DiscReason.protocolError);
                    return;
                }
                auto p = unmarshal.read!(CPHello)();
                //check version
                if (p.protocolVersion != cProtocolVersion) {
                    close(DiscReason.wrongVersion);
                    return;
                }
                //verify nickname and connect player (nick might be changed)
                if (!mOwner.checkNewNick(p.playerName)) {
                    close(DiscReason.invalidNick);
                    return;
                }
                mPlayerName = p.playerName;
                //xxx no authentication for now
                state(ClientConState.connected);
                SPConAccept p_res;
                p_res.id = mId;
                p_res.playerName = mPlayerName;
                send(ServerPacket.conAccept, p_res);
                mOwner.updatePlayerList();
                break;
            case ClientPacket.lobbyCmd:
                //client issued a command into the server console
                if (mState != ClientConState.connected) {
                    close(DiscReason.protocolError);
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
                    p_res.msg = e.msg;
                }
                //transmit command result
                send(ServerPacket.cmdResult, p_res);
                break;
            case ClientPacket.startLoading:
                if (mOwner.state != CmdServerState.lobby) {
                    //tried to host while game already started, not fatal
                    sendError("ccerror_wrongstate");
                    return;
                }
                auto p = unmarshal.read!(CPStartLoading)();
                mOwner.ccStartGame(this, p);
                break;
            case ClientPacket.deployTeam:
                if (mState != ClientConState.connected) {
                    close(DiscReason.protocolError);
                    return;
                }
                if (mOwner.state != CmdServerState.lobby) {
                    //close(DiscReason.gameStarted);
                    return;
                }
                auto p = unmarshal.read!(CPDeployTeam)();
                mMyTeamInfo = gConf.loadConfigGzBuf(p.teamConf);
                mMyTeamInfo.rename(p.teamName);
                mOwner.updatePlayerList();
                break;
            case ClientPacket.loadDone:
                if (mState != ClientConState.connected) {
                    close(DiscReason.protocolError);
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
                    close(DiscReason.protocolError);
                    return;
                }
                if (mOwner.state != CmdServerState.playing) {
                    return;
                }
                auto p = unmarshal.read!(CPGameCommand)();
                mOwner.gameCommand(this, p.cmd);
                break;
            case ClientPacket.ack:
                auto p = unmarshal.read!(CPAck)();
                if (p.timestamp > mOwner.mTimeStamp)
                    close(DiscReason.protocolError);
                else
                    mLastAckTS = p.timestamp;
                break;
            case ClientPacket.pong:
                auto p = unmarshal.read!(CPPong)();
                Time rtt = timeCurrentTime() - p.ts;
                gotPong(rtt);
                break;
            default:
                //we have reliable networking, so the client did something wrong
                close(DiscReason.protocolError);
        }
    }

    uint lastAckTS() {
        return mLastAckTS;
    }

    private void gotPong(Time rtt) {
        Time t = timeCurrentTime();

        mPongs[mPongIdx].cur = t;
        mPongs[mPongIdx].rtt = rtt;
        mPongIdx = (mPongIdx+1) % mPongs.length;

        //calculate average of cached pongs
        Time pa;
        int count;
        foreach (ref pv; mPongs) {
            if (pv.cur != Time.Never && t - pv.cur < cPingAvgOver) {
                pa += pv.rtt;
                count++;
            }
        }
        //we just got a pong, so there's at least that
        assert(count > 0);
        mAvgPing = pa / count;
        //Trace.formatln("Ping: {} (avg = {})", rtt, ping());
    }

    Time ping() {
        return mAvgPing;
    }

    //NetPeer.onReceive
    private void onReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        assert(sender is mPeer);
        //packet structure: 2 bytes message id + data
        if (dataLen < 2) {
            close(DiscReason.protocolError);
            return;
        }
        scope unmarshal = new UnmarshalBuffer(data[0..dataLen]);
        try {
            receive(channelId, unmarshal);
        } catch (UnmarshalException e) {
            //malformed packet, unmarshalling failed
            close(DiscReason.protocolError);
        }
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender, uint code) {
        assert(sender is mPeer);
        if (code > 0)
            Trace.formatln("Client disconnected with error: {}",
                reasonToString[code]);
        state(ClientConState.closed);
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
}

//as command line program
version (CmdServerMain):

import tango.io.Stdout;

import common.init;
import framework.filesystem;

void main(char[][] args) {
    auto cmdargs = init(args, "no help lol");
    if (!cmdargs)
        return;
    auto server = new CmdNetServer(gConf.loadConfigDef("server"));
    while (true) {
        server.frame();
    }
    server.shutdown();
    Stdout.formatln("bye.");
}
