module game.toplevel;

import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import framework.framework;
import framework.commandline;
import framework.i18n;
import framework.timesource;
import game.scene;
import game.game;
import game.common;
import game.leveledit;
import game.visual;
import game.clientengine;
import game.loader;
import game.loader_game;
import gui.gui;
import gui.guiobject;
import gui.windmeter;
import gui.messageviewer;
import gui.gametimer;
import gui.preparedisplay;
import gui.fps;
import gui.gameview;
import gui.console;
import gui.loadingscreen;
import utils.time;
import utils.configfile;
import utils.log;
import utils.output;
import utils.mylist;
import perf = std.perf;
import gc = std.gc;
import genlevel = levelgen.generator;
import str = std.string;
import conv = std.conv;

//xxx include so that module constructors (static this) are actually called
import game.projectile;
import game.special_weapon;

//this contains the mainframe
class TopLevel {
    Scene metascene;
    //overengineered
    private void delegate() mOnStopGui; //associated with sceneview
    LevelEditor editor;
    KeyBindings keybindings;

    GuiMain mGui;
    GameView mGameView;
    GuiConsole mGuiConsole;
    LoadingScreen mLoadScreen;

    GameEngine thegame;
    ClientGameEngine clientengine;

    //xxx move this to where-ever
    Translator localizedKeynames;
    //ConfigNode mWormsAnim;
    //Animator mWormsAnimator;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    private GameLoader mGameLoader;

    this() {
        initTimes();

        mGui = new GuiMain(globals.framework.screen.size);

        mGui.add(new GuiFps(), GUIZOrder.FPS);

        mGuiConsole = new GuiConsole();
        mGui.add(mGuiConsole, GUIZOrder.Console);

        mLoadScreen = new LoadingScreen();
        mGui.add(mLoadScreen, GUIZOrder.Loading);
        mLoadScreen.active = false;

        initConsole();

        globals.framework.onFrame = &onFrame;
        globals.framework.onKeyPress = &onKeyPress;
        globals.framework.onKeyDown = &onKeyDown;
        globals.framework.onKeyUp = &onKeyUp;
        globals.framework.onMouseMove = &onMouseMove;
        globals.framework.onVideoInit = &onVideoInit;

        //do it yourself... (initial event)
        onVideoInit(false);

        localizedKeynames = new Translator("keynames");

        keybindings = new KeyBindings();
        keybindings.loadFrom(globals.loadConfig("binds").getSubNode("binds"));

        mGameLoader = new GameLoader(globals.anyConfig.getSubNode("newgame"), mGui);
        mGameLoader.onFinish = &gameLoaded;

        //load a new game
        mLoadScreen.startLoad(mGameLoader);
    }

    void gameLoaded(Loader sender) {
        thegame = mGameLoader.thegame;
        thegame.gameTime.resetTime;
        resetTime();
        clientengine = mGameLoader.clientengine;
        metascene = mGameLoader.metascene;
    }

    private void initConsole() {
        globals.cmdLine = new CommandLine(mGuiConsole.console);

        globals.setDefaultOutput(mGuiConsole.console);

        globals.cmdLine.registerCommand("gc", &testGC, "timed GC run");
        globals.cmdLine.registerCommand("gcstats", &testGCstats, "GC stats");
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
        globals.cmdLine.registerCommand("raisewater", &cmdRaiseWater, "increase waterline");

        globals.cmdLine.registerCommand("editor", &cmdLevelEdit, "hm");

        globals.cmdLine.registerCommand("wind", &cmdSetWind, "Change wind speed");
        globals.cmdLine.registerCommand("stop", &cmdStop, "stop editor/game");

        globals.cmdLine.registerCommand("slow", &cmdSlow, "todo");

        globals.cmdLine.registerCommand("framerate", &cmdFramerate, "set fixed framerate");
        globals.cmdLine.registerCommand("cameradisable", &cmdCameraDisable, "disable game camera");
        globals.cmdLine.registerCommand("detail", &cmdDetail, "switch detail level");
    }

    private void cmdDetail(CommandLine cmd) {
        if (!clientengine)
            return;
        clientengine.detailLevel = clientengine.detailLevel + 1;
        cmd.console.writefln("set detailLevel to %s", clientengine.detailLevel);
    }

    private void cmdFramerate(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        int rate = 0;
        if (sargs.length < 1)
            return;
        try {
            rate = conv.toInt(sargs[0]);
        } catch (conv.ConvError) {
            return;
        }
        globals.framework.fixedFramerate = rate;
    }

    private void cmdCameraDisable(CommandLine) {
        if (mGameView.view)
            mGameView.view.setCameraFocus(null);
    }

    private void cmdStop(CommandLine) {
        if (mOnStopGui)
            mOnStopGui();
        //screen.setFocus(null);
        //sceneview.clientscene = null;
        mOnStopGui = null;
    }

    private void cmdSetWind(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        if (sargs.length < 1)
            return;
        thegame.windSpeed = conv.toFloat(sargs[0]);
    }

    private void killEditor() {
        if (editor) {
            editor.kill();
            editor = null;
        }
    }

    private void cmdLevelEdit(CommandLine cmd) {
        //closeGame();
        editor = new LevelEditor();
        mGui.add(editor.render, GUIZOrder.Gui);
        //clearly sucks, find a better way
        mGui.setFocus(editor.render);

        mOnStopGui = &killEditor;
    }

