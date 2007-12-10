module common.toplevel;

import std.string;
import framework.font;
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
import gui.wm;
import common.common;
import framework.resources;
import common.task;
import utils.time;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.output;
import utils.misc;
import utils.mylist;
import utils.mybox;
import utils.perf;
import gc = std.gc;
import std.stream : File, FileMode;

//ZOrders!
//only for the stuff managed by TopLevel
//note that Widget.zorder can take any value
enum GUIZOrder : int {
    Gui,
    Something, //hack for the fade-"overlay"
    Console,
    FPS,
}

TopLevel gTopLevel;

//this contains the mainframe
class TopLevel {
private:
    KeyBindings keybindings;

    GuiMain mGui;
    GuiConsole mGuiConsole;

    TaskManager taskManager;

    bool mShowKeyDebug = false;
    bool mKeyNameIt = false;

    PerfTimer mTaskTime, mGuiDrawTime, mGuiFrameTime;
    PerfTimer mFrameTime;

    Time[PerfTimer] mLastTimerValues;

    const cTimerStatsUpdateTimeMs = 1000;

    Time mLastTimerStatsUpdate;
    int mLastTimerStatsFrames;
    bool mLastTimerInitialized;
    int mTimerStatsGeneration;

    void onFrameEnd() {
        mFrameTime.stop();

        Time cur = timeCurrentTime();
        if (!mLastTimerInitialized) {
            mLastTimerStatsUpdate = cur;
            mLastTimerStatsFrames = 1;
            mLastTimerInitialized = true;
        }
        if (cur - mLastTimerStatsUpdate >= timeMsecs(cTimerStatsUpdateTimeMs)) {
            mTimerStatsGeneration++;
            mLastTimerStatsUpdate = cur;
            int div = mLastTimerStatsFrames;
            mLastTimerStatsFrames = 0;
            foreach (PerfTimer cnt; globals.timers) {
                assert(!cnt.active, "timers must be off across frames");
                auto t = cnt.time();
                mLastTimerValues[cnt] = t / div;
                cnt.reset();
            }
        }
        mLastTimerStatsFrames++;

        mFrameTime.start();
    }

    void cmdShowTimers(MyBox[] args, Output write) {
        write.writefln("Timers:");
        listTimers((char[] a, char[] b) {write.writefln("   %s: %s", a, b);});
    }

    void listTimers(void delegate(char[] name, char[] value) cb) {
        foreach (char[] name, PerfTimer cnt; globals.timers) {
            Time* pt = cnt in mLastTimerValues;
            char[] s = "<unknown>";
            if (pt)
                s = format("%s", *pt);
            cb(name, s);
        }
    }

    int timerCount() {
        return globals.timers.length;
    }

    public this() {
        assert(!gTopLevel, "singleton");
        gTopLevel = this;

        auto framework = gFramework;

        mTaskTime = globals.newTimer("tasks");
        mGuiDrawTime = globals.newTimer("gui_draw");
        mGuiFrameTime = globals.newTimer("gui_frame");
        mFrameTime = globals.newTimer("frame_time");

        mGui = new GuiMain(framework.screenSize);

        auto fps = new GuiFps();
        fps.zorder = GUIZOrder.FPS;
        mGui.mainFrame.add(fps);

        mGuiConsole = new GuiConsole(false);
        mGuiConsole.zorder = GUIZOrder.Console;
        mGui.mainFrame.add(mGuiConsole);

        initConsole();

        taskManager = new TaskManager();

        gWindowManager = new WindowManager(mGui);

        framework.onUpdate = &onUpdate;
        framework.onFrame = &onFrame;
        framework.onKeyPress = &onKeyPress;
        framework.onKeyDown = &onKeyDown;
        framework.onKeyUp = &onKeyUp;
        framework.onMouseMove = &onMouseMove;
        framework.onVideoInit = &onVideoInit;
        framework.onFrameEnd = &onFrameEnd;

        //fugly!
        //framework.clearColor = Color(0,0,1);

        //do it yourself... (initial event)
        onVideoInit(false);

        keybindings = new KeyBindings();
        keybindings.loadFrom(gFramework.loadConfig("binds").getSubNode("binds"));

        //load a new game
        //newGame();

        /+
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
        +/

        auto autoexec = globals.anyConfig.getSubNode("autoexec");
        foreach (char[] name, char[] value; autoexec) {
            globals.cmdLine.execute(value);
        }

        if (taskManager.taskList.length == 0) {
            mGuiConsole.output.writefln("Nothing to run, do what you want");
            mGuiConsole.consoleVisible = true;
        }
    }

