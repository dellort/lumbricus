module game.toplevel;

import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import framework.framework;
import framework.commandline;
import framework.i18n;
import game.scene;
import game.animation;
import game.game;
import game.banana;
import game.worm;
import game.common;
import game.physic;
import game.gobject;
import game.leveledit;
import gui.windmeter;
import utils.time;
import utils.configfile;
import utils.log;
import utils.output;
import perf = std.perf;
import gc = std.gc;
import genlevel = levelgen.generator;
import str = std.string;
import conv = std.conv;

//ZOrders!
//maybe keep in sync with game.Scene.cMaxZOrder
//these values are for globals.toplevel.guiscene
enum GUIZOrder : int {
    Invisible = 0,
    Background,
    Game,
    Gui,
    Console,
    FPS,
}

//this contains the mainframe
class TopLevel {
    FontLabel fpsDisplay;
    Font consFont;
    Screen screen;
    Scene guiscene;
    //overengineered
    private SceneView sceneview;
    private void delegate() mOnStopGui; //associated with sceneview
    LevelEditor editor;
    Console console;
    KeyBindings keybindings;
    GameEngine thegame;
    //xxx move this to where-ever
    Translator localizedKeynames;
    //ConfigNode mWormsAnim;
    //Animator mWormsAnimator;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    private WindMeter mGuiWindMeter;

    private char[] mGfxSet = "gpl";

    this() {
        initTimes();

        screen = new Screen(globals.framework.screen.size);

        guiscene = screen.rootscene;

        sceneview = new SceneView();
        sceneview.setScene(guiscene, GUIZOrder.Game); //container!
        //sceneview is simply the window that shows the level
        sceneview.pos = Vector2i(0, 0);
        sceneview.thesize = guiscene.thesize;

        initConsole();

        fpsDisplay = new FontLabel(globals.framework.getFont("fpsfont"));
        fpsDisplay.setScene(guiscene, GUIZOrder.FPS);
        mGuiWindMeter = new WindMeter();

        globals.framework.onFrame = &onFrame;
        globals.framework.onKeyPress = &onKeyPress;
        globals.framework.onKeyDown = &onKeyDown;
        globals.framework.onKeyUp = &onKeyUp;
        globals.framework.onMouseMove = &onMouseMove;
        globals.framework.onVideoInit = &onVideoInit;

        //do it yourself... (initial event)
        onVideoInit(false);

        /+ to be removed
        mWormsAnim = globals.loadConfig("wormsanim");
        mWormsAnimator = new Animator();
        mWormsAnimator.setScene(gamescene, 2);
        mWormsAnimator.pos = Vector2i(100,330);
        +/

        localizedKeynames = new Translator("keynames");

        keybindings = new KeyBindings();
        keybindings.loadFrom(globals.loadConfig("binds").getSubNode("binds"));
    }

    private void initConsole() {
        console = new Console(globals.framework.getFont("console"));
        Color console_color;
        if (parseColor(globals.anyConfig.getSubNode("console")
            .getStringValue("backcolor"), console_color))
        {
            console.backcolor = console_color;
        }
        globals.cmdLine = new CommandLine(console);

        globals.defaultOut = console;
        gDefaultOutput.destination = globals.defaultOut;

        auto consrender = new CallbackSceneObject();
        consrender.setScene(guiscene, GUIZOrder.Console);
        consrender.onDraw = &renderConsole;

        globals.cmdLine.registerCommand("gc", &testGC, "timed GC run");
        globals.cmdLine.registerCommand("quit", &killShortcut, "kill it");
        globals.cmdLine.registerCommand("toggle", &showConsole,
            "toggle this console");
        globals.cmdLine.registerCommand("log", &cmdShowLog,
            "List and modify log-targets");
        globals.cmdLine.registerCommand("level", &cmdGenerateLevel,
            "Generate new level");
        globals.cmdLine.registerCommand("bind", &cmdBind,
            "display/edit key bindings");
        globals.cmdLine.registerCommand("nameit", &cmdNameit, "name a key");
        globals.cmdLine.registerCommand("video", &cmdVideo, "set video");
        globals.cmdLine.registerCommand("fullscreen", &cmdFS, "toggle fs");
        globals.cmdLine.registerCommand("phys", &cmdPhys, "test123");
        globals.cmdLine.registerCommand("expl", &cmdExpl, "BOOM! HAHAHAHA");
        globals.cmdLine.registerCommand("pause", &cmdPause, "pause");
        //globals.cmdLine.registerCommand("loadanim", &cmdLoadAnim, "load worms animation");
        globals.cmdLine.registerCommand("clouds", &cmdClouds, "enable/disable animated clouds");
        globals.cmdLine.registerCommand("simplewater", &cmdSimpleWater, "set reduced water mode");

        globals.cmdLine.registerCommand("editor", &cmdLevelEdit, "hm");

        globals.cmdLine.registerCommand("gfxset", &cmdGfxSet, "Set level graphics style");
        globals.cmdLine.registerCommand("wind", &cmdSetWind, "Change wind speed");
        globals.cmdLine.registerCommand("stop", &cmdStop, "stop editor/game");

        globals.cmdLine.registerCommand("slow", &cmdSlow, "todo");
    }