    private void cmdRaiseWater(CommandLine cmd) {
        char[][] sargs = cmd.parseArgs();
        int add = 0;
        if (sargs.length < 1)
            return;
        try {
            add = conv.toInt(sargs[0]);
        } catch (conv.ConvError) {
            return;
        }
        thegame.raiseWater(add);
    }

    private void cmdPhys(CommandLine) {
        //oops?
        //auto obj = new TestAnimatedGameObject(thegame);
        //obj.setPos(thegame.tmp);
        assert(false);
    }

    private void cmdExpl(CommandLine) {
        //auto obj = new BananaBomb(thegame);
        //obj.setPos(toVector2f(thegame.tmp));
        assert(false);
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: %s", globals.framework.screen.size);
        mGui.size = globals.framework.screen.size;
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
        try {
            globals.framework.setVideoMode(args[0], args[1], args[2], mIsFS);
        } catch (Exception e) {
            //failed to set video mode, try again in windowed mode
            mIsFS = false;
            globals.framework.setVideoMode(args[0], args[1], args[2], mIsFS);
        }
    }

    private bool mIsFS;
    private void cmdFS(CommandLine cmd) {
        try {
            globals.framework.setVideoMode(globals.framework.screen.size.x1,
                globals.framework.screen.size.x2, globals.framework.bitDepth,
                !mIsFS);
        } catch (Exception e) {
            //fullscreen switch failed
            mIsFS = true;
            globals.framework.setVideoMode(globals.framework.screen.size.x1,
                globals.framework.screen.size.x2, globals.framework.bitDepth,
                !mIsFS);
        }
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

    /+
    private void cmdLoadAnim(CommandLine cmd) {
        auto a = new Animation(mWormsAnim.getSubNode(cmd.parseArgs[0]));
        std.stdio.writefln("Loaded ",cmd.parseArgs[0]);
        mWormsAnimator.setAnimation(a);
    }
    +/

    private void showConsole(CommandLine) {
        mGuiConsole.console.toggle();
        //xxx focus hack
        if (mGuiConsole.console.visible)
            mGui.setFocus(mGuiConsole);
        else
            mGui.setFocus(mGameView);
    }

    private void killShortcut(CommandLine) {
        globals.framework.terminate();
    }

    private void testGC(CommandLine) {
        auto counter = new perf.PerformanceCounter();
        gc.GCStats s1, s2;
        gc.getStats(s1);
        counter.start();
        gc.fullCollect();
        counter.stop();
        gc.getStats(s2);
        Time t;
        t.musecs = counter.microseconds;
        globals.log("GC fullcollect: %s, free'd %s KB", t,
            ((s1.usedsize - s2.usedsize) + 512) / 1024);
    }
    private void testGCstats(CommandLine cmd) {
        auto w = cmd.console;
        gc.GCStats s;
        gc.getStats(s);
        w.writefln("GC stats:");
        w.writefln("poolsize = %s KB", s.poolsize/1024);
        w.writefln("usedsize = %s KB", s.usedsize/1024);
        w.writefln("freeblocks = %s", s.freeblocks);
        w.writefln("freelistsize = %s KB", s.freelistsize/1024);
        w.writefln("pageblocks = %s", s.pageblocks);
    }

    private void cmdGenerateLevel(CommandLine cmd) {
        //char[] arg0 = cmd?cmd.getArgString():"";
        mLoadScreen.startLoad(mGameLoader);
    }

    private void cmdPause(CommandLine) {
        thegame.gameTime.paused = !thegame.gameTime.paused;
        clientengine.engineTime.paused = thegame.gameTime.paused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
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
        float g = setgame ? val : thegame.gameTime.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        cmd.console.writefln("set slowdown: game=%s animations=%s", g, a);
        thegame.gameTime.slowDown = g;
        clientengine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void initTimes() {
        resetTime();
    }

    void resetTime() {
        globals.gameTimeAnimations.resetTime();
    }

    private void onFrame(Canvas c) {
        if (mGameLoader.fullyLoaded) {
            globals.gameTimeAnimations.update();

            if (thegame) {
                thegame.doFrame();
            }

            if (clientengine) {
                clientengine.doFrame();
            }
        }

        mGui.doFrame(timeCurrentTime());

        mGui.draw(c);

        if (!mLoadScreen.loading)
            //xxx can't deactivate this from delegate because it would crash
            //the list
            mLoadScreen.active = false;
    }

    private void onKeyPress(KeyInfo infos) {
        mGui.putOnKeyPress(infos);
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
        char[] bind = keybindings.findBinding(infos.code,
            globals.framework.getModifierSet());
        if (bind) {
            if (mShowKeyDebug) {
                globals.log("Binding '%s'", bind);
            }
            globals.cmdLine.execute(bind, false);
            return false;
        }
        mGui.putOnKeyDown(infos);
        return true;
    }

    private bool onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", globals.framework.keyinfoToString(infos));
        }
        mGui.putOnKeyUp(infos);
        return true;
    }

    private void onMouseMove(MouseInfo mouse) {
        //globals.log("%s", mouse.pos);
        mGui.putOnMouseMove(mouse);
    }
}
