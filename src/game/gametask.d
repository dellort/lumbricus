module game.gametask;

import common.globalconsole;
import common.lua;
import common.task;
import common.resources;
import common.resset;
import common.resview;
import framework.config;
import framework.commandline;
import framework.drawing;
import framework.filesystem;
import framework.font;
import framework.i18n;
import framework.surface;
import utils.timesource;
import framework.lua;
import game.gui.loadingscreen;
import game.hud.gameframe;
import game.hud.teaminfo;
import game.hud.gameview;
import game.controller;
import game.core;
import game.loader;
import game.gameshell;
import game.game;
import game.setup;
//--> following 2 imports are not actually needed, but avoid linker errors
//    on windows with game.gui.leveledit disabled in lumbricus.d
import game.levelgen.placeobjects;
import game.levelgen.genrandom;
//<--
import gui.console;
import gui.container;
import gui.global;
import gui.label;
import gui.logwindow;
import gui.tablecontainer;
import gui.widget;
import gui.window;
import gui.button;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.list;
import utils.array;
import utils.color;
import utils.misc;
import utils.mybox : MyBox;
import utils.output;
import utils.rect2;
import utils.time;
import utils.vector2;
import utils.log;
import utils.configfile;
import utils.random;
import utils.path;
import utils.perf;
import utils.archive;
import str = utils.string;

//import game.serialize_register : initGameSerialization;

import utils.stream;

//these imports register classes in a factory on module initialization
import game.animation;
import game.weapon.girder;
import game.weapon.rope;
import game.weapon.jetpack;
import game.weapon.drill;
import game.weapon.napalm;
import game.weapon.parachute;
import game.weapon.airstrike;
import game.weapon.luaweapon;
import game.gamemodes.turnbased;
import game.gamemodes.realtime;
import game.plugin.messages;
import game.plugin.persistence;
import game.plugin.statistics;
import game.lua.all;


class Fader : Widget {
    private {
        Time mFadeStartTime;
        int mFadeDur;
        Color mStartCol = {0,0,0,0};
        Color mEndCol = {0,0,0,1};
        Color mColor;
    }

    bool done;

    this(Time fadeTime, bool fadeIn) {
        focusable = false;
        isClickable = false;
        if (fadeIn)
            swap(mStartCol, mEndCol);
        mColor = mStartCol;
        mFadeStartTime = timeCurrentTime;
        mFadeDur = fadeTime.msecs;
    }

    override void onDraw(Canvas c) {
        c.drawFilledRect(widgetBounds, mColor);
    }

    override void simulate() {
        super.simulate();
        int mstime = (timeCurrentTime - mFadeStartTime).msecs;
        if (mstime > mFadeDur) {
            //end of fade
            done = true;
        } else {
            float scale = 1.0f*mstime/mFadeDur;
            mColor = mStartCol + (mEndCol - mStartCol) * scale;
        }
    }
}

LogStruct!("game") gGameLog;

