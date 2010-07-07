module game.gametask;

import common.common;
import common.lua;
import common.task;
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
import gui.tablecontainer;
import gui.widget;
import gui.window;
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

class GameTask {
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

        CommandBucket mCmds;

        Fader mFader;
        const cFadeOutDuration = timeSecs(2);
        const cFadeInDuration = timeMsecs(500);

        bool mDelayedFirstFrame; //draw screen before loading first chunk

        ConfigNode mGamePersist;

        bool mDead;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(char[] args = "") {
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
    this(GameConfig cfg) {
        createWindow();
        initGame(cfg);
    }

    this(GameLoader loader, SimpleNetConnection con) {
        mGameLoader = loader;
        mConnection = con;
        mConnection.onGameStart = &netGameStart;

        createWindow();
        doInit();
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
        globals.cmdLine.addSub(mCmds);
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
        addChunk(&initGameGui, "gui");
        mGUIGameLoader.onFinish = &gameLoaded;

        mLoadScreen.setPrimaryChunks(chunks);

        addTask(&onFrame);
    }

    private void unloadGame() {
        //log("unloadGame");
        /+if (mServerEngine) {
            mServerEngine.kill();
            mServerEngine = null;
        }+/
        if (mGameShell) {
            mGameShell.terminate();
            Object e = mGameShell.serverEngine;
            //mGameShell.getSerializeContext().death_stomp(e);
        }
        mGameShell = null;
        if (mGameFrame) {
            mGameFrame.kill();
        }
        mGame = null;
        mControl = null;
    }

    private bool initGameGui() {
        mGameInfo = new GameInfo(mGameShell, mControl);
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

    private void gameLoaded(Loader sender) {
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

    void kill() {
        if (mDead)
            return;
        mDead = true;
        mRealWindow.remove();
        unloadAndReset();
        mCmds.kill();
        if (mGameFrame)
            mGameFrame.remove(); //from GUI
        if (mLoadScreen)
            mLoadScreen.remove();
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
        if (mGUIGameLoader.fullyLoaded) {
            if (mGameShell) {
                mGameShell.frame();
                mGameInfo.replayRemain = mGameShell.replayRemain;
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
            mLoadScreen.primaryPos = mGUIGameLoader.currentChunk;
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
        float val = args[0].unbox!(float);
        write.writefln("set slow_down={}", val);
        mControl.executeCommand(myformat("slow_down {}", val));
    }

    private void cmdStep(MyBox[] args, Output write) {
        auto val = args[0].unbox!(int);
        write.writefln("single_step {}", val);
        mControl.executeCommand(myformat("single_step {}", val));
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

    this(char[] args = "") {
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

    private void printOutput(char[] s) {
        mOut.writef("{}", s);
    }

    private void cmdExec(MyBox[] args, Output output) {
        exec(args[0].unbox!(char[])());
    }

    static this() {
        registerTaskClass!(typeof(this))("luaconsole");
    }
}
