module net.lobby;

import common.task;
import framework.commandline;
import framework.config;
import framework.globalsettings;
import framework.i18n;
import game.gameshell;
import game.gametask;
import game.setup;
import game.gui.setup_local;
import game.gui.gamesummary;
import gui.window;
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
import net.serverlist;
import utils.array;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.random;
import utils.time;
import utils.vector2;

import tango.util.Convert : to;

string translateError(DiscReason code) {
    return translate("neterror." ~ reasonToString[code]);
}

class CmdNetClientTask {
    private {
        static LogStruct!("connect") log;
        CmdNetClient mClient;
        Label mLblError;
        Button mConnectButton;
        EditLine mConnectTo, mNickname;
        Tabs mTabs;
        Widget mConnectDlg;
        WindowWidget mConnectWnd;
        Widget mDirectMarker;
        static Setting mNickSetting;

        enum cRefreshInterval = timeSecs(2);
        int mMode = -1;
        AnnounceSt[] mAnnounce;
        ServerAddress[] mCurServers;
        Time mLastTime;

        //contains announcer-widget mapping
        struct AnnounceSt {
            ServerList servers;
            //if this widget is activated in the tab control, use this announcer
            Widget marker;
            //target list for servers
            StringListWidget list;
        }
    }

    this(string args = "") {
        mLastTime = timeCurrentTime();

        mClient = new CmdNetClient();
        mClient.onConnect = &onConnect;
        mClient.onDisconnect = &onDisconnect;
        mClient.onError = &onError;

        auto config = loadConfig("dialogs/connect_gui.conf");
        auto loader = new LoadGui(config);
        loader.load();

        auto ann = config.getSubNode("announce");
        foreach (ConfigNode sub; ann) {
            AnnounceSt as;
            log.minor("Init announce client: %s", sub.name);
            as.servers = new ServerList(
                AnnounceClientFactory.instantiate(sub.name, sub));
            as.servers.onChange = &serverListChange;
            as.marker = loader.lookup(sub["ctl_marker"]);
            as.list = loader.lookup!(StringListWidget)(sub["ctl_list"]);
            string refreshBtn = sub["ctl_refresh"];
            if (refreshBtn.length > 0) {
                loader.lookup!(Button)(sub["ctl_refresh"]).onClick =
                    &refreshClick;
            }
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
        mNickname.onChange = &nicknameChange;
        mNickSetting.onChange ~= &nickSettingChange;
        mNickname.text = mNickSetting.value;

        mTabs = loader.lookup!(Tabs)("tabs");
        mTabs.onActiveChange = &tabActivate;

        mConnectWnd = gWindowFrame.createWindow(mConnectDlg,
            r"\t(connect.caption)");

        addTask(&onFrame);
    }

    private void onConnect(CmdNetClient sender) {
        log.notice("Connection to %s succeeded", sender.serverAddress);
        mClient.onConnect = null;
        mClient.onDisconnect = null;
        mClient.onError = null;
        new CmdNetLobbyTask(mClient);
        //ownership is handed over
        mClient = null;
        mConnectWnd.remove();
    }

    private void onDisconnect(CmdNetClient sender, DiscReason code) {
        assert(code <= DiscReason.max);
        LogPriority type;
        if (code == 0) {
            type = LogPriority.Notice;
            mLblError.text = "";
        } else {
            type = LogPriority.Error;
            mLblError.text = translate("connect.error", translateError(code));
        }
        mConnectButton.text = translate("connect.connect");
        mConnectButton.enabled = true;
        log.emit(type, "Lost connection to %s: %s", sender.serverAddress,
            reasonToString[code]);
    }

    private void onError(CmdNetClient sender, string msg, string[] args) {
        //connection error
        mLblError.text = translate("connect.error", msg);
        log.error("Error from %s: %s", sender.serverAddress, msg);
    }

    private void connectClick(Button sender) {
        string addr = mConnectTo.text;
        if (mMode >= 0) {
            int sel = mAnnounce[mMode].list.selectedIndex;
            if (sel < 0 || sel >= mCurServers.length)
                return;
            addr = mCurServers[sel].toString();
        }
        log.notice("Trying to connect to %s", NetAddress(addr));
        mClient.connect(NetAddress(addr), mNickname.text);
        sender.text = translate("connect.connecting");
        sender.enabled = false;
    }

    private void cancelClick(Button sender) {
        mConnectWnd.remove();
    }

    private void refreshClick(Button sender) {
        if (mMode >= 0) {
            mAnnounce[mMode].servers.refreshAll();
        }
    }

    private void tabActivate(Tabs sender) {
        if (sender.active && sender.active.client is mDirectMarker) {
            setMode(-1);
        } else {
            foreach (int idx, ref as; mAnnounce) {
                if (sender.active && sender.active.client is as.marker) {
                    setMode(idx);
                    return;
                }
            }
        }
    }

    //xxx perhaps implement a generic setting editor control
    private void nicknameChange(EditLine sender) {
        mNickSetting.set(sender.text);
    }

    private void nickSettingChange(Setting sender) {
        if (mNickname.text != sender.value)
            mNickname.text = sender.value;
    }

    private void setMode(int idx) {
        if (mMode >= 0)
            mAnnounce[mMode].servers.active = false;
        mMode = idx;
        if (idx >= 0) {
            assert(idx < mAnnounce.length);
            mAnnounce[idx].servers.active = true;
        }
    }

    private void onKill() {
        if (mClient) {
            mClient.close();
            delete mClient;
        }
        foreach (ref as; mAnnounce) {
            as.servers.close();
        }
        arrayRemoveUnordered(mNickSetting.onChange, &nickSettingChange, true);
        //xxx I don't know about that
        saveSettings();
    }

    private void serverListChange(ServerList sender) {
        if (sender is mAnnounce[mMode].servers) {
            string[] contents;
            mCurServers = null;
            foreach (s; sender.list) {
                contents ~= s.toString();
                mCurServers ~= s.addr;
            }
            //nothing found
            //xxx: currently we can't separate between
            //     "still searching" or "no servers there"
            if (contents.length == 0) {
                if (mAnnounce[mMode].servers.active)
                    contents ~= translate("connect.noservers");
                else
                    contents ~= translate("connect.announceerror");
            }
            mAnnounce[mMode].list.setContents(contents);
        }
    }

    private bool onFrame() {
        if (mConnectWnd.wasClosed()) {
            onKill();
            return false;
        }

        if (mClient)
            mClient.tick();
        if (mMode >= 0) {
            mAnnounce[mMode].servers.tick();
        }

        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("cmdclient");
        mNickSetting = addSetting!(string)("net.nickname", "Player",
            SettingType.String);
    }
}

class CreateNetworkGame : SimpleContainer {
    private {
        LevelWidget mLevelSelector;
        Widget mDialog, mWaiting;
    }

