module net.cmdclient;

import common.common;
import framework.commandline;
import game.controller;
import game.gameshell;
import game.levelgen.level;
import game.setup;
public import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.gzip;
import utils.misc;
import utils.log;
import utils.vector2;

import str = utils.string;
import tango.util.Convert;

enum ClientState {
    idle,
    connecting,
    connected,
}

//playerId corresponds to CmdNetClient.myId() and NetTeamInfo.Team.playerId
char[] makeAccessTag(uint playerId) {
    return myformat("net_id::{}", playerId);
}

class CmdNetClient : SimpleNetConnection {
    private {
        NetBase mBase;
        NetHost mHost;
        NetPeer mServerCon;
        MarshalBuffer mMarshal; //for keeping temporary memory
        char[] mPlayerName;
        uint mId;
        ClientState mState;
        Time mStateEnter;
        NetAddress mTmpAddr;
        GameShell mShell;
        //lol. this simply maps playerId -> makeAccessTag(playerId)
        //maybe this could go into mPlayerInfo, but I'm not sure
        //most likely it would be fine to call makeAccessTag directly, but apart
        //  from the additional memory allocation, maybe there's additional
        //  logic I don't understand, or so
        char[][uint] mSrvControl;
        CmdNetControl mClControl;
        bool mHadDisconnect;
        //name<->id conversion
        uint[char[]] mNameToId;
        ConfigNode mPersistentState;

        CommandBucket mCmds;

        struct MyPlayerInfo {
            bool valid;
            NetPlayerInfo info;
        }
        MyPlayerInfo[] mPlayerInfo;
        int mPlayerCount;
        uint mLastAck;
        const cAckInterval = 10;
    }

    void delegate(CmdNetClient sender) onConnect;
    void delegate(CmdNetClient sender, DiscReason code) onDisconnect;
    void delegate(CmdNetClient sender, char[] msg, char[][] args) onError;
    void delegate(CmdNetClient sender, char[][] text) onMessage;

    this() {
        registerCmds();

        mMarshal = new MarshalBuffer();

        mBase = new NetBase();
        mHost = mBase.createClient();
        state(ClientState.idle);
    }

    ~this() {
        delete mHost;
        delete mBase;
    }

    void tick() {
        mHost.serviceAll();
        Time t = timeCurrentTime();
        switch (mState) {
            case ClientState.connecting:
                //timeout connection attempt after 5s
                if (t - mStateEnter > timeSecs(5)) {
                    close(DiscReason.timeout);
                }
                break;
            default:
        }
    }

    //returns immediately
    void connect(NetAddress addr, char[] playerName) {
        if (mState != ClientState.idle)
            return;
        if (mServerCon) {
            mServerCon.reset();
            //xxx lol etc.: hack against mysteriously failing connections
            delete mHost;
            mHost = mBase.createClient();
            mServerCon = null;
        }
        mTmpAddr = addr;
        mPlayerName = playerName;
        mServerCon = mHost.connect(addr, 10);
        mServerCon.onConnect = &conConnect;
        mServerCon.onDisconnect = &conDisconnect;
        state(ClientState.connecting);
        mHadDisconnect = false;
    }

    //true if fully connected (with handshake)
    bool connected() {
        return mServerCon && mServerCon.connected()
            && mState == ClientState.connected;
    }

    //implements SimpleNetConnection.close()
    void close() {
        close(DiscReason.none);
    }

    //close connection, or abort connecting
    void close(DiscReason why) {
        state(ClientState.idle);
        if (mShell) {
            mShell.terminated = true;
        }
        if (!mServerCon)
            return;
        mServerCon.disconnect(why);
        mHost.serviceAll();
        if (!mHadDisconnect) {
            if (onDisconnect)
                onDisconnect(this, why);
            mHadDisconnect = true;
        }
    }

    NetAddress serverAddress() {
        if (mServerCon)
            return mServerCon.address();
        else
            return NetAddress.init;
    }

    //may have been modified by server
    char[] playerName() {
        return mPlayerName;
    }

    uint myId() {
        return mId;
    }

    ClientState state() {
        return mState;
    }

    //server console command
    void lobbyCmd(char[] cmd) {
        if (!connected)
            return;
        CPLobbyCmd p;
        p.cmd = cmd;
        send(ClientPacket.lobbyCmd, p);
    }