    private void initConsole() {
        globals.cmdLine = mGuiConsole.cmdline;

        globals.setDefaultOutput(mGuiConsole.output);

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
            "set fixed framerate", ["int:framerate"]);

        globals.cmdLine.registerCommand("ps", &cmdPS, "list tasks");
        globals.cmdLine.registerCommand("spawn", &cmdSpawn, "create task",
            ["text:task name (get avilable ones with 'help_spawn')"]);
        globals.cmdLine.registerCommand("kill", &cmdKill, "kill a task by ID",
            ["int:task id"]);
        globals.cmdLine.registerCommand("terminate", &cmdTerminate,
            "terminate a task by ID", ["int:task id"]);
        globals.cmdLine.registerCommand("help_spawn", &cmdSpawnHelp,
            "list tasks registered at task factory (use for spawn)");
        globals.cmdLine.registerCommand("grab", &cmdGrab, "-", ["bool:onoff"]);

        globals.cmdLine.registerCommand("res_unload", &cmdResUnload,
            "Unload unused resources; currently can crash!", []);
        globals.cmdLine.registerCommand("res_list", &cmdResList,
            "List all resources", []);

        globals.cmdLine.registerCommand("release_caches", &cmdReleaseCaches,
            "Release caches (temporary data)", []);
        /+
        globals.cmdLine.registerCommand("caching", &cmdSetCaching,
            "Set if texture caching should be done", ["bool:if enabled"]);
        +/

        globals.cmdLine.registerCommand("times", &cmdShowTimers,
            "List timers", []);

        /+
        globals.cmdLine.registerCommand("fw_info", &cmdInfoString,
            "Query a info string from the framework, with no argument: list "
            "all info string names", ["text?:Name of the string or 'all'"]);
        globals.cmdLine.registerCommand("fw_debug", &cmdSetFWDebug,
            "Switch some debugging stuff in Framework on/off", ["bool:Value"]);
        +/
        globals.cmdLine.registerCommand("fw_driver", &cmdSetFWDriver,
            "Set framework driver", ["bool:Caching", "bool:mark alpha"]);

