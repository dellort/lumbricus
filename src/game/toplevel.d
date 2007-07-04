module game.toplevel;

import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import framework.framework;
import framework.commandline;
import framework.i18n;
import framework.timesource;
import gui.gui;
import gui.guiobject;
import gui.leveledit;
import gui.fps;
import gui.guiframe;
import gui.gameframe;
import gui.console;
import game.common;
import utils.time;
import utils.configfile;
import utils.log;
import utils.output;
import utils.mylist;
import utils.mybox;
import perf = std.perf;
import gc = std.gc;

//this contains the mainframe
class TopLevel {
private:
    KeyBindings keybindings;

    GuiMain mGui;
    GuiConsole mGuiConsole;

    GuiFrame mCurrentFrame;
    GameFrame mGameFrame;

    //xxx move this to where-ever
    Translator localizedKeynames;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    public this() {
        initTimes();

        mGui = new GuiMain(globals.framework.screen.size);

        mGui.add(new GuiFps(), GUIZOrder.FPS);

        mGuiConsole = new GuiConsole();
        mGui.add(mGuiConsole, GUIZOrder.Console);

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

        //load a new game
        newGame();
    }

    private void initConsole() {
        globals.cmdLine = new CommandLine(mGuiConsole.console);

        globals.setDefaultOutput(mGuiConsole.console);

        globals.cmdLine.registerCommand("gc", &testGC, "timed GC run");
        globals.cmdLine.registerCommand("gcstats", &testGCstats, "GC stats");
        globals.cmdLine.registerCommand("quit", &killShortcut, "kill it");
        globals.cmdLine.registerCommand("toggle", &showConsole,
            "toggle this console");
        //globals.cmdLine.registerCommand("log", &cmdShowLog,
          //  "List and modify log-targets");
        globals.cmdLine.registerCommand("level", &cmdGenerateLevel,
            "Generate new level");
        globals.cmdLine.registerCommand("bind", &cmdBind,
            "display/edit key bindings", [
                "text?:add/kill",
                "text?:name",
                "text...:bind to"
            ]);
        globals.cmdLine.registerCommand("nameit", &cmdNameit, "name a key");
        globals.cmdLine.registerCommand("video", &cmdVideo, "set video", [
            "int:width",
            "int:height",
            "int?=0:depth (bits)"]);
        globals.cmdLine.registerCommand("fullscreen", &cmdFS, "toggle fs");
        globals.cmdLine.registerCommand("pause", &cmdPause, "pause");
        globals.cmdLine.registerCommand("stop", &cmdStop, "stop editor/game");
        globals.cmdLine.registerCommand("editor", &cmdLevelEdit, "hm");
        globals.cmdLine.registerCommand("slow", &cmdSlow, "set slowdown", [
            "float:slow down",
            "text?:ani or game"]);
        globals.cmdLine.registerCommand("framerate", &cmdFramerate,
            "set fixed framerate");
    }

    private void cmdFramerate(MyBox[] args, Output write) {
        globals.framework.fixedFramerate = args[0].unbox!(int)();
    }

    void killFrame() {
        if (mCurrentFrame) {
            mCurrentFrame.kill();
            mCurrentFrame = null;
            mGameFrame = null;
        }
    }

    private void cmdStop(MyBox[] args, Output write) {
        killFrame();
    }

    private void cmdLevelEdit(MyBox[] args, Output write) {
        killFrame();
        mCurrentFrame = new LevelEditor(mGui);
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: %s", globals.framework.screen.size);
        mGui.size = globals.framework.screen.size;
    }

    private void cmdVideo(MyBox[] args, Output write) {
        int a = args[0].unbox!(int);
        int b = args[1].unbox!(int);
        int c = args[2].unbox!(int);
        try {
            globals.framework.setVideoMode(a, b, c, mIsFS);
        } catch (Exception e) {
            //failed to set video mode, try again in windowed mode
            mIsFS = false;
            globals.framework.setVideoMode(a, b, c, mIsFS);
        }
    }

    private bool mIsFS;
    private void cmdFS(MyBox[] args, Output write) {
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
    private void cmdBind(MyBox[] args, Output write) {
        switch (args[0].unbox!(char[])()) {
            case "add":
                keybindings.addBinding(args[1].unbox!(char[])(),
                    args[2].unbox!(char[])());
                return;
            case "kill":
                //remove all bindings
                keybindings.removeBinding(args[1].unbox!(char[])());
                return;
            default:
        }
        //else, list all bindings
        write.writefln("Bindings:");
        keybindings.enumBindings(
            (char[] bind, Keycode code, ModifierSet mods) {
                write.writefln("    %s='%s' ('%s')", bind,
                    keybindings.unparseBindString(code, mods),
                    translateKeyshortcut(code, mods));
            }
        );
    }

    private void cmdNameit(MyBox[] args, Output write) {
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

/*    private void cmdShowLog(CommandLine cmd) {

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
    }*/

    private void showConsole(MyBox[], Output) {
        mGuiConsole.toggle();
    }

    private void killShortcut(MyBox[], Output) {
        globals.framework.terminate();
    }

    private void testGC(MyBox[] args, Output write) {
        auto counter = new perf.PerformanceCounter();
        gc.GCStats s1, s2;
        gc.getStats(s1);
        counter.start();
        gc.fullCollect();
        counter.stop();
        gc.getStats(s2);
        Time t;
        t.musecs = counter.microseconds;
        write.writefln("GC fullcollect: %s, free'd %s KB", t,
            ((s1.usedsize - s2.usedsize) + 512) / 1024);
    }
    private void testGCstats(MyBox[] args, Output write) {
        auto w = write;
        gc.GCStats s;
        gc.getStats(s);
        w.writefln("GC stats:");
        w.writefln("poolsize = %s KB", s.poolsize/1024);
        w.writefln("usedsize = %s KB", s.usedsize/1024);
        w.writefln("freeblocks = %s", s.freeblocks);
        w.writefln("freelistsize = %s KB", s.freelistsize/1024);
        w.writefln("pageblocks = %s", s.pageblocks);
    }

    private void cmdGenerateLevel(MyBox[] args, Output write) {
        newGame();
    }

    private void newGame() {
        killFrame();
        mCurrentFrame = mGameFrame = new GameFrame(mGui);
    }

    private void cmdPause(MyBox[], Output) {
        if (mGameFrame)
            mGameFrame.gamePaused = !mGameFrame.gamePaused;
        globals.gameTimeAnimations.paused = !globals.gameTimeAnimations.paused;
    }

    //slow time <whatever>
    //whatever can be "game", "ani" or left out
    private void cmdSlow(MyBox[] args, Output write) {
        bool setgame, setani;
        switch (args[1].unbox!(char[])) {
            case "game": setgame = true; break;
            case "ani": setani = true; break;
            default:
                setgame = setani = true;
        }
        float val = args[0].unbox!(float);
        float g = setgame ? val : mGameFrame.thegame.gameTime.slowDown;
        float a = setani ? val : globals.gameTimeAnimations.slowDown;
        write.writefln("set slowdown: game=%s animations=%s", g, a);
        mGameFrame.thegame.gameTime.slowDown = g;
        mGameFrame.clientengine.engineTime.slowDown = g;
        globals.gameTimeAnimations.slowDown = a;
    }

    private void initTimes() {
        resetTime();
    }

    void resetTime() {
        globals.gameTimeAnimations.resetTime();
    }

    private void onFrame(Canvas c) {
        if (mCurrentFrame) {
            mCurrentFrame.onFrame(c);
        }

        mGui.doFrame(timeCurrentTime());

        mGui.draw(c);
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
