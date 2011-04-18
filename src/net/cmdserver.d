module net.cmdserver;

import framework.config;
import framework.commandline;
import game.temp;
public import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import net.announce;
import net.announce_php;
import net.announce_lan;
import utils.configfile;
import utils.time;
import utils.timesource;
import utils.list2;
import utils.output;
import utils.log;
import utils.misc;
import utils.array;
import utils.queue;
debug import utils.random;

import tango.core.Thread; //for yield()
import tango.util.Convert;
import xout = tango.io.Stdout;

//version = LagDebug;

enum CmdServerState {
    lobby,
    loading,
    playing,
}

class CmdNetServer {
    private {
        LogStruct!("netserver") log;

        ushort mPort;
        int mMaxPlayers, mPlayerCount;
        string mServerName;
        uint mMaxLag;
        public ObjectList!(CmdNetClientConnection, "client_node") mClients;
        CmdServerState mState;

        NetBase mBase;
        NetHost mHost;
        NetAnnounce mAnnounce;

        struct PendingCommand {
            CmdNetClientConnection client;
            string cmd;
        }
        PendingCommand[] mPendingCommands;
        TimeSource mMasterTime;
        TimeSourceFixFramerate mGameTime;
        uint mTimeStamp;
        debug int mSimLagMs, mSimJitterMs;
        AnnounceInfo mAnnounceInfo;
        Time mLastInfo;
        uint[] mRecentDisconnects;
        MarshalBuffer mQueryMarshal;

        const cInfoInterval = timeSecs(2);
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
        debug {
            mSimLagMs = serverConfig.getValue("sim_lag", 0);
            mSimJitterMs = serverConfig.getValue("sim_jitter", 0);
        }

        mMasterTime = new TimeSource("ServerMasterTime");
        mGameTime = new TimeSourceFixFramerate("ServerGameTime", mMasterTime,
            cFrameLength);

        mQueryMarshal = new MarshalBuffer();

        //create and open server
        log.notice("Server listening on port {}", mPort);
        mBase = new NetBase();
        mHost = mBase.createServer(mPort, mMaxPlayers+1);
        mHost.onConnect = &onConnect;
        mHost.onPacketPreview = &onPacketPreview;

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
        if (mState == CmdServerState.loading) {
            foreach (cl; mClients) {
                cl.gameTerminated = false;
            }
            mRecentDisconnects = null;
        } else if (mState == CmdServerState.playing) {
            //initialize and start server time
            mGameTime.resetTime();
            mMasterTime.paused = false;
            mMasterTime.initTime();
            mTimeStamp = 0;
            foreach (cl; mClients) {
                cl.resetGameState();
            }
        } else {
            mMasterTime.paused = true;
        }
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
            bool allFinished = true;
            foreach (cl; mClients) {
                allFinished &= cl.gameTerminated;
            }
            if (allFinished)
                state = CmdServerState.lobby;
            else {
                mMasterTime.update();
                mGameTime.update(&gameTick);
            }
        }
        mAnnounce.tick();
    }

    //disconnect, free memory
    void shutdown() {
        log.notice("Server shutting down");
        foreach (cl; mClients) {
            cl.close("server shutdown", DiscReason.serverShutdown);
        }
        mHost.serviceAll();
        mAnnounce.close();
        delete mHost;
        delete mBase;
    }

    void announceInternet(bool yes) {
        mAnnounce.announceInternet = yes;
    }

    //validate (and possibly change) the nickname of a connecting player
    private bool checkNewNick(ref string nick, bool allowChange = true) {
        //no empty nicks, minimum length 3
        if (nick.length < 3)
            return false;
        //xxx check for invalid chars (e.g. space)
        //check for names already in use
        string curNick = nick;
        int idx = 2;
        while (true) {
            foreach (cl; mClients) {
                if (cl.state != ClientConState.establish
                    && cl.playerName == curNick)
                {
                    if (allowChange) {
                        //name is in use, append "_x" with incr. number to it
                        curNick = nick ~ "_" ~ to!(string)(idx);
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

    //preview packets to the listening socket and look for server queries
    //return true if a custom packet was processed (to keep it away from enet)
    //xxx opening a second socket for queries would also be possible (and a lot
    //    of games do it), but I would consider that a dirty hack because it
    //    would cause problems with NAT and require a game port to be
    //    transmitted with the query response
    private bool onPacketPreview(NetHost sender, IPv4Address from,
        ubyte[] data)
    {
        if (data.length == cQueryIdent.length
            && data[0..cQueryIdent.length] == cast(ubyte[])cQueryIdent)
        {
            //query request, send server information
            QueryResponse resp;
            resp.serverName = mServerName;
            resp.curPlayers = mPlayerCount;
            resp.maxPlayers = mMaxPlayers;
            //xxx
            resp.players = null;

            mQueryMarshal.reset();
            mQueryMarshal.writeRaw(cast(ubyte[])cQueryIdent);
            mQueryMarshal.write(cProtocolVersion);
            mQueryMarshal.write(resp);
            mHost.socket.sendTo(mQueryMarshal.data, from);
            return true;
        }
        return false;
    }

    //new client is trying to connect
    private void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        int newId = 0;
        CmdNetClientConnection insertBefore;
        //keep clients list sorted by id, and ids unique
        foreach (cl; mClients) {
            if (cl.id == newId) {
                newId++;
            } else {
                insertBefore = cl;
                break;
            }
        }
        auto cl = new CmdNetClientConnection(this, peer, newId);
        if (mPlayerCount >= mMaxPlayers)
            cl.close("server full", DiscReason.serverFull);
        if (cl.state != ClientConState.establish)
            //connection was rejected
            return;
        log.minor("New connection from {}, id = {}", cl.address, cl.id);
        mClients.insert_before(cl, insertBefore);
        mPlayerCount++;
        updateAnnounce();
        printClients();
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientRemove(CmdNetClientConnection client) {
        log.minor("Client from {} ({}) disconnected",
            client.address, client.playerName);
        //store id, to notify other players
        if ((mState == CmdServerState.playing
            || mState == CmdServerState.loading) && !client.gameTerminated)
        {
            mRecentDisconnects ~= client.id;
        }
        mClients.remove(client);
        mPlayerCount--;
        updateAnnounce();
        printClients();
        //update client's player list
        updatePlayerList();
        //player disconnecting while loading
        if (mState == CmdServerState.loading)
            checkLoading();
    }

    //A client wants to start a game and asks for permission
    //here, we check if no other client is currently setting up a game
    private void doRequestCreateGame(CmdNetClientConnection client) {
        if (mState != CmdServerState.lobby)
            return;
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected || cl is client)
                continue;
            if (cl.hasHostPermission()) {
                client.sendError("error_permissiondenied");
                return;
            }
        }
        //ok, player is allowed to host
        client.hostRequestTime = timeCurrentTime();
        SPGrantCreateGame p;
        p.playerId = client.id;
        p.state = SPGrantCreateGame.State.granted;
        //notify everybody
        sendAll(ServerPacket.grantCreateGame, p);
    }

    //A client is about to start a game and asks for the
    //  required data (i.e. team info)
    private void doPrepareCreateGame(CmdNetClientConnection client) {
        if (mState != CmdServerState.lobby)
            return;
        //xxx need more checks, e.g. if client is the "admin user",
        //    or at least if another client is already hosting a game
        SPAcceptCreateGame p;
        foreach (cl; mClients) {
            if (cl.mTeamName.length > 0) {
                SPAcceptCreateGame.Team pt;
                pt.playerId = cl.id;
                pt.teamName = cl.mTeamName;
                pt.teamConf = cl.mTeamData;
                p.teams ~= pt;
            }
        }
        client.send(ServerPacket.acceptCreateGame, p);
    }

    //A client sends a (complete) GameConfig, broadcast it to all players
    private void doStartGame(CmdNetClientConnection client, CPCreateGame msg)
    {
        if (mState != CmdServerState.lobby)
            return;
        state = CmdServerState.loading;
        //no more new connections
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected) {
                cl.close("disconnect leftovers");
                continue;
            }
            cl.loadDone = false;
        }
        SPStartLoading reply;
        reply.gameConfig = msg.gameConfig;
        //distribute game config
        sendAll(ServerPacket.startLoading, reply);
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

    private void listConnectedClients(void delegate(CmdNetClientConnection) d) {
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            d(cl);
        }
    }

    //send a packet to every connected player
    private void sendAll(T)(ServerPacket pid, T data, ubyte channelId = 0) {
        listConnectedClients((CmdNetClientConnection cl) {
            cl.send(pid, data, channelId);
        });
    }

    //send the current player list to all clients
    private void updatePlayerList() {
        SPPlayerList plist;
        //get info about players
        foreach (cl; mClients) {
            if (cl.state != ClientConState.connected)
                continue;
            auto p = SPPlayerList.Player(cl.id, cl.playerName);
            if (cl.mTeamName.length > 0)
                p.teamName = cl.mTeamName;
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
            if (cl.gameTerminated)
                continue;
            //assemble load status info for update packet
            st.playerIds ~= cl.id;
            st.done ~= cl.loadDone;
            allDone &= cl.loadDone;
        }
        sendAll(ServerPacket.loadStatus, st);

        SPGameStart info;
        if (allDone) {
            //when all are done loading, start the game
            sendAll(ServerPacket.gameStart, info);
            state = CmdServerState.playing;
        }
    }

    //incoming game command from a client
    private void gameCommand(CmdNetClientConnection client, string cmd) {
        //Trace.formatln("Gamecommand({}): {}",client.playerName, cmd);
        assert(mState == CmdServerState.playing);
        //add to queue, for sending with next server frame
        PendingCommand pc;
        pc.client = client;
        pc.cmd = cmd;
        mPendingCommands ~= pc;
    }

    private void gameTerminated(CmdNetClientConnection client) {
        if (mState == CmdServerState.playing
            || mState == CmdServerState.loading)
        {
            mRecentDisconnects ~= client.id;
        }
        if (mState == CmdServerState.loading) {
            checkLoading();
        }
    }

    //compare CPAck packets from all clients
    //all packets should be the same (timestamp and hash),
    //  if not something is wrong
    private void performHashCheck() {
        //find the hash value appearing most
        MajorityCounter!(CPAck) majority;
        //randomize the returned element on equal count (for security)
        //  else, in 1vs1 one client could intentionally send an invalid
        //  hash to disconnect the other if he is the first client
        majority.random = true;
        foreach (cl; mClients) {
            if (cl.gameTerminated)
                continue;
            assert(cl.hasAck());
            majority.count(cl.topAck());
        }
        CPAck expected = majority.result;
        //now compare and notify the minority
        foreach (cl; mClients) {
            if (cl.gameTerminated)
                continue;
            //remove the ack packet from the queue
            CPAck ack = cl.popAck();
            //compare with expectation
            if (expected != ack) {
                if (expected.timestamp != ack.timestamp) {
                    //acks are sent in order at a fixed interval, so if the
                    //  ack timestamp doesn't match, the client implementation
                    //  is somehow wrong, or crap was sent
                    cl.close("ack for wrong timestamp",
                        DiscReason.internalError);
                } else {
                    //handleDesync will notify the client that his game is
                    //  out of sync; the client should then cause the game to
                    //  terminate (or just display a message)
                    cl.handleDesync(expected.timestamp, ack.hash,
                        expected.hash);
                }
            }
        }
    }

    //execute a server frame
    private void gameTick(Time overdue) {
        //Trace.formatln("Tick, {} commands", mPendingCommands.length);
        CmdNetClientConnection[] lagClients;
        bool haveAllAck = true;
        foreach (cl; mClients) {
            if (cl.gameTerminated)
                continue;
            if (mTimeStamp - cl.lastAckTS > mMaxLag)
                lagClients ~= cl;
            haveAllAck &= cl.hasAck();
        }
        if (lagClients.length > 0) {
            //don't execute frame
            //xxx inform players
            //    also, is it ok to let mGameTime continue?
            return;
        }
        if (haveAllAck) {
            //if there is an Ack packet from all playing clients, do a
            //  hash check
            //Note: because ack packets are received in order, the waiting
            //      Ack packet has to be for the same timestamp for every client
            performHashCheck();
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
        //mAnnounceInfo.serverName = mServerName;
        mAnnounceInfo.port = mPort;
        //mAnnounceInfo.maxPlayers = mMaxPlayers;
        //mAnnounceInfo.curPlayers = mPlayerCount;
        mAnnounce.update(mAnnounceInfo);
    }

    void printClients() {
        log.notice("Connected:");
        foreach (CmdNetClientConnection c; mClients) {
            log.notice("  address {} state {} name '{}'", c.address, c.state,
                c.playerName);
        }
        log.notice("playerCount={}", mPlayerCount);
    }
}

private class CCError : CustomException {
    this(string msg) { super(msg); }
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
        LogStruct!("netserver_peer") log;

        public ObjListNode!(typeof(this)) client_node;
        CmdNetServer mOwner;
        NetPeer mPeer;
        //this is just to keep the temporary memory without reallocating
        MarshalBuffer mMarshal;
        ClientConState mState;
        Time mStateEnter, mLastPing;
        string mPlayerName;
        CommandBucket mCmds;
        CommandLine mCmd;
        StringOutput mCmdOutBuffer;
        ubyte[] mTeamData;
        string mTeamName;
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
        uint lastAckTS = 0;
        Queue!(CPAck) mAckQueue;
        bool mDesyncSent;
        bool gameTerminated;

        //time when this client requested to host a game
        Time hostRequestTime = Time.Never;
        //time a player has from opening the "create game" dialog to clicking ok
        const cHostTimeout = timeSecs(30);
    }

    private this(CmdNetServer owner, NetPeer peer, uint id) {
        assert(!!peer);
        mOwner = owner;
        mId = id;
        mPeer = peer;
        mPeer.onDisconnect = &onDisconnect;
        mPeer.onReceive = &onReceive;
        mCmdOutBuffer = new StringOutput();
        mMarshal = new MarshalBuffer();
        mAckQueue = new typeof(mAckQueue);
        state(ClientConState.establish);
        if (mOwner.state != CmdServerState.lobby) {
            close("game started", DiscReason.gameStarted);
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
        string newName = args[0].unbox!(string);
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

    void close(string desc, DiscReason why = DiscReason.none) {
        log.notice("disconnect peer {}, code={}, reason: {}", id(), why, desc);
        mPeer.disconnect(why);
        state(ClientConState.closed);
    }

    //transmit a non-fatal error message
    private void sendError(string errorCode, string[] args = null) {
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

    string playerName() {
        return mPlayerName;
    }

    //true if there is an Ack packet waiting
    bool hasAck() {
        return !mAckQueue.empty();
    }

    CPAck popAck() {
        return mAckQueue.pop();
    }

    CPAck topAck() {
        return mAckQueue.top();
    }

    void resetGameState() {
        mAckQueue.clear();
        lastAckTS = 0;
        mDesyncSent = false;
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
                    close("timeout", DiscReason.timeout);
                }
                break;
            default:
        }
        version(LagDebug) if (mOutputQueue.length > 0) {
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

    bool hasHostPermission() {
        return hostRequestTime != Time.Never
            && timeCurrentTime() - hostRequestTime < cHostTimeout;
    }

    version(LagDebug) {
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
        mMarshal.reset();
        mMarshal.write(pid);
        mMarshal.write(data);
        ubyte[] buf = mMarshal.data();
        version(LagDebug) {
            if (mOwner.mSimLagMs > 0)
                //lag simulation, queue packet
                mOutputQueue ~= Packet(buf.dup, timeCurrentTime(), channelId,
                    reliable);
            else
                mPeer.send(buf, channelId, now, reliable, reliable);
        } else {
            mPeer.send(buf, channelId, now, reliable, reliable);
        }
    }

    //broadcast this data to all clients using the SPClientBroadcast message
    private void sendClientBroadcast(ubyte[] data) {
        mMarshal.reset();
        mMarshal.write(ServerPacket.clientBroadcast);
        SPClientBroadcast p;
        p.senderPlayerId = mId;
        mMarshal.write(p);
        mMarshal.writeRaw(data);
        ubyte[] buf = mMarshal.data();
        mOwner.listConnectedClients((CmdNetClientConnection cl) {
            cl.mPeer.send(buf, 0, false, true, true);
        });
    }

    void handleDesync(uint timestamp, EngineHash hash, EngineHash expected) {
        //send only once per round
        if (mDesyncSent)
            return;
        mDesyncSent = true;
        log.warn("Game is out of sync for player '{}'", mPlayerName);
        log.warn("  Timestamp: {}  Hash: {}  Expected: {}", timestamp,
            hash, expected);

        SPGameAsync p;
        p.timestamp = timestamp;
        p.hash = hash;
        p.expected = expected;
        send(ServerPacket.gameAsync, p);
    }

    //incoming client packet, all data (including id) is in unmarshal buffer
    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ClientPacket)();

        switch (pid) {
            case ClientPacket.error:
                auto p = unmarshal.read!(CPError)();
                log.warn("Client reported error: {}", p.errMsg);
                break;
            case ClientPacket.hello:
                //this is the first packet a client should send after connecting
                if (mState != ClientConState.establish) {
                    close("hello packet wrong state", DiscReason.protocolError);
                    return;
                }
                auto p = unmarshal.read!(CPHello)();
                //check version
                if (p.protocolVersion != cProtocolVersion) {
                    close("wrong protocol version", DiscReason.wrongVersion);
                    return;
                }
                //verify nickname and connect player (nick might be changed)
                if (!mOwner.checkNewNick(p.playerName)) {
                    close("invalid nick", DiscReason.invalidNick);
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
                    close("lobbycmd packet wrong state",
                        DiscReason.protocolError);
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
            case ClientPacket.requestCreateGame:
                auto p = unmarshal.read!(CPRequestCreateGame)();
                if (p.request)
                    mOwner.doRequestCreateGame(this);
                else {
                    if (hasHostPermission()) {
                        SPGrantCreateGame reply;
                        reply.playerId = id;
                        reply.state = SPGrantCreateGame.State.revoked;
                        //notify everybody
                        mOwner.sendAll(ServerPacket.grantCreateGame, reply);
                    }
                    hostRequestTime = Time.Never;
                }
                break;
            case ClientPacket.prepareCreateGame:
                if (mOwner.state != CmdServerState.lobby) {
                    //tried to host while game already started, not fatal
                    sendError("error_wrongstate");
                    return;
                }
                //notify everybody
                SPGrantCreateGame reply;
                reply.playerId = id;
                reply.state = SPGrantCreateGame.State.starting;
                mOwner.sendAll(ServerPacket.grantCreateGame, reply);
                //remove hosting permission
                hostRequestTime = Time.Never;
                mOwner.doPrepareCreateGame(this);
                break;
            case ClientPacket.createGame:
                if (mOwner.state != CmdServerState.lobby) {
                    //tried to host while game already started, not fatal
                    sendError("error_wrongstate");
                    return;
                }
                auto p = unmarshal.read!(CPCreateGame)();
                mOwner.doStartGame(this, p);
                break;
            case ClientPacket.deployTeam:
                if (mState != ClientConState.connected) {
                    close("deplayteam packet wrong state",
                        DiscReason.protocolError);
                    return;
                }
                if (mOwner.state != CmdServerState.lobby) {
                    //close(DiscReason.gameStarted);
                    return;
                }
                auto p = unmarshal.read!(CPDeployTeam)();
                mTeamData = p.teamConf;
                mTeamName = p.teamName;
                mOwner.updatePlayerList();
                break;
            case ClientPacket.loadDone:
                if (mState != ClientConState.connected) {
                    close("loaddone packet wrong state",
                        DiscReason.protocolError);
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
                    close("gamecommand wrong state", DiscReason.protocolError);
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
                    close("timestamp from future", DiscReason.protocolError);
                else {
                    lastAckTS = p.timestamp;
                    mAckQueue.push(p);
                }
                log.trace("[{}] Ack for frame {}, hash = {}", mId, p.timestamp,
                    p.hash);
                break;
            case ClientPacket.pong:
                auto p = unmarshal.read!(CPPong)();
                Time rtt = timeCurrentTime() - p.ts;
                gotPong(rtt);
                break;
            case ClientPacket.clientBroadcast:
                sendClientBroadcast(unmarshal.getRest());
                break;
            case ClientPacket.gameTerminated:
                mOwner.gameTerminated(this);
                gameTerminated = true;
                break;
            default:
                //we have reliable networking, so the client did something wrong
                close("unknown packet id", DiscReason.protocolError);
        }
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
    private void onReceive(NetPeer sender, ubyte channelId, ubyte[] data) {
        assert(sender is mPeer);
        scope unmarshal = new UnmarshalBuffer(data);
        try {
            receive(channelId, unmarshal);
        } catch (UnmarshalException e) {
            //malformed packet, unmarshalling failed
            close("unmarshalling error", DiscReason.protocolError);
        }
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender, uint code) {
        assert(sender is mPeer);
        if (code > 0)
            log.error("Client disconnected with error: {}",
                reasonToString[code]);
        state(ClientConState.closed);
    }
}


//code for standalone server (called from lumbricus.d and lumbricus_server.d)

//when this gets true, server will shutdown
bool gTerminate = false;

void runCmdServer() {
    setupConsole("Lumbricus Server");
    auto server = new CmdNetServer(loadConfigDef("server.conf"));
    scope(exit) server.shutdown();
    while (!gTerminate) {
        server.frame();
        Thread.yield();
    }
}

version(Windows) {
    import tango.sys.win32.UserGdi : SetConsoleTitleA, SetConsoleCtrlHandler;
    import tango.stdc.stringz : toStringz;

    extern(Windows) int CtrlHandler(uint dwCtrlType) {
        gTerminate = true;
        //make Windows not kill us immediately
        return 1;
    }

    void setupConsole(string title) {
        //looks nicer
        SetConsoleTitleA(toStringz(title));
        //handle Ctrl-C for graceful termination
        SetConsoleCtrlHandler(&CtrlHandler, 1);
    }
} else version (linux) {
    import tango.stdc.signal;

    extern(C) void sighandler(int sig) {
        gTerminate = true;
    }

    void setupConsole(string title) {
        xout.Stdout.formatln("\033]0;{}\007", title);
        signal(SIGINT, &sighandler);
        signal(SIGTERM, &sighandler);
    }
} else {
    void setupConsole(string title) {
    }
}