    private void cmdStop(CommandLine) {
        if (mOnStopGui)
            mOnStopGui();
        screen.setFocus(null);
        sceneview.clientscene = null;
        mOnStopGui = null;
    }

    private void setScene(Scene s) {
        //not clean, but we need to redo this GUI-handling stuff anyway
        cmdStop(null);
        sceneview.clientscene = s;
        scrollReset();
    }

    private void initializeGame(GameConfig config) {
        closeGame();
        resetTime();
        //xxx README: since the scene is recreated for each level, there's no
        //            need to remove them all in Game.kill()
        auto gamescene = new Scene();
        setScene(gamescene);
        thegame = new GameEngine(gamescene, config);
        initializeGui();
        //yes, really twice, as no game time should pass while loading stuff
        resetTime();
        mTimeLast = globals.framework.getCurrentTime().msecs;

        //callback when invoking cmdStop
        mOnStopGui = &closeGame;
    }

    private void closeGame() {
        closeGui();
        if (thegame) {
            thegame.kill();
            delete thegame;
            thegame = null;
        }
    }

    private void initializeGui() {
        closeGui();
        mGuiWindMeter.engine = thegame;
        mGuiWindMeter.setScene(guiscene, GUIZOrder.Gui);
        mGuiWindMeter.pos = guiscene.thesize - mGuiWindMeter.size - Vector2i(5,5);
    }

    private void closeGui() {
        mGuiWindMeter.engine = null;
        mGuiWindMeter.setScene(null, GUIZOrder.Gui);
    }

    private void cmdSetWind(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        if (sargs.length < 1)
            return;
        thegame.windSpeed = conv.toFloat(sargs[0]);
    }

    private void cmdGfxSet(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        if (sargs.length < 1)
            return;
        mGfxSet = sargs[0];
    }

    private void killEditor() {
        if (editor) {
            editor.kill();
            editor = null;
        }
    }

    private void cmdLevelEdit(CommandLine cmd) {
        //replace level etc. by the "editor" in a very violent way
        auto editscene = new Scene();
        setScene(editscene);
        editor = new LevelEditor(editscene);
        //clearly sucks, find a better way
        screen.setFocus(editor.render);

        mOnStopGui = &killEditor;
    }

    private void cmdClouds(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        bool on = false;
        if (sargs.length < 1)
            return;
        try {
            on = cast(bool)conv.toInt(sargs[0]);
        } catch (conv.ConvError) {
            return;
        }
        thegame.gameSky.enableClouds = on;
    }

    private void cmdSimpleWater(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        bool simple = false;
        if (sargs.length < 1)
            return;
        try {
            simple = cast(bool)conv.toInt(sargs[0]);
        } catch (conv.ConvError) {
            return;
        }
        thegame.gameWater.simpleMode = simple;
    }