    void requestCreateGame(bool request = true) {
        CPRequestCreateGame p;
        p.request = request;
        send(ClientPacket.requestCreateGame, p);
    }

    void prepareCreateGame() {
        sendEmpty(ClientPacket.prepareCreateGame);
    }

    void createGame(GameConfig cfg) {
        CPCreateGame p;
        p.gameConfig = saveConfigGzBuf(cfg.save());
        send(ClientPacket.createGame, p);
    }

    void deployTeam(ConfigNode teamInfo) {
        CPDeployTeam p;
        p.teamName = teamInfo.name;
        p.teamConf = saveConfigGzBuf(teamInfo);
        send(ClientPacket.deployTeam, p);
    }

    //called by GameLoader.finish
    void signalLoadingDone(GameShell shell) {
        mShell = shell;
        sendEmpty(ClientPacket.loadDone);
    }

    bool playerNameToId(char[] name, ref uint id) {
        if (name in mNameToId) {
            id = mNameToId[name];
            return true;
        }
        return false;
    }

    bool idToPlayerName(uint id, ref char[] name) {
        if (isIdValid(id)) {
            name = mPlayerInfo[id].info.name;
            return true;
        }
        return false;
    }

    bool isIdValid(uint id) {
        if (id < mPlayerInfo.length && mPlayerInfo[id].valid)
            return true;
        return false;
    }

    int opApply(int delegate(ref NetPlayerInfo info) del) {
        foreach (ref pl; mPlayerInfo) {
            if (pl.valid) {
                int res = del(pl.info);
                if (res)
                    return res;
            }
        }
        return 0;
    }

    int playerCount() {
        return mPlayerCount;
    }

    //got packet with GameConfig
    private void doStartLoading(GameConfig cfg) {
        //start loading graphics and engine
        //will call signalLoadingDone() when finished
        auto loader = GameLoader.CreateNetworkGame(cfg, &signalLoadingDone);
        assert(!!onStartLoading, "Need to set callbacks");
        //--- just dump hash for debugging
        foreach (o; loader.gameConfig.level.objects) {
            if (auto bmp = cast(LevelLandscape)o) {
                gLog.notice("checksum bitmap '{}': {}", bmp.name,
                    bmp.landscape.checksum);
            }
        }
        //--- end
        onStartLoading(this, loader);
    }

    //status update on other players (for gui display of progress)
    private void doLoadStatus(NetLoadState st) {
        if (onLoadStatus)
            onLoadStatus(this, st);
    }

    private void doGameStart(SPGameStart info) {
        assert(!!onGameStart, "Need to set callbacks");
        //if setMe() is never called, we are spectator
        mClControl = new CmdNetControl(this);
        mSrvControl = null;
        if (!mShell) {
            close(DiscReason.internalError);
            return;
        }
        foreach (team; mShell.serverEngine.singleton!(GameController)().teams) {
            uint ownerId = to!(uint)(team.netId);
            if (!(ownerId in mSrvControl))
                mSrvControl[ownerId] = makeAccessTag(ownerId);
        }

        mShell.masterTime.paused = false;
        mLastAck = 0;
        onGameStart(this, mClControl);
    }

    void gameKilled(ConfigNode persistentState) {
        mShell = null;
        if (connected) {
            mPersistentState = persistentState;
            sendEmpty(ClientPacket.gameTerminated);
        }
    }

    private void checkAck(uint timestamp) {
        assert(mLastAck <= timestamp);
        if (timestamp - mLastAck > cAckInterval) {
            CPAck p;
            p.timestamp = timestamp;
            send(ClientPacket.ack, p);
            mLastAck = timestamp;
        }
    }

    bool waitingForServer() {
        if (mShell)
            return mShell.waitingForFrame();
        return false;
    }

    //transmit local game control command (called from CmdNetControl)
    private void sendCommand(char[] cmd) {
        CPGameCommand p;
        p.cmd = cmd;
        send(ClientPacket.gameCommand, p);
    }

    private void state(ClientState newState) {
        mState = newState;
        mStateEnter = timeCurrentTime();
    }

