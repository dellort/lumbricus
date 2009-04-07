module net.cmdclient;

import common.common;
import common.task;
import framework.framework;
import framework.i18n;
import game.gameshell;
import game.gametask;
import game.setup;
import game.gamepublic;
import game.levelgen.level;
import gui.wm;
import gui.widget;
import gui.list;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.button;
import gui.label;
import gui.edit;
import gui.loader;
import gui.logwindow;
import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.gzip;
import utils.misc;
import utils.log;
import utils.vector2;

import str = stdx.string;

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
    void delegate(CmdNetClient sender, DiscReason code) onDisconnect;
    void delegate(CmdNetClient sender, char[] msg, char[][] args) onError;
    void delegate(CmdNetClient sender, char[][] text) onMessage;

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
                if (map.player == mPlayerName)
                    mClControl.addTeam(t);
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

    private void conDisconnect(NetPeer sender, uint code) {
        mHadDisconnect = true;
        assert(sender is mServerCon);
        mServerCon = null;
        state(ClientState.idle);
        if (onDisconnect)
            onDisconnect(this, cast(DiscReason)code);
    }

    private void conReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        //packet structure: 2 bytes message id + data
        if (dataLen < 2) {
            close(DiscReason.protocolError);
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
                //no close(), errors are non-fatal
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
                if (p.success) {
                    char[][] lines = str.splitlines(p.msg);
                    if (onMessage)
                        onMessage(this, lines);
                } else {
                    if (onError && p.msg.length > 0)
                        onError(this, p.msg, null);
                }
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
                close(DiscReason.protocolError);
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
        Team[] mOwnedTeams;
    }

    void addTeam(Team myTeam) {
        mOwnedTeams ~= myTeam;
    }

    this(CmdNetClient con) {
        mConnection = con;
        mShell = con.mShell;
    }

    TeamMember getControlledMember() {
        foreach (Team t; mOwnedTeams) {
            if (t.active) {
                return t.getActiveMember();
            }
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

//we need to be able to catch entered commands and transmit them
//no tab completion/history for now
private class CnsEditLine : EditLine {
    private CmdNetClientTask mCl;
    override protected bool handleKeyPress(KeyInfo infos) {
        if (infos.code == Keycode.PAGEUP) {
            mCl.mConsole.scrollBack(+1);
        } else if (infos.code == Keycode.PAGEDOWN) {
            mCl.mConsole.scrollBack(-1);
        } else if (infos.code == Keycode.RETURN) {
            mCl.executeCommand(text);
            text = null;
        } else {
            return super.handleKeyPress(infos);
        }
        return true;
    }
}

class CmdNetClientTask : Task {
    private {
        CmdNetClient mClient;
        DropDownList mTeams;
        Label mLblError;
        ConfigNode mTeamNode;
        GameTask mGame;
        Button mConnectButton, mReadyButton, mHostButton;
        StringListWidget mPlayers;
        EditLine mConnectTo, mNickname;
        CnsEditLine mEdConsole;
        LogWindow mConsole;
        char[] mPlayerName;
        //only needed when this client is starting the game
        GameConfig mGameConfig;
        Widget mConnectDlg, mLobbyDlg;
        Window mConnectWnd, mLobbyWnd;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mClient = new CmdNetClient();
        mClient.onConnect = &onConnect;
        mClient.onDisconnect = &onDisconnect;
        mClient.onStartLoading = &onStartLoading;
        mClient.onUpdateGameInfo = &onUpdateGameInfo;
        mClient.onError = &onError;
        mClient.onMessage = &onMessage;

        auto config = gConf.loadConfig("lobby_gui");
        auto loader = new LoadGui(config);
        loader.registerWidget!(CnsEditLine)("cnseditline");
        loader.load();

        //--------------------------------------------------------------

        mConnectDlg = loader.lookup("connect_root");

        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        mConnectButton = loader.lookup!(Button)("btn_connect");
        mConnectButton.onClick = &connectClick;

        mLblError = loader.lookup!(Label)("lbl_error");
        mLblError.text = "";

        mConnectTo = loader.lookup!(EditLine)("ed_address");
        mNickname = loader.lookup!(EditLine)("ed_nick");

        mConnectWnd = gWindowManager.createWindow(this, mConnectDlg,
            _("lobby.caption_connect"));

        //--------------------------------------------------------------

        mLobbyDlg = loader.lookup("lobby_root");

        mTeams = loader.lookup!(DropDownList)("dd_teams");
        mTeamNode = gConf.loadConfig("teams").getSubNode("teams");
        char[][] contents;
        foreach (ConfigNode subn; mTeamNode) {
            contents ~= subn.name;
        }
        mTeams.list.setContents(contents);
        mTeams.onSelect = &teamSelect;

        mPlayers = loader.lookup!(StringListWidget)("list_players");

        mHostButton = loader.lookup!(Button)("btn_host");
        mHostButton.onClick = &hostGame;
        mReadyButton = loader.lookup!(Button)("btn_ready");
        mReadyButton.enabled = false;  //xxx later
        mConsole = loader.lookup!(LogWindow)("console");
        mEdConsole = loader.lookup!(CnsEditLine)("ed_console");
        mEdConsole.mCl = this;

        loader.lookup!(Button)("btn_leave").onClick = &cancelClick;

        mLobbyWnd = gWindowManager.createWindow(this, mLobbyDlg, "");
        mLobbyWnd.visible = false;
    }

    private void onConnect(CmdNetClient sender) {
        mPlayerName = sender.playerName;
        mConnectWnd.visible = false;
        mLobbyWnd.visible = true;
        auto props = mLobbyWnd.properties;
        props.windowTitle = _("lobby.caption_lobby", mPlayerName);
        mLobbyWnd.properties = props;
    }

    private void onDisconnect(CmdNetClient sender, DiscReason code) {
        assert(code <= DiscReason.max);
        if (code == 0)
            mLblError.text = "";
        else
            mLblError.text = _("lobby.error", reasonToString[code]);
        mConnectButton.text = _("lobby.connect");
        mConnectButton.enabled = true;
        if (mLobbyWnd.visible) {
            //disconnected in lobby, disable everything
            mTeams.enabled = false;
            mPlayers.setContents([""]);
            mPlayers.enabled = false;
            mHostButton.enabled = false;
            mReadyButton.enabled = false;
            //show error message in console
            mConsole.writefln(_("lobby.c_disconnect",
                reasonToString[code]));
            mConsole.enabled = false;
            mEdConsole.enabled = false;
        }
    }

    private void teamSelect(DropDownList sender) {
        mClient.deployTeam(mTeamNode.getSubNode(sender.selection));
    }

    private void connectClick(Button sender) {
        mClient.connect(NetAddress(mConnectTo.text), mNickname.text);
        sender.text = _("lobby.connecting");
        sender.enabled = false;
    }

    private void cancelClick(Button sender) {
        kill();
    }

    private void hostGame(Button sender) {
        if (mClient.connected) {
            ConfigNode node = gConf.loadConfig("newgame");
            GameConfig conf = loadGameConfig(node, null, false);
            mClient.startLoading(conf);
        }
    }

    private void executeCommand(char[] cmd) {
        mClient.lobbyCmd(cmd);
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
        if (mLobbyWnd.visible) {
            //lobby error
            mConsole.writefln(_("lobby.c_serror", msg));
        } else {
            //connection error
            mLblError.text = _("lobby.error", msg);
        }
    }

    private void onMessage(CmdNetClient sender, char[][] text) {
        if (mLobbyWnd.visible) {
            foreach (l; text) {
                mConsole.writefln(l);
            }
        }
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
