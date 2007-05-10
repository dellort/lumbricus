module game.toplevel;
import game.common;
import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import game.scene;
import game.animation;
import framework.framework;
import framework.commandline;
import utils.time;
import utils.configfile;
import utils.log;
import perf = std.perf;
import gc = std.gc;

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

    bool mShowKeyDebug;

    this() {
        screen = new Screen(globals.framework.screen.size);

        console = new Console(globals.framework.getFont("console"));
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

        auto consrender = new CallbackSceneObject();
        consrender.scene = guiscene;
        consrender.zorder = GUIZOrder.Console;
        consrender.active = true;
        consrender.onDraw = &renderConsole;

        //kidnap framework singleton...
        globals.framework.onFrame = &onFrame;
        globals.framework.onKeyPress = &onKeyPress;
        globals.framework.onKeyDown = &onKeyDown;
        globals.framework.onKeyUp = &onKeyUp;

        //xxx test
        ConfigNode node = globals.loadConfig("animations");
        auto sub = node.getSubNode("testani1");
        Animation ani = new Animation(sub);
        Animator ar = new Animator();
        ar.scene = gamescene;
        ar.zorder = 2;
        ar.active = true;
        ar.setAnimation(ani, true);

        globals.framework.registerShortcut(Keycode.G, [Modifier.Control],
            &testGC);
        globals.framework.registerShortcut(Keycode.ESCAPE, null, &killShortcut);
        globals.framework.registerShortcut(Keycode.F1, null, &showConsole);
    }

    private void showConsole(KeyInfo infos) {
        console.toggle();
    }

    private void killShortcut(KeyInfo infos) {
        globals.framework.terminate();
    }

    private void testGC(KeyInfo infos) {
        auto counter = new perf.PerformanceCounter();
        counter.start();
        gc.fullCollect();
        counter.stop();
        //hrhrhr
        Time t;
        t.musecs = counter.microseconds;
        globals.log("GC fullcollect: %s", t);
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

    private void onKeyDown(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("down: %s", globals.framework.keyinfoToString(infos));
        }
    }

    private void onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", globals.framework.keyinfoToString(infos));
        }
    }

    private void renderConsole(Canvas canvas) {
        console.frame(canvas);
    }
}