    //connection attempt succeeded, start handshake
    private void conConnect(NetPeer sender) {
        assert(sender is mServerCon);
        //close might have been called before the connection completed
        if (mState == ClientState.idle)
            return;
        mServerCon.onReceive = &conReceive;
        //send handshake packet
        CPHello p;
        p.playerName = mPlayerName;
        send(ClientPacket.hello, p);
    }

    private void conDisconnect(NetPeer sender, uint code) {
        mHadDisconnect = true;
        assert(sender is mServerCon);
        state(ClientState.idle);
        if (onDisconnect)
            onDisconnect(this, cast(DiscReason)code);
        mServerCon = null;
    }

    private void conReceive(NetPeer sender, ubyte channelId, ubyte[] data) {
        scope unmarshal = new UnmarshalBuffer(data);
        try {
            receive(channelId, unmarshal);
        } catch (UnmarshalException e) {
            //malformed packet, unmarshalling failed
            close(DiscReason.protocolError);
        }
    }

    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ServerPacket)();

        switch (pid) {
            case ServerPacket.error:
                auto p = unmarshal.read!(SPError)();
                if (onError)
                    onError(this, p.errMsg, p.args);
                //no close(), errors are non-fatal
                break;
            case ServerPacket.conAccept:
                //handshake accepted, connection is complete
                auto p = unmarshal.read!(SPConAccept)();
                //get updated nickname
                mPlayerName = p.playerName;
                mId = p.id;
                state(ClientState.connected);
                if (onConnect)
                    onConnect(this);
                break;
            case ServerPacket.cmdResult:
                //result from a command ran by lobbyCmd()
                auto p = unmarshal.read!(SPCmdResult)();
                if (p.success) {
                    char[][] lines = str.splitlines(p.msg);
                    if (onMessage)
                        onMessage(this, lines);
                } else {
                    if (onError && p.msg.length > 0)
                        onError(this, p.msg, null);
                }
                break;
            case ServerPacket.playerList:
                //info about other players while in lobby
                //the list is sorted by id
                auto p = unmarshal.read!(SPPlayerList)();
                mNameToId = null;
                mPlayerInfo.length = p.players[$-1].id + 1;
                mPlayerCount = p.players.length;
                uint curId = 0;
                foreach (player; p.players) {
                    while (curId < player.id) {
                        mPlayerInfo[curId].valid = false;
                        curId++;
                    }
                    mNameToId[player.name] = curId;
                    if (!mPlayerInfo[curId].valid) {
                        mPlayerInfo[curId] = MyPlayerInfo.init;
                        mPlayerInfo[curId].valid = true;
                    }
                    mPlayerInfo[curId].info.name = player.name;
                    mPlayerInfo[curId].info.teamName = player.teamName;
                    curId++;
                }
                if (onUpdatePlayers)
                    onUpdatePlayers(this);
                break;
            case ServerPacket.playerInfo:
                auto p = unmarshal.read!(SPPlayerInfo)();
                //PlayerList packet always comes first
                if (mPlayerInfo.length != p.players[$-1].id + 1) {
                    close(DiscReason.protocolError);
                }
                foreach (pinfo; p.players) {
                    if (p.updateFlags & SPPlayerInfo.Flags.ping)
                        mPlayerInfo[pinfo.id].info.ping = pinfo.ping;
                }
                if (onUpdatePlayers)
                    onUpdatePlayers(this);
                break;
            case ServerPacket.loadStatus:
                //status of other players while loading
                auto p = unmarshal.read!(SPLoadStatus)();
                NetLoadState st;
                st.playerIds = p.playerIds;
                st.done = p.done;
                doLoadStatus(st);
                break;
            case ServerPacket.startLoading:
                //receiving GameConfig (gzipped ConfigNode)
                auto p = unmarshal.read!(SPStartLoading)();
                GameConfig cfg = new GameConfig();
                cfg.load(loadConfigGzBuf(p.gameConfig));
                //saveConfig(cfg.save(), "gc.conf");
                doStartLoading(cfg);
                break;
            case ServerPacket.gameStart:
                //all players finished loading
                if (!mShell)
                    break;
                auto p = unmarshal.read!(SPGameStart)();
                doGameStart(p);
                break;
            case ServerPacket.gameCommands:
                if (!mShell)
                    break;
                //incoming aggregated game commands of all players for
                //one server frame
                auto p = unmarshal.read!(SPGameCommands)();
                //forward all commands to the engine
                foreach (gce; p.commands) {
                    if (auto ptr = gce.playerId in mSrvControl) {
                        mShell.addLoggedInput(*ptr, gce.cmd, p.timestamp);
                    }
                }
                //execute all player disconnects
                foreach (uint id; p.disconnectIds) {
                    if (auto ptr = id in mSrvControl) {
                        mShell.addLoggedInput(*ptr, "remove_control",
                            p.timestamp);
                        mSrvControl.remove(id);
                    }
                }
                mShell.setFrameReady(p.timestamp);
                checkAck(p.timestamp);
                break;
            case ServerPacket.ping:
                auto p = unmarshal.read!(SPPing)();
                CPPong reply;
                reply.ts = p.ts;
                send(ClientPacket.pong, reply, 1, true, false);
                break;
            case ServerPacket.clientBroadcast:
                receiveClientBroadcast(unmarshal);
                break;
            case ServerPacket.grantCreateGame:
                auto p = unmarshal.read!(SPGrantCreateGame)();
                if (onHostGrant)
                    onHostGrant(this, p.playerId, p.granted);
                break;
            case ServerPacket.acceptCreateGame:
                auto p = unmarshal.read!(SPAcceptCreateGame)();
                NetTeamInfo info;
                foreach (pt; p.teams) {
                    NetTeamInfo.Team nt;
                    nt.playerId = pt.playerId;
                    nt.teamConf = loadConfigGzBuf(pt.teamConf);
                    nt.teamConf.rename(pt.teamName);
                    info.teams ~= nt;
                }
                if (onHostAccept)
                    onHostAccept(this, info, mPersistentState);
                break;
            default:
                close(DiscReason.protocolError);
        }
    }

    private void receiveClientBroadcast(UnmarshalBuffer unmarshal) {
        auto pkt = unmarshal.read!(SPClientBroadcast)();
        char[] name;
        if (!idToPlayerName(pkt.senderPlayerId, name)) {
            //can this happen? at least the server could be evil and send crap
            name = "(unknown)";
        }

        auto pid = unmarshal.read!(Client2ClientPacket)();

        switch (pid) {
            case Client2ClientPacket.chatMessage:
                auto p = unmarshal.read!(CCChatMessage)();
                if (onMessage) {
                    onMessage(this,
                        [myformat("<{}> {}", name, p.witty_comment)]);
                }
                break;
            default:
                close(DiscReason.protocolError);
        }
    }

    //send packet without payload
    private void sendEmpty(ClientPacket pid, ubyte channelId = 0,
        bool now = false)
    {
        if (!mServerCon)
            return;
        struct Empty {
        }
        Empty t;
        send(pid, t, channelId, now);
    }

    //send packet with some data (data will be marshalled)
    private void send(T)(ClientPacket pid, T data, ubyte channelId = 0,
        bool now = false, bool reliable = true)
    {
        if (!mServerCon)
            return;
        mMarshal.reset();
        mMarshal.write(pid);
        mMarshal.write(data);
        ubyte[] buf = mMarshal.data();
        mServerCon.send(buf, channelId, now, reliable, reliable);
    }

    private void broadcast(T)(Client2ClientPacket pid, T data) {
        mMarshal.reset();
        mMarshal.write(ClientPacket.clientBroadcast);
        mMarshal.write(pid);
        mMarshal.write(data);
        ubyte[] buf = mMarshal.data();
        mServerCon.send(buf, 0, false, true, true);
    }

    private void cmdSay(MyBox[] args, Output write) {
        CCChatMessage m;
        m.witty_comment = args[0].unboxMaybe!(char[])();
        if (m.witty_comment.length > 0)
            broadcast(Client2ClientPacket.chatMessage, m);
    }

    private void registerCmds() {
        mCmds = new CommandBucket();
        mCmds.register(Command("say", &cmdSay, "say something",
            ["text?...:what to say"]));
    }

    CommandBucket commands() {
        return mCmds;
    }
}

//Local input -> Server input proxy (one for the local player)
class CmdNetControl : ClientControl {
    private {
        CmdNetClient mConnection;
    }

    this(CmdNetClient con) {
        super(con.mShell, makeAccessTag(con.myId()));
        mConnection = con;
    }

    override void sendCommand(char[] cmd) {
        mConnection.sendCommand(cmd);
    }
}
