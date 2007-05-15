module game.toplevel;
import game.common;
import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import game.scene;
import game.animation;
import game.game;
import framework.framework;
import framework.commandline;
import framework.i18n;
import utils.time;
import utils.configfile;
import utils.log;
import utils.output;
import perf = std.perf;
import gc = std.gc;
import level = level.generator;
import str = std.string;
import conv = std.conv;
import game.physic;
import game.gobject;

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
    Scene gamescene;
    SceneView gameview;
    Console console;
    KeyBindings keybindings;
    GameController thegame;
    Time gameStartTime;
    private Time mPauseStarted; //absolute time of pause start
    private Time mPausedTime; //summed amount of time paused
    private bool mPauseMode;
    //xxx move this to where-ever
    ConfigNode localizedKeyfile;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    this() {
        screen = new Screen(globals.framework.screen.size);

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

        //xxx: make this fail-safe
        localizedKeyfile = globals.loadConfig(
            globals.locales.getStringValue("keyname_conf", "keynames"));

        guiscene = screen.rootscene;
        fpsDisplay = new FontLabel(globals.framework.getFont("fpsfont"));
        fpsDisplay.scene = guiscene;
        fpsDisplay.zorder = GUIZOrder.FPS;
        fpsDisplay.active = true;

        gamescene = new Scene();
        gameview = new SceneView(gamescene);
        gameview.scene = guiscene; //container!
        gameview.zorder = GUIZOrder.Game;
        gameview.active = true;
        //gameview is simply the window that shows the level
        gameview.pos = Vector2i(10, 10);
        gameview.thesize = guiscene.thesize - Vector2i(10, 10)*2;

        auto consrender = new CallbackSceneObject();
        consrender.scene = guiscene;
        consrender.zorder = GUIZOrder.Console;
        consrender.active = true;
        consrender.onDraw = &renderConsole;

        globals.framework.onFrame = &onFrame;
        globals.framework.onKeyPress = &onKeyPress;
        globals.framework.onKeyDown = &onKeyDown;
        globals.framework.onKeyUp = &onKeyUp;
        globals.framework.onMouseMove = &onMouseMove;
        globals.framework.onVideoInit = &onVideoInit;

        //do it yourself... (initial event)
        onVideoInit(false);

        //xxx test
        ConfigNode node = globals.loadConfig("animations");
        auto sub = node.getSubNode("testani1");
        Animation ani = new Animation(sub);
        Animator ar = new Animator();
        ar.scene = gamescene;
        ar.zorder = 2;
        ar.active = true;
        ar.setAnimation(ani, true);

        keybindings = new KeyBindings();
        keybindings.loadFrom(globals.loadConfig("binds").getSubNode("binds"));

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
        globals.cmdLine.registerCommand("scroll", &cmdScroll, "enter scroll mode");
        globals.cmdLine.registerCommand("phys", &cmdPhys, "test123");
        globals.cmdLine.registerCommand("pause", &cmdPause, "pause");
    }

    private void cmdPhys(CommandLine) {
        GameObject obj = new GameObject(thegame);
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: %s", globals.framework.screen.size);
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
            (char[] bind, Keycode code, Modifier[] mods) {
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
    char[] translateKeyshortcut(Keycode code, Modifier[] mods) {
        if (!localizedKeyfile)
            return "?";
        char[] res = localizedKeyfile.getStringValue(
            globals.framework.translateKeycodeToKeyID(code), "?");
        foreach (Modifier mod; mods) {
            res = localizedKeyfile.getStringValue(
                globals.framework.modifierToString(mod), "?") ~ "+" ~ res;
        }
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

    private bool mScrolling;

    private void cmdScroll(CommandLine cmd) {
        if (mScrolling) {
            //globals.framework.grabInput = false;
            globals.framework.cursorVisible = true;
            globals.framework.unlockMouse();
        } else {
            //globals.framework.grabInput = true;
            globals.framework.cursorVisible = false;
            globals.framework.lockMouse();
        }
        mScrolling = !mScrolling;
    }

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
        if (thegame) {
            thegame.kill();
            thegame = null;
        }
        auto x = new level.LevelGenerator();
        x.config = globals.loadConfig("levelgen").getSubNode("levelgen");
        auto level = x.generateRandom(1920, 696, "");
        thegame = new GameController(gamescene, level);
        gameStartTime = globals.gameTime;
    }

    private void cmdPause(CommandLine) {
        if (mPauseMode) {
            mPausedTime += globals.gameTime - mPauseStarted;
        } else {
            mPauseStarted = globals.gameTime;
        }
        mPauseMode = !mPauseMode;
    }

    private void onFrame(Canvas c) {
        globals.gameTimeAnimations = globals.framework.getCurrentTime();
        globals.gameTime = globals.gameTimeAnimations;

        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);

        if (thegame && !mPauseMode) {
            thegame.doFrame(globals.gameTime - gameStartTime - mPausedTime);
        }

        screen.draw(c);
    }

    private void onKeyPress(KeyInfo infos) {
        if (console.visible && globals.cmdLine.keyPress(infos))
            return;
    }

    private Vector2i mMouseStart;

    private bool onKeyDown(KeyInfo infos) {
        if (mKeyNameIt) {
            //modifiers are also keys, ignore them
            if (globals.framework.isModifierKey(infos.code)) {
                return false;
            }
            auto mods = globals.framework.getAllModifiers();
            globals.cmdLine.console.writefln("Key: '%s' '%s'",
                keybindings.unparseBindString(infos.code, mods),
                translateKeyshortcut(infos.code, mods));
            mKeyNameIt = false;
            return false;
        }
        if (mShowKeyDebug) {
            globals.log("down: %s", globals.framework.keyinfoToString(infos));
        }
        if (infos.code == Keycode.MOUSE_LEFT) {
            mMouseStart = gameview.clientoffset - globals.framework.mousePos;
        }
        char[] bind = keybindings.findBinding(infos.code,
            globals.framework.getAllModifiers());
        if (bind) {
            if (mShowKeyDebug) {
                globals.log("Binding '%s'", bind);
            }
            globals.cmdLine.execute(bind);
            return false;
        }
        return true;
    }

    private bool onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", globals.framework.keyinfoToString(infos));
        }
        return true;
    }

    private void onMouseMove(MouseInfo mouse) {
        //globals.log("%s", mouse.pos);
        if (globals.framework.getKeyState(Keycode.MOUSE_LEFT)) {
            gameview.clientoffset = mMouseStart + mouse.pos;
        }
        if (mScrolling) {
            gameview.clientoffset = gameview.clientoffset - mouse.rel;
        }
    }

    private void renderConsole(Canvas canvas) {
        console.frame(canvas);
    }
}
