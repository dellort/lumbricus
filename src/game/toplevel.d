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
import utils.time;
import utils.configfile;
import utils.log;
import utils.output;
import perf = std.perf;
import gc = std.gc;
import level = level.generator;

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

    bool mShowKeyDebug = true;

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
    }

    private void cmdShowLog(CommandLine cmd, uint id) {

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
            cmd.console.writefln("  %s", log.category);
        }
    }

    private void showConsole(CommandLine, uint) {
        console.toggle();
    }

    private void killShortcut(CommandLine, uint) {
        globals.framework.terminate();
    }

    private void testGC(CommandLine, uint) {
        auto counter = new perf.PerformanceCounter();
        counter.start();
        gc.fullCollect();
        counter.stop();
        //hrhrhr
        Time t;
        t.msecs = counter.microseconds;
        globals.log("GC fullcollect: %s", t);
    }

    private void cmdGenerateLevel(CommandLine cmd, uint id) {
        if (thegame) {
            thegame.kill();
            thegame = null;
        }
        auto x = new level.LevelGenerator();
        x.config = globals.loadConfig("levelgen").getSubNode("levelgen");
        auto level = x.generateRandom(2000, 600, "");
        thegame = new GameController(gamescene, level);
    }

    private void onFrame() {
        globals.gameTimeAnimations = globals.framework.getCurrentTime();
        globals.gameTime = globals.gameTimeAnimations;

        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);

        Canvas canvas = globals.framework.screen.startDraw();
        screen.draw(canvas);
        globals.framework.screen.endDraw();
    }

    private void onKeyPress(KeyInfo infos) {
        if (console.visible && globals.cmdLine.keyPress(infos))
            return;
    }

    private Vector2i mMouseStart;

    private void onKeyDown(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("down: %s", globals.framework.keyinfoToString(infos));
        }
        if (infos.code == Keycode.MOUSE_LEFT) {
            mMouseStart = gameview.clientoffset - globals.framework.mousePos;
        }
        char[] bind = keybindings.findBinding(infos.code,
            globals.framework.getAllModifiers());
        if (bind) {
            globals.log("Binding '%s'", bind);
            globals.cmdLine.execute(bind);
        }
    }

    private void onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", globals.framework.keyinfoToString(infos));
        }
    }

    private void onMouseMove(MouseInfo mouse) {
        //globals.log("%s", mouse.pos);
        if (globals.framework.getKeyState(Keycode.MOUSE_LEFT)) {
            gameview.clientoffset = mMouseStart + mouse.pos;
        }
    }

    private void renderConsole(Canvas canvas) {
        console.frame(canvas);
    }
}