    void delegate() onCancel;
    void delegate() onWantStart;
    void delegate(GameConfig conf) onStart;

    this() {
        auto config = loadConfig("dialogs/netgamesetup_gui.conf");
        auto loader = new LoadGui(config);

        mLevelSelector = new LevelWidget();
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
        ConfigNode node = loadConfig("newgame_net.conf");
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
                string[] wormNames;
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
                        memberNode.add("", myformat("Worm %s", i));
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

        conf.randomSeed = to!(string)(generateRandomSeed());

        onStart(conf);
    }

    private void cancelClick(Button sender) {
        if (onCancel)
            onCancel();
    }
}

class CmdNetLobbyTask {
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
        WindowWidget mLobbyWnd, mCreateWnd;
        GameSummary mGameSummary;
    }

    this(CmdNetClient client) {
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

        auto config = loadConfig("dialogs/lobby_gui.conf");
        auto loader = new LoadGui(config);
        loader.load();

        //--------------------------------------------------------------

        mLobbyDlg = loader.lookup("lobby_root");

        mTeams = loader.lookup!(DropDownList)("dd_teams");
        mTeamNode = loadConfig("teams.conf").getSubNode("teams");
        string[] contents;
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
        mLobbyWnd = gWindowFrame.createWindow(mLobbyDlg,
            translate("lobby.caption", mClient.playerName), Vector2i(550, 500));

        //--------------------------------------------------------------

        mCreateDlg = new CreateNetworkGame();
        mCreateDlg.onCancel = &createCancel;
        mCreateDlg.onWantStart = &createWantStart;
        mCreateDlg.onStart = &createStart;

        addTask(&onFrame);
    }

