module net.lobby;

import common.common;
import common.task;
import framework.commandline;
import framework.framework;
import framework.i18n;
import game.gameshell;
import game.gametask;
import game.gamepublic;
import game.setup;
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
import net.netlayer;
import net.announce;
import net.cmdclient;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.log;

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

        const cRefreshInterval = timeSecs(3);
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

        auto config = gConf.loadConfig("connect_gui");
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
            _("connect.caption"));
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
            mLblError.text = _("connect.error", reasonToString[code]);
        mConnectButton.text = _("connect.connect");
        mConnectButton.enabled = true;
        log("Lost connection to {}: {}", sender.serverAddress,
            reasonToString[code]);
    }

    private void onError(CmdNetClient sender, char[] msg, char[][] args) {
        //connection error
        mLblError.text = _("connect.error", msg);
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
        sender.text = _("connect.connecting");
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
                        contents ~= _("connect.noservers");
                    else
                        contents ~= _("connect.announceerror");
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

class CmdNetLobbyTask : Task {
    private {
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
        Window mLobbyWnd;
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

        auto config = gConf.loadConfig("lobby_gui");
        auto loader = new LoadGui(config);
        loader.load();

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
        mConsoleWidget = loader.lookup!(GuiConsole)("chatbox");
        mConsoleWidget.cmdline.setPrefix("/", "say");
        //warning: CommandBucket (client.commands()) can have only 1 parent
        mConsoleWidget.cmdline.commands.addSub(client.commands());
        mConsoleWidget.cmdline.onFallbackExecute = &cmdlineFalbackExecute;
        mConsole = mConsoleWidget.output;

        loader.lookup!(Button)("btn_leave").onClick = &cancelClick;

        //xxx values should be read from configfile
        mLobbyWnd = gWindowManager.createWindow(this, mLobbyDlg,
            _("lobby.caption", mClient.playerName), Vector2i(550, 500));
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
        mConsole.writefln(_("lobby.c_disconnect",
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
            ConfigNode node = gConf.loadConfig("newgame_net");
            GameConfig conf = loadGameConfig(node, null, false);
            mClient.startLoading(conf);
        }
    }

    private void executeCommand(char[] cmd) {
        mClient.lobbyCmd(cmd);
    }

    private void onGameKill(Task t) {
        if (mClient)
            mClient.gameKilled();
    }

    private void onStartLoading(SimpleNetConnection sender, GameLoader loader) {
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
        mConsole.writefln(_("lobby.c_serror", msg));
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
