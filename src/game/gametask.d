module game.gametask;

import common.common;
import common.task;
import common.loadsave;
import common.resources;
import common.resset;
import common.resview;
import framework.commandline;
import framework.framework;
import framework.filesystem;
import framework.font;
import framework.i18n;
import utils.timesource;
import framework.lua;
import game.gui.loadingscreen;
import game.hud.gameframe;
import game.hud.teaminfo;
import game.hud.gameview;
import game.clientengine;
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
import gui.tablecontainer;
import gui.widget;
import gui.wm;
import gui.button;
import gui.dropdownlist;
import gui.boxcontainer;
import gui.list;
import utils.array;
import utils.misc;
import utils.mybox;
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
import tango.io.device.File : File;

//these imports register classes in a factory on module initialization
import game.animation;
//BEGIN action stuff imports; to be removed soon --->
import game.action.common;
import game.action.list;
import game.action.spawn;
import game.action.weaponactions;
import game.action.spriteactions;
import game.weapon.projectile;
import game.weapon.ray;
import game.weapon.melee;
//<--- END action stuff imports
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
import game.controller_plugins;
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

class GameTask : StatefulTask {
    private {
        GameShell mGameShell; //can be null, if a client in a network game!
        GameLoader mGameLoader; //creates a GameShell
        GameEngine mGame;
        ClientGameEngine mClientEngine;
        ClientControl mControl;
        GameInfo mGameInfo;
        SimpleNetConnection mConnection;

        GameFrame mGameFrame;
        SimpleContainer mWindow;

        LoadingScreen mLoadScreen;
        Loader mGUIGameLoader;
        Resources.Preloader mResPreloader;

        CommandBucket mCmds;

        Fader mFader;
        const cFadeOutDuration = timeSecs(2);
        const cFadeInDuration = timeMsecs(500);

        bool mDelayedFirstFrame; //draw screen before loading first chunk

        ConfigNode mGamePersist;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm, char[] args = "") {
        super(tm);

        createWindow();

        if (str.eatStart(args, "demo:")) {
            mGameLoader = GameLoader.CreateFromDemo(args);
            doInit();
            return;
        }

        ConfigNode node;
        if (str.eatStart(args, "config:")) {
            node = loadConfig(args);
            args = "";
        } else {
            node = loadConfig("newgame");
        }

        //hack, what else
        //there should be a proper command line parser (for lumbricus.d too)
        if (args == "freegraphics") {
            args = "";
            node.getSubNode("gfx")["config"] = "freegraphics.conf";
        }

        if (args == "") {
            initGame(loadGameConfig(node));
            return;
        }

        throw new CustomException("unknown commandline params: >"~args~"<");
    }

    //start a game
    this(TaskManager tm, GameConfig cfg) {
        super(tm);

        createWindow();
        initGame(cfg);
    }

    this(TaskManager tm, TarArchive savedState) {
        super(tm);

        createWindow();
        initFromSave(savedState);
    }

    this(TaskManager tm, GameLoader loader, SimpleNetConnection con) {
        super(tm);

        mGameLoader = loader;
        mConnection = con;
        mConnection.onGameStart = &netGameStart;

        createWindow();
        doInit();
    }

    private void createWindow() {
        mWindow = new SimpleContainer();
        auto wnd = gWindowManager.createWindowFullscreen(this, mWindow,
            r"\t(game_title)");
        //background is mostly invisible, except when loading and at low
        //detail levels (where the background isn't completely overdrawn)
        auto props = wnd.properties;
        props.background = Color(0); //black :)
        wnd.properties = props;

        mCmds = new CommandBucket();
        mCmds.helpTranslator = localeRoot.bindNamespace(
            "console_commands.gametask");
        registerCommands();
        mCmds.bind(globals.cmdLine);
    }

    private void netGameStart(SimpleNetConnection sender, ClientControl control)
    {
        mControl = control;
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        mGameLoader = GameLoader.CreateNewGame(cfg);
        doInit();
    }

    private void initFromSave(TarArchive tehfile) {
        auto guiconf = tehfile.readConfigStream("gui.conf");

        //mSavedViewPosition = guiconf.getValue!(Vector2i)("viewpos");
        //mSavedSetViewPosition = true;

        mGameLoader = GameLoader.CreateFromSavegame(tehfile);
        doInit();
    }

    void doInit() {
        mLoadScreen = new LoadingScreen();
        mLoadScreen.zorder = 10;
        assert (!!mWindow);
        mWindow.add(mLoadScreen);

        auto load_txt = localeRoot.bindNamespace("loading.game");
        char[][] chunks;

        void addChunk(LoadChunkDg cb, char[] txt_id) {
            chunks ~= load_txt(txt_id);
            mGUIGameLoader.registerChunk(cb);
        }

        mGUIGameLoader = new Loader();
        addChunk(&initLoadResources, "resources");
        addChunk(&initGameEngine, "gameengine");
        addChunk(&initClientEngine, "clientengine");
        addChunk(&initGameGui, "gui");
        mGUIGameLoader.onFinish = &gameLoaded;

        mLoadScreen.setPrimaryChunks(chunks);
    }

