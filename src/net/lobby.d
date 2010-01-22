module net.lobby;

import common.common;
import common.task;
import framework.commandline;
import framework.framework;
import framework.i18n;
import game.gameshell;
import game.gametask;
import game.glue;
import game.setup;
import game.gui.setup_local;
import game.gui.gamesummary;
import gui.wm;
import gui.widget;
import gui.list;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.button;
import gui.console;
import gui.label;
import gui.edit;
import gui.loader;
import gui.logwindow;
import gui.tabs;
import gui.container;
import net.netlayer;
import net.announce;
import net.cmdclient;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.log;

import tango.math.random.Random : rand;
import tango.util.Convert : to;

class CmdNetClientTask : Task {
    private {
        static LogStruct!("connect") log;
        CmdNetClient mClient;
        Label mLblError;
        Button mConnectButton;
        EditLine mConnectTo, mNickname;
        Tabs mTabs;
        Widget mConnectDlg;
        Window mConnectWnd;
        Widget mDirectMarker;

        const cRefreshInterval = timeSecs(2);
        int mMode = -1;
        AnnounceSt[] mAnnounce;
        char[][] mCurServers;
        Time mLastTime;

        //contains announcer-widget mapping
        struct AnnounceSt {
            NetAnnounceClient announce;
            //if this widget is activated in the tab control, use this announcer
            Widget marker;
            //target list for servers
            StringListWidget list;
        }
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mLastTime = timeCurrentTime();

        mClient = new CmdNetClient();
        mClient.onConnect = &onConnect;
        mClient.onDisconnect = &onDisconnect;
        mClient.onError = &onError;

        auto config = loadConfig("dialogs/connect_gui");
        auto loader = new LoadGui(config);
        loader.load();

        auto ann = config.getSubNode("announce");
        foreach (ConfigNode sub; ann) {
            AnnounceSt as;
            log("Init announce client: {}", sub.name);
            as.announce = AnnounceClientFactory.instantiate(sub.name, sub);
            as.marker = loader.lookup(sub["ctl_marker"]);
            as.list = loader.lookup!(StringListWidget)(sub["ctl_list"]);
            mAnnounce ~= as;
        }
        mDirectMarker = loader.lookup(config["direct_marker"]);

        //--------------------------------------------------------------

        mConnectDlg = loader.lookup("connect_root");

        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        mConnectButton = loader.lookup!(Button)("btn_connect");
        mConnectButton.onClick = &connectClick;

        mLblError = loader.lookup!(Label)("lbl_error");
        mLblError.text = "";

        mConnectTo = loader.lookup!(EditLine)("ed_address");
        mNickname = loader.lookup!(EditLine)("ed_nick");

        mTabs = loader.lookup!(Tabs)("tabs");
        mTabs.onActiveChange = &tabActivate;

        mConnectWnd = gWindowManager.createWindow(this, mConnectDlg,
            r"\t(connect.caption)");
    }

    private void onConnect(CmdNetClient sender) {
        log("Connection to {} succeeded", sender.serverAddress);
        mClient.onConnect = null;
        mClient.onDisconnect = null;
        mClient.onError = null;
        new CmdNetLobbyTask(manager, mClient);
        //ownership is handed over
        mClient = null;
        kill();
    }

    private void onDisconnect(CmdNetClient sender, DiscReason code) {
        assert(code <= DiscReason.max);
        if (code == 0)
            mLblError.text = "";
        else
            mLblError.text = translate("connect.error", reasonToString[code]);
        mConnectButton.text = translate("connect.connect");
        mConnectButton.enabled = true;
        log("Lost connection to {}: {}", sender.serverAddress,
            reasonToString[code]);
    }

    private void onError(CmdNetClient sender, char[] msg, char[][] args) {
        //connection error
        mLblError.text = translate("connect.error", msg);
        log("Error from {}: {}", sender.serverAddress, msg);
    }