    private void cmdlineFalbackExecute(CommandLine sender, string line) {
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
            translateError(code)));
        mConsoleWidget.enabled = false;
    }

    private void teamSelect(DropDownList sender) {
        mClient.deployTeam(mTeamNode.getSubNode(sender.selection));
    }

    private void cancelClick(Button sender) {
        mLobbyWnd.remove();
    }

    private void hostGame(Button sender) {
        if (mClient.connected) {
            //ask if we are allowed to create a game
            mClient.requestCreateGame();
        }
    }

    //the server allowed someone to create a game
    private void onHostGrant(CmdNetClient sender, uint playerId,
        SPGrantCreateGame.State state)
    {
        if (playerId == mClient.myId) {
            //we want to create a game, show the setup window
            if (state == SPGrantCreateGame.State.granted) {
                mCreateDlg.reset();
                if (!mCreateWnd) {
                    mCreateWnd = gWindowFrame.createWindow(mCreateDlg,
                        r"\t(gamesetup.caption_net)");
                    mCreateWnd.onClose = &createClose;
                } else {
                    gWindowFrame.addWindow(mCreateWnd);
                }
            }
        } else {
            if (mCreateWnd)
                mCreateWnd.remove();
            //show a message that someone else is creating a game
            string name;
            mClient.idToPlayerName(playerId, name);
            switch (state) {
                case SPGrantCreateGame.State.granted:
                    mConsole.writefln(translate("lobby.hostinprogress", name));
                    break;
                case SPGrantCreateGame.State.revoked:
                    mConsole.writefln(translate("lobby.hostaborted", name));
                    break;
                case SPGrantCreateGame.State.starting:
                    mConsole.writefln(translate("lobby.hoststarting", name));
                    break;
            }
        }
    }

    //got team info, assemble and send GameConfig
    //Big xxx: all data is loaded from newgame_net.conf, need setup dialog
    private void onHostAccept(CmdNetClient sender, NetTeamInfo info,
        ConfigNode persistentState)
    {
        mCreateDlg.doStart(info, persistentState);
    }

    //CreateNetworkGame callbacks -->

    private void createCancel() {
        //tell the server that someone else can create a game
        mClient.requestCreateGame(false);
        mCreateWnd.remove();
    }

    private void createWantStart() {
        //user clicked the "Go" button, request team info
        mClient.prepareCreateGame();
    }

    private void createStart(GameConfig conf) {
        //really start
        log.minor("debug dump!");
        saveConfig(conf.save(), "dump.conf");

        mClient.createGame(conf);
        mCreateWnd.remove();
    }

    private void createClose(WindowWidget sender) {
        createCancel();
    }

    //<-- CreateNetworkGame end

    private void executeCommand(string cmd) {
        mClient.lobbyCmd(cmd);
    }

    private void onGameKill() {
        ConfigNode persist;
        if (mGame && mGame.gamePersist) {
            persist = mGame.gamePersist;
            mGameSummary = new GameSummary(persist);
            if (mGameSummary.gameOver)
                persist = null;
        }
        mGame = null;
        if (mClient)
            mClient.gameKilled(persist);
    }

    private void onStartLoading(SimpleNetConnection sender, GameLoader loader) {
        if (mCreateWnd)
            mCreateWnd.remove();
        if (mGameSummary) {
            mGameSummary.remove();
            mGameSummary = null;
        }
        //mConsole.writefln(translate("lobby.gamestarting"));
        mGame = new GameTask(loader, mClient);
    }

    private void onUpdatePlayers(SimpleNetConnection sender)
    {
        string[] contents;
        contents.length = mClient.playerCount;
        int idx = 0;
        foreach (ref NetPlayerInfo pinfo; mClient) {
            contents[idx] = myformat("%s (%s), %s", pinfo.name, pinfo.teamName,
                pinfo.ping);
            idx++;
        }
        mPlayers.setContents(contents);
    }

    private void onError(CmdNetClient sender, string msg, string[] args) {
        //lobby error
        mConsole.writefln(translate("lobby.c_serror", msg));
    }

    private void onMessage(CmdNetClient sender, string[] text) {
        if (!mLobbyWnd.wasClosed) {
            foreach (l; text) {
                mConsole.writefln(l);
            }
        }
    }

    private void onKill() {
        mClient.close();
        delete mClient;
    }

    private bool onFrame() {
        if (mLobbyWnd.wasClosed) {
            onKill();
            return false;
        }
        mClient.tick();
        if (mGame && !mGame.active)
            onGameKill();
        return true;
    }
}
