module common.toplevel;

import std.string;
import framework.font;
import framework.console;
import framework.keysyms;
import framework.framework;
import framework.commandline;
import framework.i18n;
import framework.timesource;
import gui.gui;
import gui.widget;
import gui.fps;
import gui.container;
import gui.console;
import common.common;
import common.task;
import utils.time;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.output;
import utils.mylist;
import utils.mybox;
import perf = std.perf;
import gc = std.gc;

//ZOrders!
//only for the stuff managed by TopLevel
//note that Widget.zorder can take any value
enum GUIZOrder : int {
    Gui,
    Console,
    FPS,
}

//this contains the mainframe
class TopLevel {
private:
    KeyBindings keybindings;

    GuiMain mGui;
    GuiConsole mGuiConsole;

    TaskManager taskManager;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    public this() {
        auto framework = getFramework();

        mGui = new GuiMain(framework.screen.size);

        auto fps = new GuiFps();
        fps.zorder = GUIZOrder.FPS;
        mGui.mainFrame.add(fps);

        mGuiConsole = new GuiConsole();
        mGuiConsole.zorder = GUIZOrder.Console;
        mGui.mainFrame.add(mGuiConsole);

        initConsole();

        taskManager = new TaskManager(mGui);

        framework.onFrame = &onFrame;
        framework.onKeyPress = &onKeyPress;
        framework.onKeyDown = &onKeyDown;
        framework.onKeyUp = &onKeyUp;
        framework.onMouseMove = &onMouseMove;
        framework.onVideoInit = &onVideoInit;

        //do it yourself... (initial event)
        onVideoInit(false);

        keybindings = new KeyBindings();
        keybindings.loadFrom(globals.loadConfig("binds").getSubNode("binds"));

        //load a new game
        //newGame();

        char[] start = globals.anyConfig["start"];
        if (start.length > 0) {
            //create an initial task
            //don't need the instance, it'll be registered in the TaskManager
            try {
                TaskFactory.instantiate(start, taskManager);
            } catch (ClassNotFoundException e) {
                mGuiConsole.console.writefln("BIG FAT WARNING: %s", e);
            }
        }
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
        globals.cmdLine.registerCommand("framerate", &cmdFramerate,
            "set fixed framerate");

        globals.cmdLine.registerCommand("ps", &cmdPS, "list tasks");
        globals.cmdLine.registerCommand("spawn", &cmdSpawn, "create task",
            ["text:task name (get avilable ones with 'help_spawn')"]);
        globals.cmdLine.registerCommand("kill", &cmdKill, "kill a task by ID",
            ["int:task id"]);
        globals.cmdLine.registerCommand("help_spawn", &cmdSpawnHelp,
            "list tasks registered at task factory (use for spawn)");
        globals.cmdLine.registerCommand("grab", &cmdGrab, "-");
    }

    private void cmdGrab(MyBox[] args, Output write) {
        getFramework.grabInput = !getFramework.grabInput;
    }

    private void cmdPS(MyBox[] args, Output write) {
        write.writefln("ID / toString()");
        foreach (Task t; taskManager.taskList) {
            write.writefln("  %2d / %s", t.taskID, t);
        }
    }

    private void cmdSpawn(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[])();
        Task n;
        try {
            n = TaskFactory.instantiate(name, taskManager);
        } catch (ClassNotFoundException e) {
            //xxx: and what if the Task was found, but the Task constructor
            //     throws this exception??
            write.writefln("not found (%s)", e);
            return;
        }
        write.writefln("spawn: instantiated %s -> %s", name, n);
    }

    private void cmdKill(MyBox[] args, Output write) {
        int id = args[0].unbox!(int)();
        foreach (Task t; taskManager.taskList) {
            if (id == t.taskID) {
                write.writefln("killing %s", t);
                t.kill();
                write.writefln("kill: done");
                return;
            }
        }
        write.writefln("Task %d not found.", id);
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered task classes: %s", TaskFactory.classes);
    }

    private void cmdFramerate(MyBox[] args, Output write) {
        globals.framework.fixedFramerate = args[0].unbox!(int)();
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
                    globals.translateKeyshortcut(code, mods));
            }
        );
    }

    private void cmdNameit(MyBox[] args, Output write) {
        mKeyNameIt = true;
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
        getFramework().terminate();
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

    private void onFrame(Canvas c) {
        //xxx move?
        globals.gameTimeAnimations.update();

        taskManager.doFrame();

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
                globals.translateKeyshortcut(infos.code, mods));
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