    private void connectClick(Button sender) {
        char[] addr = mConnectTo.text;
        if (mMode >= 0) {
            int sel = mAnnounce[mMode].list.selectedIndex;
            if (sel < 0 || sel >= mCurServers.length)
                return;
            addr = mCurServers[sel];
        }
        log("Trying to connect to {}", NetAddress(addr));
        mClient.connect(NetAddress(addr), mNickname.text);
        sender.text = translate("connect.connecting");
        sender.enabled = false;
    }

    private void cancelClick(Button sender) {
        kill();
    }

    private void tabActivate(Tabs sender) {
        if (sender.active == mDirectMarker) {
            setMode(-1);
        } else {
            foreach (int idx, ref as; mAnnounce) {
                if (sender.active == as.marker) {
                    setMode(idx);
                    return;
                }
            }
        }
    }

    private void setMode(int idx) {
        if (mMode >= 0)
            mAnnounce[mMode].announce.active = false;
        if (idx >= 0) {
            assert(idx < mAnnounce.length);
            mAnnounce[idx].announce.active = true;
        }
        mMode = idx;
    }

    override protected void onKill() {
        if (mClient) {
            mClient.close();
            delete mClient;
        }
        foreach (ref as; mAnnounce) {
            as.announce.close();
        }
    }

    override protected void onFrame() {
        if (mClient)
            mClient.tick();
        if (mMode >= 0) {
            mAnnounce[mMode].announce.tick();
            Time t = timeCurrentTime();
            //refresh servers periodically
            //Note: depending on announcer, this does not mean to actually
            //      request a new list, it just gets the announcer's current one
            if (t - mLastTime > cRefreshInterval) {
                char[][] contents;
                mCurServers = null;
                foreach (s; mAnnounce[mMode].announce) {
                    //full info for gui display
                    contents ~= myformat("{}:{} ({}/{}) {}", s.address,
                        s.info.port, s.info.curPlayers, s.info.maxPlayers,
                        s.info.serverName);
                    //address only for connecting
                    mCurServers ~= myformat("{}:{}", s.address, s.info.port);
                }
                //nothing found
                //xxx: currently we can't separate between
                //     "still searching" or "no servers there"
                if (contents.length == 0) {
                    if (mAnnounce[mMode].announce.active)
                        contents ~= translate("connect.noservers");
                    else
                        contents ~= translate("connect.announceerror");
                }
                mAnnounce[mMode].list.setContents(contents);
                mLastTime = t;
            }
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdclient");
    }
}

class CreateNetworkGame : SimpleContainer {
    private {
        LevelWidget mLevelSelector;
        Task mOwner;
        Widget mDialog, mWaiting;
    }

    void delegate() onCancel;
    void delegate() onWantStart;
    void delegate(GameConfig conf) onStart;

    this(Task owner) {
        mOwner = owner;
        auto config = loadConfig("dialogs/netgamesetup_gui");
        auto loader = new LoadGui(config);

        mLevelSelector = new LevelWidget(mOwner);
        loader.addNamedWidget(mLevelSelector, "levelwidget");
        mLevelSelector.onSetBusy = &levelBusy;

        loader.load();

        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        loader.lookup!(Button)("btn_go").onClick = &goClick;

        mDialog = loader.lookup("creategame_root");
        mWaiting = loader.lookup("waiting_root");

        reset();
    }

    void reset() {
        clear();
        add(mDialog);
    }

    private void levelBusy(bool busy) {
        //
    }

    private void goClick(Button sender) {
        assert(!!onWantStart);
        //xxx lol, no way back
        clear();
        add(mWaiting);
        onWantStart();
    }

