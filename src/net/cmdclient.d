module net.cmdclient;

import common.common;
import common.task;
import game.gameshell;
import game.gametask;
import game.setup;
import game.gamepublic;
import game.levelgen.level;
import gui.wm;
import gui.list;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.button;
import gui.label;
import gui.edit;
import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.gzip;
import utils.misc;
import utils.log;
import utils.vector2;

enum ClientState {
    idle,
    connecting,
    connected,
}

class CmdNetClient : SimpleNetConnection {
    private {
        NetBase mBase;
        NetHost mHost;
        NetPeer mServerCon;
        char[] mPlayerName;
        ClientState mState;
        Time mStateEnter;
        NetAddress mTmpAddr;
        GameShell mShell;
        NetGameControl[char[]] mSrvControl;
        CmdNetControl mClControl;
        bool mHadDisconnect;
    }

    void delegate(CmdNetClient sender) onConnect;
    void delegate(CmdNetClient sender) onDisconnect;
    void delegate(CmdNetClient sender, char[] msg, char[][] args) onError;

    this() {
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
                    if (onError)
                        onError(this, "error_contimeout", [mTmpAddr.hostName]);
                    close();
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

    //close connection, or abort connecting
    void close() {
        state(ClientState.idle);
        if (!mServerCon)
            return;
        mServerCon.disconnect();
        mHost.serviceAll();
        if (!mHadDisconnect) {
            if (onDisconnect)
                onDisconnect(this);
            mHadDisconnect = true;
        }
    }

    void closeWithReason(char[] errorCode) {
        if (!connected)
            return;
        CPError p;
        p.errMsg = errorCode;
        send(ClientPacket.error, p, 0, true);
        close();
    }

    NetAddress serverAddress() {
        if (connected)
            return mServerCon.address();
        else
            return NetAddress.init;
    }

    //may have been modified by server
    char[] playerName() {
        return mPlayerName;
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

    void startLoading(GameConfig cfg) {
        CPStartLoading p;
        p.gameConfig = gConf.saveConfigGzBuf(cfg.save());
        send(ClientPacket.startLoading, p);
    }

    void deployTeam(ConfigNode teamInfo) {
        CPDeployTeam p;
        p.teamName = teamInfo.name;
        p.teamConf = gConf.saveConfigGzBuf(teamInfo);
        send(ClientPacket.deployTeam, p);
    }

    //called by GameLoader.finish
    void signalLoadingDone(GameShell shell) {
        mShell = shell;
        sendEmpty(ClientPacket.loadDone);
    }

    //got packet with GameConfig
    private void doStartLoading(GameConfig cfg) {
        //start loading graphics and engine
        //will call signalLoadingDone() when finished
        auto loader = GameLoader.CreateNetworkGame(cfg, this);
        assert(!!onStartLoading, "Need to set callbacks");
        //--- just dump hash for debugging
        foreach (o; loader.gameConfig.level.objects) {
            if (auto bmp = cast(LevelLandscape)o) {
                Trace.formatln("- checksum bitmap '{}': {}", bmp.name,
                    bmp.landscape.checksum);
            }
        }
        //--- end
        onStartLoading(this, loader);
    }

    //incoming info packet (while in lobby)
    private void doUpdateGameInfo(NetGameInfo info) {
        if (onUpdateGameInfo)
            onUpdateGameInfo(this, info);
    }

    //status update on other players (for gui display of progress)
    private void doLoadStatus(NetLoadState st) {
        if (onLoadStatus)
            onLoadStatus(this, st);
    }

    private Team findTeam(char[] t) {
        foreach (team; mShell.serverEngine.logic.getTeams) {
            if (team.name == t)
                return team;
        }
        return null;
    }

    private void doGameStart(SPGameStart info) {
        assert(!!onGameStart, "Need to set callbacks");
        //if setMe() is never called, we are spectator
        mClControl = new CmdNetControl(this);
        //lol
        foreach (map; info.mapping) {
            auto ctl = new NetGameControl(mShell);
            mSrvControl[map.player] = ctl;
            foreach (team; map.team) {
                Team t = findTeam(team);
                //proper error handling: ignore or disconnect
                assert(!!t, "team not found: "~team);
                ctl.addTeam(t);
                //if it is our team, enable a local->server input proxy
                //oops that thing accepts only one team
                if (map.player == mPlayerName)
                    mClControl.setMe(t);
            }
        }
        mShell.masterTime.paused = false;
        onGameStart(this, mClControl);
    }

    private void doExecCommand(uint timestamp, char[] player, char[] cmd) {
        if (player in mSrvControl)
            mSrvControl[player].executeTSCommand(cmd, timestamp);
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

    private void conDisconnect(NetPeer sender) {
        mHadDisconnect = true;
        assert(sender is mServerCon);
        mServerCon = null;
        state(ClientState.idle);
        if (onDisconnect)
            onDisconnect(this);
    }

    private void conReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        //packet structure: 2 bytes message id + data
        if (dataLen < 2) {
            closeWithReason("error_protocol");
            return;
        }
        scope unmarshal = new UnmarshalBuffer(data[0..dataLen]);
        receive(channelId, unmarshal);
    }

    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ServerPacket)();

        switch (pid) {
            case ServerPacket.error:
                auto p = unmarshal.read!(SPError)();
                if (onError)
                    onError(this, p.errMsg, p.args);
                //close();
                break;
            case ServerPacket.conAccept:
                //handshake accepted, connection is complete
                auto p = unmarshal.read!(SPConAccept)();
                //get updated nickname
                mPlayerName = p.playerName;
                if (onConnect)
                    onConnect(this);
                state(ClientState.connected);
                break;
            case ServerPacket.cmdResult:
                //result from a command ran by lobbyCmd()
                auto p = unmarshal.read!(SPCmdResult)();
                if (onError && p.msg.length > 0)
                    onError(this, p.msg, null);
                break;
            case ServerPacket.gameInfo:
                //info about other players while in lobby
                auto p = unmarshal.read!(SPGameInfo)();
                NetGameInfo info;
                info.players = p.players;
                info.teams = p.teams;
                doUpdateGameInfo(info);
                break;
            case ServerPacket.loadStatus:
                //status of other players while loading
                auto p = unmarshal.read!(SPLoadStatus)();
                NetLoadState st;
                st.players = p.players;
                st.done = p.done;
                doLoadStatus(st);
                break;
            case ServerPacket.startLoading:
                //receiving GameConfig (gzipped ConfigNode)
                auto p = unmarshal.read!(SPStartLoading)();
                GameConfig cfg = new GameConfig();
                cfg.load(gConf.loadConfigGzBuf(p.gameConfig));
                //gConf.saveConfig(cfg.save(), "gc.conf");
                doStartLoading(cfg);
                break;
            case ServerPacket.gameStart:
                //all players finished loading
                auto p = unmarshal.read!(SPGameStart)();
                doGameStart(p);
                break;
            case ServerPacket.gameCommands:
                //incoming aggregated game commands of all players for
                //one server frame
                auto p = unmarshal.read!(SPGameCommands)();
                //forward all commands to the engine
                foreach (gce; p.commands) {
                    doExecCommand(p.timestamp, gce.player, gce.cmd);
                }
                mShell.setFrameReady(p.timestamp);
                break;
            default:
                if (onError)
                    onError(this, "error_protocol", []);
                closeWithReason("error_protocol");
        }
    }