    private void cmdPhys(CommandLine) {
        //oops?
        //auto obj = new TestAnimatedGameObject(thegame);
        //obj.setPos(thegame.tmp);
        assert(false);
    }

    private void cmdExpl(CommandLine) {
        auto obj = new BananaBomb(thegame);
        //obj.setPos(toVector2f(thegame.tmp));
        assert(false);
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: %s", globals.framework.screen.size);
        screen.setSize(globals.framework.screen.size);
        sceneview.thesize = guiscene.thesize;
    }

    private void cmdVideo(CommandLine cmd) {
        int[3] args;
        char[][] sargs = cmd.parseArgs();
        if (sargs.length != 3)
            return;
        try {
            foreach (int idx, inout a; args) {
                a = conv.toInt(sargs[idx]);
            }
        } catch (conv.ConvError) {
            return;
        }
        globals.framework.setVideoMode(args[0], args[1], args[2], false);
    }

    private bool mIsFS;
    private void cmdFS(CommandLine cmd) {
        globals.framework.setVideoMode(globals.framework.screen.size.x1,
            globals.framework.screen.size.x2, globals.framework.bitDepth,
            !mIsFS);
        mIsFS = !mIsFS;
    }

    //bind [name action [keys]]
    private void cmdBind(CommandLine cmd) {
        char[][] args = cmd.parseArgs();
        if (args.length >= 2) {
            switch (args[0]) {
                case "add":
                    char[] bindstr = str.join(args[2..$], " ");
                    keybindings.addBinding(args[1], bindstr);
                    return;
                case "kill":
                    //remove all bindings
                    keybindings.removeBinding(args[1]);
                    return;
                default:
            }
        }
        //else, list all bindings
        cmd.console.writefln("Bindings:");
        keybindings.enumBindings(
            (char[] bind, Keycode code, ModifierSet mods) {
                cmd.console.writefln("    %s='%s' ('%s')", bind,
                    keybindings.unparseBindString(code, mods),
                    translateKeyshortcut(code, mods));
            }
        );
    }

    private void cmdNameit(CommandLine) {
        mKeyNameIt = true;
    }

    //translate into translated user-readable string
    char[] translateKeyshortcut(Keycode code, ModifierSet mods) {
        if (!localizedKeynames)
            return "?";
        char[] res = localizedKeynames(
            globals.framework.translateKeycodeToKeyID(code), "?");
        foreachSetModifier(mods,
            (Modifier mod) {
                res = localizedKeynames(
                    globals.framework.modifierToString(mod), "?") ~ "+" ~ res;
            }
        );
        return res;
    }

    private void cmdShowLog(CommandLine cmd) {

        void setTarget(Log log, char[] targetstr) {
            switch (targetstr) {
                case "stdout":
                    log.setBackend(StdioOutput.output, targetstr); break;
                case "null":
                    log.setBackend(DevNullOutput.output, targetstr); break;
                case "console":
                default:
                    log.setBackend(cmd.console, "console");
            }
        }

        char[][] args = cmd.parseArgs();
        Log[] set;

        if (args.length == 2) {
            if (args[0] == "all") {
                set = gAllLogs.values;
            } else if (args[0] in gAllLogs) {
                set = [gAllLogs[args[0]]];
            }
            if (set.length) {
                foreach (Log log; set) {
                    setTarget(log, args[1]);
                }
                return;
            }
        }

        cmd.console.writefln("Log targets:");
        foreach (Log log; gAllLogs) {
            cmd.console.writefln("  %s -> %s", log.category, log.backend_name);
        }
    }

    //--------------------------- Scrolling start -------------------------

    private bool mScrolling;
    private Vector2f mScrollDest, mScrollOffset;
    private const float K_SCROLL = 0.01f;
    //for scrolling stuff only
    private long mTimeLast;
    private const cScrollStepMs = 10;

    private void scrollToggle() {
        if (mScrolling) {
            //globals.framework.grabInput = false;
            globals.framework.cursorVisible = true;
            globals.framework.unlockMouse();
        } else {
            //globals.framework.grabInput = true;
            globals.framework.cursorVisible = false;
            globals.framework.lockMouse();
            mScrollDest = toVector2f(sceneview.clientoffset);
            mScrollOffset = mScrollDest;
        }
        mScrolling = !mScrolling;
    }