    void doStart(NetTeamInfo info, ConfigNode persistentState) {
        assert(!!onStart);
        //generate level
        auto finalLevel = mLevelSelector.currentLevel.render();

        //everything else uses defaults...
        ConfigNode node = loadConfig("newgame_net");
        int wormHP = node.getValue("worm_hp", 150);
        int wormCount = node.getValue("worm_count", 4);

        GameConfig conf = loadGameConfig(node, finalLevel, true,
            persistentState);
        auto teams = conf.teams;
        //other players' teams are added below
        teams.clear();
        foreach (ref ti; info.teams) {
            ConfigNode ct = ti.teamConf;
            if (ct) {
                //fixed number of team members
                char[][] wormNames;
                auto memberNode = ct.getSubNode("member_names");
                foreach (ConfigNode sub; memberNode) {
                    wormNames ~= sub.value;
                }
                memberNode.clear();
                for (int i = 0; i < wormCount; i++) {
                    if (i < wormNames.length)
                        memberNode.add("", wormNames[i]);
                    else
                        //xxx localize? not so sure about that (we don't
                        //    have access to the team owner's locale)
                        memberNode.add("", myformat("Worm {}", i));
                }
                //fixed health
                ct.setValue("power", wormHP);
                //the clients need this to identify which team belongs to whom
                ct.setValue("net_id", ti.playerId);
                teams.addNode(ct);
            }
        }

        //set access control - right now, an access tag is mapped to one or more
        //  teams. for the game engine, the tag is an arbitrary string. we use
        //  the net-team-id as the tag, so that "cheating" by trying to control
        //  the other's teams is not possible.
        ConfigNode access_map = conf.management.getSubNode("access_map");
        foreach (ref ti; info.teams) {
            //s is the list of controlled teams
            auto s = access_map.getSubNode(makeAccessTag(ti.playerId));
            s.add("", ti.teamConf["id"]);
        }

        conf.randomSeed = to!(char[])(rand.uniform!(uint));

        onStart(conf);
    }

    private void cancelClick(Button sender) {
        if (onCancel)
            onCancel();
    }
}

class CmdNetLobbyTask : Task {
    private {
        static LogStruct!("lobby") log;
        CmdNetClient mClient;
        DropDownList mTeams;
        ConfigNode mTeamNode;
        GameTask mGame;
        Button mReadyButton, mHostButton;
        StringListWidget mPlayers;
        Output mConsole;
        GuiConsole mConsoleWidget;
        //only needed when this client is starting the game
        GameConfig mGameConfig;
        Widget mLobbyDlg;
        CreateNetworkGame mCreateDlg;
        Window mLobbyWnd, mCreateWnd;
        GameSummary mGameSummary;
    }

    this(TaskManager tm, CmdNetClient client) {
        super(tm);

        assert(!!client);
        assert(client.connected);
        mClient = client;
        mClient.onDisconnect = &onDisconnect;
        mClient.onStartLoading = &onStartLoading;
        mClient.onUpdatePlayers = &onUpdatePlayers;
        mClient.onError = &onError;
        mClient.onMessage = &onMessage;
        mClient.onHostGrant = &onHostGrant;
        mClient.onHostAccept = &onHostAccept;

        auto config = loadConfig("dialogs/lobby_gui");
        auto loader = new LoadGui(config);
        loader.load();

        //--------------------------------------------------------------

        mLobbyDlg = loader.lookup("lobby_root");

        mTeams = loader.lookup!(DropDownList)("dd_teams");
        mTeamNode = loadConfig("teams").getSubNode("teams");
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
        mConsoleWidget = loader.lookup!(GuiConsole)("chatbox");
        mConsoleWidget.cmdline.setPrefix("/", "say");
        //warning: CommandBucket (client.commands()) can have only 1 parent
        mConsoleWidget.cmdline.commands.addSub(client.commands());
        mConsoleWidget.cmdline.onFallbackExecute = &cmdlineFalbackExecute;
        mConsole = mConsoleWidget.output;

        loader.lookup!(Button)("btn_leave").onClick = &cancelClick;

        //xxx values should be read from configfile
        //also xxx playerName will be interpreted as markup
        mLobbyWnd = gWindowManager.createWindow(this, mLobbyDlg,
            translate("lobby.caption", mClient.playerName), Vector2i(550, 500));

        //--------------------------------------------------------------

        mCreateDlg = new CreateNetworkGame(this);
        mCreateDlg.onCancel = &createCancel;
        mCreateDlg.onWantStart = &createWantStart;
        mCreateDlg.onStart = &createStart;
    }

    private void cmdlineFalbackExecute(CommandLine sender, char[] line) {
        mClient.lobbyCmd(line);
    }