    //send packet without payload
    private void sendEmpty(ClientPacket pid, ubyte channelId = 0,
        bool now = false)
    {
        if (!mServerCon)
            return;
        mServerCon.send(&pid, pid.sizeof, channelId, now);
    }

    //send packet with some data (data will be marshalled)
    private void send(T)(ClientPacket pid, T data, ubyte channelId = 0,
        bool now = false)
    {
        if (!mServerCon)
            return;
        scope marshal = new MarshalBuffer();
        marshal.write(pid);
        marshal.write(data);
        ubyte[] buf = marshal.data();
        mServerCon.send(buf.ptr, buf.length, channelId, now);
    }
}

//Local input -> Server input proxy (one for the local player)
class CmdNetControl : ClientControl {
    private {
        CmdNetClient mConnection;
        GameShell mShell;
        Team mOwnedTeam;
    }

    void setMe(Team myTeam) {
        mOwnedTeam = myTeam;
    }

    this(CmdNetClient con) {
        mConnection = con;
        mShell = con.mShell;
    }

    TeamMember getControlledMember() {
        if (!mOwnedTeam)
            return null;
        if (mOwnedTeam.active) {
            return mOwnedTeam.getActiveMember();
        }
        return null;
    }

    void executeCommand(char[] cmd) {
        mConnection.sendCommand(cmd);
    }
}