    private void scrollReset() {
        mScrollOffset = toVector2f(sceneview.clientoffset);
        mScrollDest = mScrollOffset;
    }

    private void scrollUpdate(Time curTime) {
        long curTimeMs = curTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset = mScrollOffset + (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            sceneview.clientoffset = toVector2i(mScrollOffset);
        }
    }

    private void scrollMove(Vector2i delta) {
        if (mScrolling) {
            mScrollDest = mScrollDest - toVector2f(delta);
            sceneview.clipOffset(mScrollDest);
        }
    }

    private void scrollCenterOn(Vector2i scenePos, bool instantly = false) {
        mScrollDest = -toVector2f(scenePos - sceneview.thesize/2);
        sceneview.clipOffset(mScrollDest);
        if (instantly) {
            mScrollOffset = mScrollDest;
            sceneview.clientoffset = toVector2i(mScrollOffset);
        }
    }

    //--------------------------- Scrolling end ---------------------------

    /+
    private void cmdLoadAnim(CommandLine cmd) {
        auto a = new Animation(mWormsAnim.getSubNode(cmd.parseArgs[0]));
        std.stdio.writefln("Loaded ",cmd.parseArgs[0]);
        mWormsAnimator.setAnimation(a);
    }
    +/

    private void showConsole(CommandLine) {
        console.toggle();
    }

    private void killShortcut(CommandLine) {
        globals.framework.terminate();
    }

    private void testGC(CommandLine) {
        auto counter = new perf.PerformanceCounter();
        counter.start();
        gc.fullCollect();
        counter.stop();
        Time t;
        t.musecs = counter.microseconds;
        globals.log("GC fullcollect: %s", t);
    }

    private void cmdGenerateLevel(CommandLine cmd) {
        auto x = new genlevel.LevelGenerator();
        x.config = globals.loadConfig("levelgen").getSubNode("levelgen");
        GameConfig cfg;
        cfg.level = x.generateRandom(cmd.getArgString(), mGfxSet);
        cfg.teams = globals.loadConfig("teams");
        initializeGame(cfg);
        //start at level center
        scrollCenterOn(thegame.gamelevel.offset+thegame.gamelevel.levelsize/2, true);
    }

    private void cmdPause(CommandLine) {
        paused = !paused;
    }

    //slow <whatever> time
    //whatever can be "game", "ani" or left out
    private void cmdSlow(CommandLine cmd) {
        auto args = cmd.parseArgs();
        bool setgame, setani;
        float val;
        if (args.length == 2) {
            val = conv.toFloat(args[1]);
            if (args[0] == "game")
                setgame = true;
            else if (args[0] == "ani")
                setani = true;
        } else if (args.length == 1) {
            val = conv.toFloat(args[0]);
            setgame = setani = true;
        } else {
            return;
        }
        float g = setgame ? val : mSlowGame;
        float a = setani ? val : mSlowAni;
        cmd.console.writefln("set slowdown: game=%s animations=%s", g, a);
        setSlowDown(g, a);
    }

    private {
        Time gameStartTime;  //absolute time of start of game (pretty useless)
        //not-slowed-down time of game, also quite useless/dangerous to use
        Time pseudoGameTime;
        Time mPauseStarted; //absolute time of pause start
        Time mPausedTime; //summed amount of time paused
        bool mPauseMode;

        //last simulated time when slowdown was set...
        Time mLastGameTime, mLastAniTime;
        //last real time when slowdown was set; relative to pseudoGameTime...
        Time mLastRealGameTime, mLastRealAniTime;
        //slowdown scale values
        float mSlowGame, mSlowAni;
    }