    private void unloadGame() {
        //log("unloadGame");
        /+if (mServerEngine) {
            mServerEngine.kill();
            mServerEngine = null;
        }+/
        if (mGameShell) {
            mCmds.removeSub(mGameShell.commands());
            mGameShell.terminate();
            Object e = mGameShell.serverEngine;
            //mGameShell.getSerializeContext().death_stomp(e);
        }
        mGameShell = null;
        if (mClientEngine) {
            mClientEngine.kill();
            mClientEngine = null;
        }
        mGame = null;
        mControl = null;
    }

    private bool initGameGui() {
        mGameInfo = new GameInfo(mGameShell, mClientEngine, mControl);
        mGameInfo.connection = mConnection;
        mGameFrame = new GameFrame(mGameInfo);
        mWindow.add(mGameFrame);
        /+
        if (mSavedSetViewPosition) {
            mSavedSetViewPosition = false;
            mGameFrame.setPosition(mSavedViewPosition);
        }
        +/

        return true;
    }

    private bool initGameEngine() {
        //log("initGameEngine");
        if (!mGameShell) {
            mGameShell = mGameLoader.finish();
            mCmds.addSub(mGameShell.commands());
            mGameShell.OnRestoreGuiAfterSnapshot = &guiRestoreSnapshot;
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

    private bool initClientEngine() {
        //log("initClientEngine");
        mClientEngine = new ClientGameEngine(mGame);
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
            debug gResources.showStats();
            mLoadScreen.secondaryActive = false;
            return true;
        }
    }

    private void gameLoaded(Loader sender) {
        //idea: start in paused mode, release poause at end to not need to
        //      reset the gametime
        //if (mServerEngine)
          //  mServerEngine.start();
        //a small wtf: why does client engine have its own time??
        mClientEngine.start();

        //remove this, so the game becomes visible
        mLoadScreen.remove();

        mFader = new Fader(cFadeInDuration, true);
        mWindow.add(mFader);
    }

    private void unloadAndReset() {
        unloadGame();
        if (mWindow) mWindow.remove();
        mWindow = null;
        if (mLoadScreen) mLoadScreen.remove();
        mLoadScreen = null;
        mGUIGameLoader = null;
        mGameLoader = null;
        mResPreloader = null;
        //mSaveGame = null;
        mControl = null;
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        unloadAndReset();
        mCmds.kill();
        if (mGameFrame)
            mGameFrame.remove(); //from GUI
        if (mLoadScreen)
            mLoadScreen.remove();
    }

    override void terminate() {
        //this is called when the window is closed
        //go boom
        kill();
    }

    void terminateWithFadeOut() {
        if (!mFader) {
            mFader = new Fader(cFadeOutDuration, false);
            mWindow.add(mFader);
            mClientEngine.fadeoutMusic(cFadeOutDuration);
        }
    }

    private void doFade() {
        if (mFader && mFader.done) {
            mFader.remove();
            mFader = null;
            if (mGame.logic.gameEnded)
                kill();
        }
    }

    override protected void onFrame() {
        if (mGUIGameLoader.fullyLoaded) {
            if (mGameShell) {
                mGameShell.frame();
                mGameInfo.replayRemain = mGameShell.replayRemain;
                if (mGameShell.terminated)
                    kill();
            }
            if (mClientEngine) {
                mClientEngine.doFrame();
                //synchronize paused state
                //still hacky, but better than GCD
                if (mGameShell)
                    mClientEngine.paused = mGameShell.paused;

                //maybe
                if (mGame.logic.gameEnded) {
                    assert(!!mGameShell && !!mGameShell.serverEngine);
                    mGamePersist = mGameShell.serverEngine.persistentState;
                    terminateWithFadeOut();
                }
            }
        } else {
            if (mDelayedFirstFrame) {
                mGUIGameLoader.loadStep();
            }
            mDelayedFirstFrame = true;
            //update GUI (Loader/LoadingScreen aren't connected anymore)
            mLoadScreen.primaryPos = mGUIGameLoader.currentChunk;
        }

        //he-he
        doFade();
    }

    //implements StatefulTask
    override void saveState(TarArchive tehfile) {
        if (!mGameShell)
            throw new CustomException("can't save network game as client");

        mGameShell.saveGame(tehfile);

        auto guiconf = new ConfigNode();
        guiconf.setValue!(Vector2i)("viewpos", mGameFrame.getPosition());
        auto zwriter = tehfile.openWriteStream("gui.conf");
        guiconf.writeFile(zwriter);
        zwriter.close();
    }

    //game specific commands
    private void registerCommands() {
        if (!mConnection) {
            mCmds.register(Command("slow", &cmdSlow, "", ["float", "text?"]));
            mCmds.register(Command("snap", &cmdSnapTest, "", ["int"]));
            mCmds.register(Command("replay", &cmdReplay, "", ["text?"]));
            mCmds.register(Command("demo_stop", &cmdDemoStop, ""));
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
            auto ph = mGameShell.serverEngine.physicworld;
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
                l.text = myformat("{}: {}", n, types[n].name);
                addc(0, n+1, l);
                l = new Label();
                l.text = myformat("{}", n);//types[n].name;
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
        gWindowManager.createWindow(this, new ShowCollide(),
            "Collision matrix");
    }

    private void cmdGameRes(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        new ResViewerTask(manager, mGameShell.serverEngine.gfx.resources);
    }

    private void cmdLua(MyBox[] args, Output write) {
        new LuaInterpreter(manager, mGameShell.serverEngine.scripting);
    }

    //slow time <whatever>
    //whatever can be "game", "ani" or left out
    private void cmdSlow(MyBox[] args, Output write) {
        bool setgame, setani;
        switch (args[1].unboxMaybe!(char[])) {
            case "game": setgame = true; break;
            case "ani": setani = true; break;
            default:
                setgame = setani = true;
        }
        float val = args[0].unbox!(float);
        if (setgame) {
            write.writefln("set slowdown: game={}", val);
            mControl.executeCommand(myformat("slow_down {}", val));
        }
        if (setani) {
            write.writefln("set slowdown: client={}", val);
            mClientEngine.setSlowDown(val);
        }
    }

    private void cmdDemoStop(MyBox[], Output) {
        if (mGameShell)
            mGameShell.stopDemoRecorder();
    }

    private void cmdExecServer(MyBox[] args, Output write) {
        //send command to the server
        char[] srvCmd = args[0].unbox!(char[]);
        mControl.executeCommand(srvCmd);
    }

    private void cmdSnapTest(MyBox[] args, Output write) {
        if (!mGameShell)
            return;
        int arg = args[0].unbox!(int);
        if (arg & 1) {
            doEngineSnap();
        }
        if (arg & 2) {
            doEngineUnsnap();
        }
    }

    private void cmdReplay(MyBox[] args, Output write) {
        char[] arg = args[0].unboxMaybe!(char[]);
        if (mGameShell.replayMode) {
            mGameShell.replaySkip();
        } else {
            if (arg.length > 0)
                mGameShell.snapForReplay();
            else
                mGameShell.replay();
        }
    }

    GameShell.GameSnap snapshot;

    private void doEngineSnap() {
        mGameShell.doSnapshot(snapshot);
    }

    private void doEngineUnsnap() {
        mGameShell.doUnsnapshot(snapshot);
    }

    private void guiRestoreSnapshot() {
        //important: readd graphics, because they could have changed
        mClientEngine.readd_graphics();
        mGameFrame.gameView.readd_graphics();
    }

    ConfigNode gamePersist() {
        return mGamePersist;
    }

    const cSaveId = "lumbricus";

    override char[] saveId() {
        return cSaveId;
    }

    static this() {
        TaskFactory.register!(typeof(this))("game");
        StatefulFactory.register!(typeof(this))(cSaveId);
    }
}

class LuaInterpreter : Task {
    private {
        CommandLine mCmdLine;
        LuaState mLua;
        Output mOut;
    }

    this(TaskManager mgr, char[] args = "") {
        auto state = new LuaState();

        //copy and paste
        //don't want to put this in framework.lua (too many weird dependencies)
        void loadscript(char[] filename) {
            filename = "lua/" ~ filename;
            auto st = gFS.open(filename);
            scope(exit) st.close();
            state.loadScript(filename, cast(char[])st.readAll());
        }

        loadscript("utils.lua");

        this(mgr, state);
    }

    this(TaskManager mgr, LuaState state) {
        super(mgr);

        mLua = state;

        auto w = new GuiConsole();
        mCmdLine = w.cmdline();
        mCmdLine.setPrefix("/", "exec");
        mCmdLine.registerCommand("exec", &cmdExec, "execute a Lua command",
            ["text...:code"]);
        mOut = w.output;
        mOut.writefln("Scripting console using: {}", mLua.cLanguageAndVersion);
        gWindowManager.createWindow(this, w, "Lua Console", Vector2i(400, 200));

        //this might be a bit dangerous/unwanted
        //but we need it for this console
        //alternatively, maybe one could create a sub-environment or whatever,
        //  that just shadows the default output function, or so
        mLua.setPrintOutput(&printOutput);
    }

    private void printOutput(char[] s) {
        mOut.writef("{}", s);
    }

    private void cmdExec(MyBox[] args, Output output) {
        auto code = args[0].unbox!(char[])();
        //somehow looks less confusing to include the command in the output
        mOut.writefln("> {}", code);
        //NOTE: this doesn't implement passing several lines as one piece of
        //  code; the Lua command line interpreter uses a very hacky way to
        //  detect the end of lines (it parses the parser error message); should
        //  we also do this?
        //http://www.lua.org/source/5.1/lua.c.html
        try {
            mLua.loadScript("input", code);
        } catch (ScriptingException e) {
            mOut.writefln("Lua error: {}", e);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("luaconsole");
    }
}