//Incoming command from server -> Local engine command proxy
//  (one for each player in the game)
class NetGameControl : GameControl {
    this(GameShell sh) {
        super(sh, false);
    }

    void executeTSCommand(char[] cmd, long timestamp) {
        setCurrentTS(timestamp);
        executeCommand(cmd);
    }
}

class CmdNetClientTask : Task {
    private {
        CmdNetClient mClient;
        //so this is why trying to connect a second client from another program
        //instance mysteriously failed...
        //static int mInstance;
        DropDownList mTeams;
        Label mLabel;
        ConfigNode mTeamNode;
        GameTask mGame;
        Button mStartButton;
        StringListWidget mPlayers;
        EditLine mConnectTo;
        char[] mPlayerName;
        //only needed when this client is starting the game
        GameConfig mGameConfig;
        bool mHadError;
    }
import utils.random;
    this(TaskManager tm, char[] args = "") {
        super(tm);

        auto mInstance = rngShared.next(10000);
        mPlayerName = myformat("Player{}", mInstance);
        mClient = new CmdNetClient();
        mClient.onConnect = &onConnect;
        mClient.onDisconnect = &onDisconnect;
        mClient.onStartLoading = &onStartLoading;
        mClient.onUpdateGameInfo = &onUpdateGameInfo;
        mClient.onError = &onError;

        auto box = new BoxContainer(false, false, 5);
        mTeams = new DropDownList();
        mTeamNode = gConf.loadConfig("teams").getSubNode("teams");
        char[][] contents;
        foreach (ConfigNode subn; mTeamNode) {
            contents ~= subn.name;
        }
        mTeams.list.setContents(contents);
        mTeams.onSelect = &teamSelect;
        mTeams.enabled = false;
        box.add(mTeams);

        mPlayers = new StringListWidget();
        box.add(mPlayers);

        mStartButton = new Button();
        mStartButton.text = "Connect";
        mStartButton.onClick = &startGame;
        box.add(mStartButton);

        mLabel = new Label();
        mLabel.text = "Idle";
        mLabel.drawBorder = false;
        box.add(mLabel);

        mConnectTo = new EditLine();
        mConnectTo.text = "localhost:12499";
        box.add(mConnectTo);

        gWindowManager.createWindow(this, box, "Client", Vector2i(200, 0));
        mInstance++;
    }

    private void onConnect(CmdNetClient sender) {
        mLabel.text = "Connected: " ~ sender.playerName;
        mStartButton.text = "Start game!";
        mStartButton.enabled = true;
        mTeams.enabled = true;
    }

    private void onDisconnect(CmdNetClient sender) {
        if (!mHadError)
            mLabel.text = "Idle";
        mStartButton.text = "Connect";
        mStartButton.enabled = true;
        mTeams.enabled = false;
        mPlayers.setContents([""]);
    }

    private void teamSelect(DropDownList sender) {
        mClient.deployTeam(mTeamNode.getSubNode(sender.selection));
    }

    private void startGame(Button sender) {
        mHadError = false;
        if (mClient.connected) {
            ConfigNode node = gConf.loadConfig("newgame");
            GameConfig conf = loadGameConfig(node, null, false);
            mClient.startLoading(conf);
        } else {
            mClient.connect(NetAddress(mConnectTo.text), mPlayerName);
            mLabel.text = "Connecting";
            mStartButton.enabled = false;
        }
    }

    private void onStartLoading(SimpleNetConnection sender, GameLoader loader) {
        mGame = new GameTask(manager, loader, mClient);
    }

    private void onUpdateGameInfo(SimpleNetConnection sender, NetGameInfo info)
    {
        char[][] contents;
        foreach (int idx, char[] pl; info.players) {
            contents ~= pl ~ " (" ~ info.teams[idx] ~ ")";
        }
        mPlayers.setContents(contents);
    }

    private void onError(CmdNetClient sender, char[] msg, char[][] args) {
        mLabel.text = "Error: " ~ msg;
        gDefaultOutput.writefln("{}", msg);
        mHadError = true;
        mPlayers.setContents([""]);
    }

    override protected void onKill() {
        mClient.close();
        delete mClient;
    }

    override protected void onFrame() {
        mClient.tick();
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdclient");
    }
}