        //more like a test
        globals.cmdLine.registerCommand("widget_tree", &cmdWidgetTree, "-");
    }

    private void cmdSetFWDriver(MyBox[] args, Output write) {
        ConfigNode n = new ConfigNode();
        n["driver"] = "sdl";
        n.setBoolValue("enable_caching", args[0].unbox!(bool));
        n.setBoolValue("mark_alpha", args[1].unbox!(bool));
        gFramework.scheduleDriverReload(Framework.DriverReload(n));
    }

    /+
    private void cmdSetFWDebug(MyBox[] args, Output write) {
        gFramework.setDebug(args[0].unbox!(bool));
    }
    +/

    /+
    private void cmdInfoString(MyBox[] args, Output write) {
        auto names = gFramework.getInfoStringNames();
        if (args[0].empty) {
            write.writefln("Strings:");
            foreach (char[] name, InfoString id; names) {
                write.writefln("  - %s", name);
            }
            return;
        }

        void show(InfoString s) {
            write.writef(gFramework.getInfoString(s));
        }

        char[] s = args[0].unbox!(char[]);
        if (s == "all") {
            foreach (char[] name, InfoString id; names) {
                write.writefln("%s:", name);
                show(id);
            }
        } else {
            if (s in names) {
                show(names[s]);
            } else {
                write.writefln("string '%s' not found", s);
            }
        }
    }
    +/

    private void cmdWidgetTree(MyBox[] args, Output write) {
        int maxdepth;
        int count;

        void showWidget(Widget w, int depth) {
            maxdepth = depth > maxdepth ? depth : maxdepth;
            count++;
            char[] pad; pad.length = depth*2; pad[] = ' ';
            Container cw = cast(Container)w;
            write.writefln("%s%s%s", pad, w, cw ? " [container]" : "");
            if (cw) {
                cw.enumChildren((Widget child) {
                    showWidget(child, depth + 1);
                });
            }
        }

        write.writefln("Widget tree:");
        showWidget(mGui.mainFrame, 0);
        write.writefln("maxdepth = %d, count = %d", maxdepth, count);
    }

    private void cmdReleaseCaches(MyBox[] args, Output write) {
        int released = gFramework.releaseCaches();
        write.writefln("released %s memory consuming house shoes", released);
    }

    /+
    private void cmdSetCaching(MyBox[] args, Output write) {
        gFramework.setAllowCaching(args[0].unbox!(bool));
    }
    +/

    private void cmdResList(MyBox[] args, Output write) {
        write.writefln("dumping to res.txt");
        auto file = new File("res.txt", FileMode.OutNew);
        write = new StreamOutput(file);
        int count;
        gFramework.resources.enumResources(
            (char[] full, Resource res) {
                write.writefln("Full=%s, Id=%s", full, res.id);
                //write.writef(" refcount=%d,", res.refcount);
                write.writef(" uid=%d, loaded=%s, refed=%s", res.uid,
                    res.isLoaded, "?"); //res.isRefed);
                write.writefln(" type=%s,", res.type);
                count++;
            }
        );
        write.writefln("%d resources.", count);
        file.close();
    }

    private void cmdResUnload(MyBox[] args, Output write) {
        //can crash; see unloadUnneeded() for details
        gFramework.resources.unloadUnneeded();
    }

    private void cmdGrab(MyBox[] args, Output write) {
        gFramework.grabInput = args[0].unbox!(bool)();
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

    private Task findTask(MyBox[] args, Output write) {
        int id = args[0].unbox!(int)();
        foreach (Task t; taskManager.taskList) {
            if (id == t.taskID) {
                return t;
            }
        }
        write.writefln("Task %d not found.", id);
        return null;
    }

    private void cmdKill(MyBox[] args, Output write) {
        Task t = findTask(args, write);
        if (t) {
            write.writefln("killing %s", t);
            t.kill();
            write.writefln("kill: done");
        }
    }

    private void cmdTerminate(MyBox[] args, Output write) {
        Task t = findTask(args, write);
        if (t) {
            write.writefln("terminating %s", t);
            t.terminate();
        }
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered task classes: %s", TaskFactory.classes);
    }

    private void cmdFramerate(MyBox[] args, Output write) {
        gFramework.fixedFramerate = args[0].unbox!(int)();
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: %s", gFramework.screenSize);
        mGui.size = gFramework.screenSize;
    }

    private void cmdVideo(MyBox[] args, Output write) {
        int a = args[0].unbox!(int);
        int b = args[1].unbox!(int);
        int c = args[2].unbox!(int);
        try {
            gFramework.setVideoMode(Vector2i(a, b), c);
        } catch (Exception e) {
            //failed to set video mode, try again in windowed mode
            gFramework.setVideoMode(Vector2i(a, b), c, false);
        }
    }

    private void cmdFS(MyBox[] args, Output write) {
        try {
            gFramework.fullScreen = !gFramework.fullScreen;
        } catch (Exception e) {
            //fullscreen switch failed
            write.writefln(e);
        }
    }

    //bind [name action [keys]]
    private void cmdBind(MyBox[] args, Output write) {
        if (!args[0].empty()) {
            switch (args[0].unbox!(char[])()) {
                case "add":
                    if (!args[1].empty() && !args[1].empty()) {
                        keybindings.addBinding(args[1].unbox!(char[])(),
                            args[2].unbox!(char[])());
                        return;
                    }
                case "kill":
                    if (!args[1].empty()) {
                        keybindings.removeBinding(args[1].unbox!(char[])());
                        return;
                    }
                default:
            }
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
        gFramework.terminate();
    }

    private void testGC(MyBox[] args, Output write) {
        auto counter = new PerfTimer();
        gc.GCStats s1, s2;
        gc.getStats(s1);
        counter.start();
        gc.fullCollect();
        counter.stop();
        gc.getStats(s2);
        write.writefln("GC fullcollect: %s, free'd %s KB", counter.time,
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

    private void onUpdate() {
        //xxx move?
        globals.gameTimeAnimations.update();

        mTaskTime.start();
        taskManager.doFrame();
        mTaskTime.stop();

        mGuiFrameTime.start();
        mGui.doFrame(timeCurrentTime());
        mGuiFrameTime.stop();
    }

    private void onFrame(Canvas c) {
        mGuiDrawTime.start();
        mGui.draw(c);
        mGuiDrawTime.stop();
    }

    private void onKeyPress(KeyInfo infos) {
        mGui.putOnKeyPress(infos);
    }

    private bool onKeyDown(KeyInfo infos) {
        if (mKeyNameIt) {
            //modifiers are also keys, ignore them
            if (gFramework.isModifierKey(infos.code)) {
                return false;
            }
            auto mods = gFramework.getModifierSet();
            mGuiConsole.output.writefln("Key: '%s' '%s'",
                keybindings.unparseBindString(infos.code, mods),
                globals.translateKeyshortcut(infos.code, mods));
            mKeyNameIt = false;
            return false;
        }
        if (mShowKeyDebug) {
            globals.log("down: %s", gFramework.keyinfoToString(infos));
        }
        char[] bind = keybindings.findBinding(infos.code,
            gFramework.getModifierSet());
        if (bind) {
            if (mShowKeyDebug) {
                globals.log("Binding '%s'", bind);
            }
            globals.cmdLine.execute(bind);
            return false;
        }
        mGui.putOnKeyDown(infos);
        return true;
    }

    private bool onKeyUp(KeyInfo infos) {
        if (mShowKeyDebug) {
            globals.log("up: %s", gFramework.keyinfoToString(infos));
        }
        mGui.putOnKeyUp(infos);
        return true;
    }

    private void onMouseMove(MouseInfo mouse) {
        //globals.log("%s", mouse.pos);
        mGui.putOnMouseMove(mouse);
    }
}

class ConsoleWindow : Task {
    this(TaskManager mgr) {
        super(mgr);
        gWindowManager.createWindowFullscreen(this,
            new GuiConsole(true, globals.cmdLine), "Console");
    }

    static this() {
        TaskFactory.register!(typeof(this))("console");
    }
}

import gui.tablecontainer;
import gui.label;

class StatsWindow : Task {
    TopLevel bla;
    int lastupdate = -1;
    Window wnd;
    TableContainer table;

    this(TaskManager mgr) {
        super(mgr);
        bla = gTopLevel;
        table = new TableContainer(2, 0, Vector2i(10, 0));
        //rettet die statistik
        wnd = gWindowManager.createWindow(this, table, "Statistics");
        auto props = wnd.properties;
        props.zorder = WindowZOrder.High;
        wnd.properties = props;
    }

    override void onFrame() {
        if (bla.mTimerStatsGeneration != lastupdate) {
            lastupdate = bla.mTimerStatsGeneration;

            void setLine(int line, char[] a, char[] b) {
                Label la, lb;
                if (!table.get(0, line)) {
                    la = new Label();
                    lb = new Label();
                    la.font = gFramework.getFont("normal");
                    lb.font = la.font;
                    la.drawBorder = false;
                    lb.drawBorder = false;
                    table.add(la, 0, line);
                    table.add(lb, 1, line, WidgetLayout.Aligned(+1, 0));
                } else {
                    la = cast(Label)table.get(0, line);
                    lb = cast(Label)table.get(1, line);
                }
                la.text = a;
                lb.text = b;
            }

            wnd.client = null; //dirty trick to avoid relayouting all the time
            table.setSize(2, bla.timerCount+3);

            int n = 0;

            gc.GCStats gcs;
            gc.getStats(gcs);

            setLine(0, "GC Used", sizeToHuman(gcs.usedsize));
            setLine(1, "GC Poolsize", sizeToHuman(gcs.poolsize));
            /*setLine(2, "Weak objects",
                gFramework.getInfoString(InfoString.Custom0));*/

            n += 3;

            bla.listTimers((char[] a, char[] b) {
                setLine(n, a, b);
                n++;
            });

            wnd.client = table;
            //avoid that the window resizes on each update
            wnd.acceptSize();
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("stats");
    }
}