    private void onDisconnect(CmdNetClient sender, DiscReason code) {
        assert(code <= DiscReason.max);
        //disconnected in lobby, disable everything
        mTeams.enabled = false;
        mPlayers.setContents([""]);
        mPlayers.enabled = false;
        mHostButton.enabled = false;
        mReadyButton.enabled = false;
        //show error message in console
        mConsole.writefln(translate("lobby.c_disconnect",
            reasonToString[code]));
        mConsoleWidget.enabled = false;
    }

    private void teamSelect(DropDownList sender) {
        mClient.deployTeam(mTeamNode.getSubNode(sender.selection));
    }

    private void cancelClick(Button sender) {
        kill();
    }

    private void hostGame(Button sender) {
        if (mClient.connected) {
            //ask if we are allowed to create a game
            mClient.requestCreateGame();
        }
    }

    //the server allowed someone to create a game
    private void onHostGrant(SimpleNetConnection sender, uint playerId,
        bool granted)
    {
        if (playerId == mClient.myId) {
            //we want to create a game, show the setup window
            if (granted) {
                mCreateDlg.reset();
                if (!mCreateWnd) {
                    mCreateWnd = gWindowManager.createWindow(this, mCreateDlg,
                        r"\t(gamesetup.caption_net)");
                    mCreateWnd.onClose = &createClose;
                }
                mCreateWnd.visible = true;
            }
        } else {
            if (mCreateWnd)
                mCreateWnd.destroy();
            //show a message that someone else is creating a game
            char[] name;
            mClient.idToPlayerName(playerId, name);
            if (granted)
                mConsole.writefln(translate("lobby.hostinprogress", name));
            else
                mConsole.writefln(translate("lobby.hostaborted", name));
        }
    }

    //got team info, assemble and send GameConfig
    //Big xxx: all data is loaded from newgame_net.conf, need setup dialog
    private void onHostAccept(SimpleNetConnection sender, NetTeamInfo info,
        ConfigNode persistentState)
    {
        mCreateDlg.doStart(info, persistentState);
    }

    //CreateNetworkGame callbacks -->

    private void createCancel() {
        //tell the server that someone else can create a game
        mClient.requestCreateGame(false);
        mCreateWnd.destroy();
    }

    private void createWantStart() {
        //user clicked the "Go" button, request team info
        mClient.prepareCreateGame();
    }

    private void createStart(GameConfig conf) {
        //really start
        log("debug dump!");
        saveConfig(conf.save(), "dump.conf");

        mClient.createGame(conf);
        mCreateWnd.destroy();
    }

    private bool createClose(Window sender) {
        //don't kill the task
        createCancel();
        return true;
    }

    //<-- CreateNetworkGame end

    private void executeCommand(char[] cmd) {
        mClient.lobbyCmd(cmd);
    }

    private void onGameKill(Task t) {
        ConfigNode persist;
        if (mGame && mGame.gamePersist) {
            persist = mGame.gamePersist;
            mGameSummary = new GameSummary(manager);
            mGameSummary.init(persist);
            if (mGameSummary.gameOver)
                persist = null;
        }
        if (mClient)
            mClient.gameKilled(persist);
    }

    private void onStartLoading(SimpleNetConnection sender, GameLoader loader) {
        if (mCreateWnd)
            mCreateWnd.destroy();
        if (mGameSummary) {
            mGameSummary.kill();
            mGameSummary = null;
        }
        //mConsole.writefln(translate("lobby.gamestarting"));
        mGame = new GameTask(manager, loader, mClient);
        mGame.registerOnDeath(&onGameKill);
    }

    private void onUpdatePlayers(SimpleNetConnection sender)
    {
        char[][] contents;
        contents.length = mClient.playerCount;
        int idx = 0;
        foreach (ref NetPlayerInfo pinfo; mClient) {
            contents[idx] = myformat("{} ({}), {}", pinfo.name, pinfo.teamName,
                pinfo.ping);
            idx++;
        }
        mPlayers.setContents(contents);
    }

    private void onError(CmdNetClient sender, char[] msg, char[][] args) {
        //lobby error
        mConsole.writefln(translate("lobby.c_serror", msg));
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
}