class GameTask : IKillable {
    private {
        GameShell mGameShell;
        GameLoader mGameLoader; //creates a GameShell
        GameCore mGame;
        ClientControl mControl;
        GameInfo mGameInfo;
        SimpleNetConnection mConnection;

        GameFrame mGameFrame;
        SimpleContainer mWindow;
        WindowWidget mRealWindow;

        LoadingScreen mLoadScreen;
        Loader mGUIGameLoader;
        Resources.Preloader mResPreloader;
        LogBackend mLoadLog;
        Widget mErrorDialog;

        CommandBucket mCmds;

        Fader mFader;
        enum cFadeOutDuration = timeSecs(2);
        enum cFadeInDuration = timeMsecs(500);

        bool mDelayedFirstFrame; //draw screen before loading first chunk

        ConfigNode mGamePersist;

        bool mDead;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(string args = "") {
        //hack, what else
        //there should be a proper command line parser (for lumbricus.d too)
        //actually, normally the newgame.conf would contain all this stuff, and
        //  we need a proper way to create sucha a .conf to start a new game
        string[] argv = str.split(args);
        string start_config;
        string start_demo;
        string graphics;

        foreach (arg; argv) {
            if (str.eatStart(arg, "demo:")) {
                start_demo = arg;
                continue;
            }

            if (str.eatStart(arg, "config:")) {
                start_config = arg;
                continue;
            }

            if (str.eatStart(arg, "graphics:")) {
                graphics = arg;
                continue;
            }

            throwError("unknown argument for game spawning: '%s'", arg);
        }

        if (start_demo.length) {
            createWindow();
            doInit({
                mGameLoader = GameLoader.CreateFromDemo(start_demo);
            });
            return;
        }

        ConfigNode node;

        if (start_config.length) {
            node = loadConfig(start_config);
        } else {
            node = loadConfig("newgame.conf");
        }

        if (graphics.length)
            node.getSubNode("gfx")["config"] = graphics ~ ".conf";

        createWindow();
        doInit({
            mGameLoader = GameLoader.CreateNewGame(loadGameConfig(node));
        });
    }

    //start a game
    this(GameConfig cfg) {
        createWindow();
        doInit({
            mGameLoader = GameLoader.CreateNewGame(cfg);
        });
    }

    this(GameLoader loader, SimpleNetConnection con) {
        createWindow();
        doInit({
            mGameLoader = loader;
            mConnection = con;
            mConnection.onGameStart = &netGameStart;
        });
    }

    private void createWindow() {
        mWindow = new SimpleContainer();
        mRealWindow = gWindowFrame.createWindowFullscreen(mWindow,
            r"\t(game_title)");
        //background is mostly invisible, except when loading and at low
        //detail levels (where the background isn't completely overdrawn)
        auto props = mRealWindow.properties;
        props.background = Color(0); //black :)
        mRealWindow.properties = props;

        mCmds = new CommandBucket();
        mCmds.helpTranslator = localeRoot.bindNamespace(
            "console_commands.gametask");
        registerCommands();
        mRealWindow.commands = mCmds;
    }

    private void netGameStart(SimpleNetConnection sender, ClientControl control)
    {
        mControl = control;
    }

    //silly wrapper to avoid writing tedious try-catch blocks
    //  phase = what loading phase the code is in
    //  code = code to be executed; exceptions will be catched and treated as
    //      load errors
    //  returns if code was executed successfully
    private bool tryLoad(string phase, scope void delegate() code) {
        try {
            code();
            return true;
        } catch (CustomException e) {
            loadFailed(phase, e);
            return false;
        }
    }

    //if tryLoad is far too silly
    private void loadFailed(string phase, Exception e) {
        gGameLog.error("error when %s: %s", phase, e);
        traceException(gGameLog.get, e);
        loadingFailed();
    }

    //set up the GUI, and call the load phases over the following frames
    //creator is called first
    //xxx: I'd like to put "creator" as extra chunk with addChunk, but that
    //  would require proper closure support; so it's called immediately for now
    void doInit(scope void delegate() creator) {
        //kill remains?
        killGame();

        //prepare loading - set up logger so we can show that to the user if
        //  loading fails
        assert(!mLoadLog);
        mLoadLog = new LogBackend("game loader", LogPriority.Notice, null);

        //create game (xxx: should be the first chunk added via addChunk)
        if (!tryLoad("creating game", creator))
            return;

        assert(!mLoadScreen);
        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        assert (!!mWindow);
        mWindow.add(mLoadScreen);

        auto load_txt = localeRoot.bindNamespace("loading.game");
        string[] chunks;

        void addChunk(LoadChunkDg cb, string txt_id) {
            chunks ~= load_txt(txt_id);
            mGUIGameLoader.registerChunk(cb);
        }

        mGUIGameLoader = new Loader();
        addChunk(&initLoadResources, "resources");
        addChunk(&initGameEngine, "gameengine");
        addChunk(&initGameGui, "gui");
        mGUIGameLoader.onFinish = &gameLoaded;

        mLoadScreen.setPrimaryChunks(chunks);

        addTask(&onFrame);
    }

    private void killGame() {
        //--- loader
        if (mLoadScreen)
            mLoadScreen.remove();
        mLoadScreen = null;

        mGUIGameLoader = null;
        mGameLoader = null;
        mResPreloader = null;

        if (mLoadLog)
            mLoadLog.retire();
        mLoadLog = null;

        //--- game (remains)
        if (mGameFrame) {
            mGameFrame.kill();
            mGameFrame.remove();
        }
        if (mGameShell) {
            mGameShell.terminate();
        }
        delete mGameShell;
        delete mGame;
        mGameShell = null;
        mGame = null;
        mControl = null;
        mConnection = null;
        mGameInfo = null;
    }

    private bool initGameGui() {
        mGameInfo = new GameInfo(mGameShell, mControl);
        mGameInfo.connection = mConnection;

        try {
            mGameFrame = new GameFrame(mGameInfo);
        } catch (CustomException e) {
            loadFailed("creating game GUI", e);
            return true;
        }

        mWindow.add(mGameFrame);

        return true;
    }

    private bool initGameEngine() {
        //log("initGameEngine");
        if (!mGameShell) {
            try {
                mGameShell = mGameLoader.finish();
            } catch (CustomException e) {
                loadFailed("creating game engine", e);
                return true;
            }
            mGame = mGameShell.serverEngine;
        }
        if (mConnection) {
            if (!mControl)
                return false;
        }

        if (mGameShell && !mControl) {
            //xxx (well, you know)
            mControl = new ClientControl(mGameShell, "local");
        }

        return true;
    }

    //periodically called by loader (stopped when we return true)
    private bool initLoadResources() {
        if (!mGameLoader)
            return true;
        Resources.Preloader preload = mGameLoader.resPreloader;
        if (!preload)
            return true;
        //(actually would only be needed for initialization)
        mLoadScreen.secondaryActive = true;
        mLoadScreen.secondaryCount = preload.totalCount();
        mLoadScreen.secondaryPos = preload.loadedCount();
        //the use in returning after some time is to redraw the screen
        preload.progressTimed(timeMsecs(100));
        if (!preload.done) {
            return false;
        } else {
            mLoadScreen.secondaryActive = false;
            return true;
        }
    }

    //NOTE: may be called even after loading failed
    private void gameLoaded(Loader sender) {
        //remove this, so the game becomes visible
        if (mLoadScreen)
            mLoadScreen.remove();
        mLoadScreen = null;

        if (mGame) {
            mFader = new Fader(cFadeInDuration, true);
            mWindow.add(mFader);
        }

        //this helps a small little bit to reduce heap growth, and also defers
        //  the first collection to a later point in the game, giving the user
        //  the impression that using a GC in a game is a good idea - INGENIOUS!
        //XXXTANGO memory.GC.collect();
    }

    private void loadingFailed() {
        gGameLog.error("loading failed.");

        LogEntry[] logentries = mLoadLog.flushLogEntries();

        killGame();

        //show user what went wrong (this is like a user unfriendly fallback;
        //  for certain types of errors we could/should do a better job?)
        auto log = new LogWindow();
        log.formatted = true;
        foreach (LogEntry e; logentries) {
            writeColoredLogEntry(e, true, &log.writefln);
        }
        //probably add some buttons such as "ok"?
        auto dialog = new SimpleContainer();
        //argh this complicated GUI creation is the reason why our dialogs are
        //  incomplete and crappy
        WidgetLayout lay;
        lay.fill[] = [0.7, 0.7]; //not the whole screen
        dialog.setLayout(lay);
        dialog.styles.addClass("load-error-dialog");
        auto grid = new TableContainer(2, 3, Vector2i(5));
        auto caption = new Label();
        WidgetLayout lay2 = WidgetLayout.Expand(true);
        caption.setLayout(lay2);
        caption.styles.addClass("load-error-caption");
        caption.textMarkup = "\\t(loading.game.failed)";
        grid.add(caption, 0, 0, 2, 1);
        grid.add(log, 0, 1, 2, 1);
        auto b1 = new Button();
        b1.onClick = &onCloseButton;
        b1.textMarkup = "\\t(gui.ok)";
        b1.setLayout(lay2);
        grid.add(b1, 0, 2);
        //button 2 should retroy or something?
        auto b2 = new Button();
        b2.onClick = &onCloseButton;
        b2.textMarkup = "not ok";
        b2.setLayout(lay2);
        grid.add(b2, 1, 2);
        dialog.add(grid);
        mErrorDialog = dialog;
        mWindow.add(dialog);
        assert(dialog.isLinked);
    }

    private void onCloseButton(Button b) {
        kill();
    }

    private void unloadAndReset() {
        killGame();
        if (mWindow) mWindow.remove();
        mWindow = null;
        mErrorDialog = null;
    }

    //IKillable.kill()
    override void kill() {
        if (mDead)
            return;
        mDead = true;
        mRealWindow.remove();
        unloadAndReset();
    }

    void terminateWithFadeOut() {
        if (!mFader) {
            //xxx GameFrame should handle fadeout graphics as well?
            mFader = new Fader(cFadeOutDuration, false);
            mWindow.add(mFader);
            if (mGameFrame)
                mGameFrame.fadeoutMusic(cFadeOutDuration);
        }
    }

    private bool gameEnded() {
        if (!mGame)
            return false;
        return mGame.singleton!(GameController)().gameEnded();
    }

    private void doFade() {
        if (mFader && mFader.done) {
            mFader.remove();
            mFader = null;
            if (gameEnded())
                kill();
        }
    }

    private bool onFrame() {
        if (mRealWindow.wasClosed())
            kill();
        if (mDead)
            return false;
        if (mGUIGameLoader) {
            if (mGUIGameLoader.fullyLoaded) {
                if (mGameShell) {
                    mGameShell.frame();
                    if (mGameShell.terminated)
                        kill();
                }

                //maybe
                if (gameEnded()) {
                    assert(!!mGameShell && !!mGameShell.serverEngine);
                    mGamePersist = mGameShell.serverEngine.persistentState;
                    terminateWithFadeOut();
                }
            } else {
                if (mDelayedFirstFrame) {
                    mGUIGameLoader.loadStep();
                }
                mDelayedFirstFrame = true;
                //update GUI (Loader/LoadingScreen aren't connected anymore)
                if (mLoadScreen)
                    mLoadScreen.primaryPos = mGUIGameLoader.currentChunk;
            }
        }

        //he-he
        doFade();

        return true;
    }

    //game specific commands
    private void registerCommands() {
        if (!mConnection) {
            mCmds.register(Command("slow", &cmdSlow, "", ["float"]));
            mCmds.register(Command("demo_stop", &cmdDemoStop, ""));
            mCmds.register(Command("single_step", &cmdStep, "", ["int?=1"]));
        }
        mCmds.register(Command("show_collide", &cmdShowCollide, ""));
        mCmds.register(Command("server", &cmdExecServer, "", ["text..."]));
        mCmds.register(Command("game_res", &cmdGameRes, "", null));
        mCmds.register(Command("lua", &cmdLua, ""));
    }

    class ShowCollide : Container {
        class Cell : SimpleContainer {
            bool bla, blu;
            override void onDraw(Canvas c) {
                if (bla || blu) {
                    Color cl = bla ? Color(0.7) : Color(1.0,0.7,0.7);
                    c.drawFilledRect(widgetBounds, cl);
                }
                c.drawRect(widgetBounds, Color(0));
                super.onDraw(c);
            }
        }
        this() {
            auto ph = mGameShell.serverEngine.physicWorld;
            auto types = ph.collide.collisionTypes;
            auto table = new TableContainer(types.length+1, types.length+1,
                Vector2i(2));
            void addc(int x, int y, Widget l) {
                Cell c = new Cell();
                c.bla = (y>0) && (x > y);
                c.blu = (y>0) && (x==y);
                c.add(l, WidgetLayout.Aligned(0, 0, Vector2i(1)));
                table.add(c, x, y);
            }
            //column/row headers
            for (int n = 0; n < types.length; n++) {
                auto l = new Label();
                l.text = myformat("%s: %s", n, types[n].name);
                addc(0, n+1, l);
                l = new Label();
                l.text = myformat("%s", n);//types[n].name;
                addc(n+1, 0, l);
            }
            int y = 1;
            foreach (t; types) {
                int x = 1;
                foreach (t2; types) {
                    ImageLabel lbl = new ImageLabel();
                    if (ph.collide.canCollide(t, t2)) {
                        lbl.image = gGuiResources.get!(Surface)
                            ("window_close"); //that icon is good enough
                    }
                    addc(x, y, lbl);
                    table.setHomogeneousGroup(0, x, 1);
                    table.setHomogeneousGroup(1, y, 1);
                    x++;
                }
                y++;
            }
            addChild(table);
        }
    }

    private void cmdShowCollide(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        gWindowFrame.createWindow(new ShowCollide(), "Collision matrix");
    }

    private void cmdGameRes(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        new ResViewerTask(mGameShell.serverEngine.resources);
    }

    private void cmdLua(MyBox[] args, Output write) {
        new LuaConsole(mGameShell.serverEngine.scripting);
    }

    //slow <time>
    private void cmdSlow(MyBox[] args, Output write) {
        if (!mControl)
            return;
        float val = args[0].unbox!(float);
        write.writefln("set slow_down=%s", val);
        mControl.execCommand(myformat("slow_down %s", val));
    }

    private void cmdStep(MyBox[] args, Output write) {
        if (!mControl)
            return;
        auto val = args[0].unbox!(int);
        write.writefln("single_step %s", val);
        mControl.execCommand(myformat("single_step %s", val));
    }

    private void cmdDemoStop(MyBox[], Output) {
        if (mGameShell)
            mGameShell.stopDemoRecorder();
    }

    private void cmdExecServer(MyBox[] args, Output write) {
        if (!mControl)
            return;
        //send command to the server
        string srvCmd = args[0].unbox!(string);
        mControl.execCommand(srvCmd);
    }

    ConfigNode gamePersist() {
        return mGamePersist;
    }

    //game is running
    bool active() {
        return !mDead;
    }

    static this() {
        registerTaskClass!(typeof(this))("game");
    }
}

class LuaConsole : LuaInterpreter {
    private {
        CommandLine mCmdLine;
        Output mOut;
    }

    this(string args = "") {
        this(cast(LuaState)null);
    }

    this(LuaState a_state) {
        auto w = new GuiConsole();
        super(&w.output.writeString, a_state);

        w.setTabCompletion(&tabcomplete);

        mCmdLine = w.cmdline();
        mCmdLine.setPrefix("/", "exec");
        mCmdLine.registerCommand("exec", &cmdExec, "execute a Lua command",
            ["text...:code"]);
        gWindowFrame.createWindow(w, "Lua Console", Vector2i(450, 300));
    }

    private void printOutput(string s) {
        mOut.writef("%s", s);
    }

    private void cmdExec(MyBox[] args, Output output) {
        exec(args[0].unbox!(string)());
    }

    static this() {
        registerTaskClass!(typeof(this))("luaconsole");
    }
}