    private void initTimes() {
        mPauseMode = false;
        gameStartTime = globals.framework.getCurrentTime();
        pseudoGameTime = timeSecs(0);
        mPausedTime = timeSecs(0);

        mLastRealGameTime = mLastRealAniTime = timeSecs(0);
        globals.gameTime = timeSecs(0);
        mLastGameTime = mLastAniTime = globals.gameTime;
        globals.gameTimeAnimations = globals.gameTime;
        setSlowDown(1,1);
    }

    void resetTime() {
        initTimes();
    }

    void paused(bool p) {
        if (p == mPauseMode)
            return;

        mPauseMode = p;
        if (mPauseMode) {
            mPauseStarted = globals.framework.getCurrentTime();
        } else {
            mPausedTime += globals.framework.getCurrentTime() - mPauseStarted;
        }
    }
    bool paused() {
        return mPauseMode;
    }

    //set the slowdown multiplier, 1 = normal, <1 = slower, >1 = faster
    void setSlowDown(float game, float ani) {
        assert(game == game && ani == ani);

        auto realtime = pseudoGameTime;

        //make old values absolute
        mLastGameTime = globals.gameTime;
        mLastAniTime = globals.gameTimeAnimations;
        mLastRealGameTime = mLastRealAniTime = realtime;

        mSlowGame = game;
        mSlowAni = ani;
    }

    //xxx: what about rounding errors??
    //possible solution: reset "Last"-times all i.e. 5 seconds?
    private void doCalcTimes() {
        if (mPauseMode)
            return;

        pseudoGameTime = globals.framework.getCurrentTime()
            - gameStartTime - mPausedTime;

        auto realtime = pseudoGameTime;

        Time doTime(Time lastsim, Time lastreal, double scale) {
            return lastsim + (realtime - lastreal)*scale;
        }

        globals.gameTimeAnimations = doTime(mLastAniTime, mLastRealAniTime,
            mSlowAni);
        globals.gameTime = doTime(mLastGameTime, mLastRealGameTime, mSlowGame);
    }

    private void onFrame(Canvas c) {
        doCalcTimes();

        //std.stdio.writefln("%s %s %s", pseudoGameTime, globals.gameTime,
        //    globals.gameTimeAnimations);

        //use real absolute time (else no scrolling when paused etc.)
        scrollUpdate(globals.framework.getCurrentTime());

        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);

        if (thegame && !mPauseMode) {
            //thegame.doFrame(pseudoGameTime);
            thegame.doFrame(globals.gameTime);
        }

        screen.draw(c);
    }

    private void onKeyPress(KeyInfo infos) {
        if (console.visible && globals.cmdLine.keyPress(infos))
            return;
        if (!console.visible)
            screen.putOnKeyPress(infos);
    }

    private bool onKeyDown(KeyInfo infos) {
        if (mKeyNameIt) {
            //modifiers are also keys, ignore them
            if (globals.framework.isModifierKey(infos.code)) {
                return false;
            }
            auto mods = globals.framework.getModifierSet();
            globals.cmdLine.console.writefln("Key: '%s' '%s'",
                keybindings.unparseBindString(infos.code, mods),
                translateKeyshortcut(infos.code, mods));
            mKeyNameIt = false;
            return false;
        }
        if (mShowKeyDebug) {
            globals.log("down: %s", globals.framework.keyinfoToString(infos));
        }
        if (infos.code == Keycode.MOUSE_RIGHT) {
            scrollToggle();
        }
        char[] bind = keybindings.findBinding(infos.code,
            globals.framework.getModifierSet());
        if (bind) {
            if (mShowKeyDebug) {
                globals.log("Binding '%s'", bind);
            }
            globals.cmdLine.execute(bind, false);
            return false;
        }
        if (!console.visible)
            screen.putOnKeyDown(infos);
        return true;
    }

    private bool onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", globals.framework.keyinfoToString(infos));
        }
        if (!console.visible)
            screen.putOnKeyUp(infos);
        return true;
    }

    private void onMouseMove(MouseInfo mouse) {
        //globals.log("%s", mouse.pos);
        scrollMove(mouse.rel);
        screen.putOnMouseMove(mouse);
    }

    private void renderConsole(Canvas canvas, SceneView parentView) {
        console.frame(canvas);
    }
}
