//connects GUI, Task-stuff and the framework; also contains general stuff
module common.toplevel;

import framework.font;
import framework.keysyms;
import framework.framework;
import framework.sound;
import framework.commandline;
import framework.i18n;
import framework.timesource;
import gui.widget;
import gui.fps;
import gui.container;
import gui.console;
import gui.propedit;
import gui.boxcontainer;
import gui.tablecontainer;
import gui.button;
import gui.scrollbar;
import gui.dropdownlist;
import gui.wm;
import common.common;
import common.loadsave;
import common.settings;
//import all restypes because of the factories (more for debugging...)
import common.allres;
import common.task;
import utils.time;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.output;
import utils.misc;
import utils.mybox;
import utils.perf;
import utils.proplist;
import memory = tango.core.Memory;
import utils.stream;
import tango.core.Variant;
import conv = tango.util.Convert;

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

version (LDC) {
    const cGCStats = false;
} else {
    const cGCStats = is(memory.GC.GCStats);
}

real gc_stat_get_r(char[] name) {
    static if (cGCStats) {
        memory.GC.GCStats stats = memory.GC.stats();
        if (name in stats)
            return stats[name];
    }
    return -1; //xD
}

T gc_stat_get(T)(char[] name, T def = T.init) {
    real res = gc_stat_get_r(name);
    return (res == -1) ? def : conv.to!(T)(res);
}

//sorry for the kludge; just for statistics
version (linux) {
    //gnu libc specific
    //http://www.gnu.org/s/libc/manual/html_node/Statistics-of-Malloc.html
    struct mallinfo_s {
        //note: these are C ints
        int arena;
        int ordblks;
        int smblks;
        int hblks;
        int hblkhd;
        int usmblks;
        int fsmblks;
        int uordblks;
        int fordblks;
        int keepcost;
    }
    extern (C) mallinfo_s mallinfo();

    //stats[0] = allocated size
    //stats[1] = free size
    //stats[2] = mmap'ed size
    void get_cmalloc_stats(size_t[3] stats) {
        auto mi = mallinfo();
        stats[0] = mi.arena;
        stats[1] = 0; //???
        stats[2] = mi.hblkhd;
    }
} else {
    void get_cmalloc_stats(size_t[3] stats) {
        stats[] = 0;
    }
}

extern(C) void show_stuff();

//this contains the mainframe
class TopLevel {
private:
    KeyBindings keybindings;

    GUI mGui;
    GuiConsole mGuiConsole;
    GuiFps mFPS;

    TaskManager taskManager;

    bool mKeyNameIt = false;

    PerfTimer mTaskTime, mGuiDrawTime, mGuiFrameTime;
    PerfTimer mFrameTime;

    Time[PerfTimer] mLastTimerValues;
    long[char[]] mLastCounterValues;

    const cTimerStatsUpdateTimeMs = 1000;

    Time mLastTimerStatsUpdate;
    int mLastTimerStatsFrames;
    bool mLastTimerInitialized;
    int mTimerStatsGeneration;

    LoadSaveHandler mLoadSave;

    debug int mPrevGCCount;
    int mOldFixedFramerate;

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
            foreach (char[] name, ref long cnt; globals.counters) {
                mLastCounterValues[name] = cnt;
                cnt = 0;
            }
        }
        mLastTimerStatsFrames++;

        mFrameTime.start();
    }

    void cmdShowTimers(MyBox[] args, Output write) {
        write.writefln("Timers:");
        listTimers((char[] a, Time t) {write.writefln("   {}: {}", a, t);});
    }

    void listTimers(void delegate(char[] name, Time value) cb) {
        foreach (char[] name, PerfTimer cnt; globals.timers) {
            Time* pt = cnt in mLastTimerValues;
            Time t = Time.Never;
            if (pt)
                t = *pt;
            cb(name, t);
        }
    }
    void listCounters(void delegate(char[] name, long value) cb) {
        foreach (char[] name, long cnt; globals.counters) {
            long* pt = name in mLastCounterValues;
            long t = 0;
            if (pt)
                t = *pt;
            cb(name, t);
        }
    }

    public this() {
        assert(!gTopLevel, "singleton");
        gTopLevel = this;

        auto framework = gFramework;

        mTaskTime = globals.newTimer("tasks");
        mGuiDrawTime = globals.newTimer("gui_draw");
        mGuiFrameTime = globals.newTimer("gui_frame");
        mFrameTime = globals.newTimer("frame_time");

        mGui = new GUI();

        gGuiTheme.addListener(&onChangeGuiTheme);
        onChangeGuiTheme(gGuiTheme);

        mFPS = new GuiFps();
        mFPS.zorder = GUIZOrder.FPS;
        mFPS.visible = false;
        mGui.mainFrame.add(mFPS);

        mGuiConsole = new GuiConsole(false);
        mGuiConsole.zorder = GUIZOrder.Console;
        mGui.mainFrame.add(mGuiConsole);

        initConsole();

        taskManager = new TaskManager();

        mLoadSave = new LoadSaveHandler(taskManager);

        gWindowManager = new WindowManager(mGui);

        framework.onUpdate = &onUpdate;
        framework.onFrame = &onFrame;
        framework.onInput = &onInput;
        framework.onVideoInit = &onVideoInit;
        framework.onFrameEnd = &onFrameEnd;
        framework.onFocusChange = &onFocusChange;

        //fugly!
        //framework.clearColor = Color(0,0,1);

        //do it yourself... (initial event)
        onVideoInit(false);

        keybindings = new KeyBindings();
        keybindings.loadFrom(loadConfig("binds").getSubNode("binds"));

        ConfigNode autoexec = loadConfig("autoexec");
        //if (globals.programArgs.findNode("exec")) {
        //    autoexec = globals.programArgs.getSubNode("exec");
        //}
        foreach (char[] name, char[] value; autoexec) {
            globals.cmdLine.execute(value);
        }

        if (taskManager.taskList.length == 0) {
            mGuiConsole.output.writefln("Nothing to run, do what you want");
            mGuiConsole.consoleVisible = true;
        }
    }

    public void deinitialize() {
        //this gets important when tasks start running threads...
        taskManager.killAll();
    }

    private void onChangeGuiTheme(PropertyValue v) {
        mGui.loadTheme(gGuiTheme.asString());
    }

    private void initConsole() {
        globals.cmdLine = mGuiConsole.cmdline;

        globals.setDefaultOutput(mGuiConsole.output);

        globals.cmdLine.registerCommand("gc", &testGC, "timed GC run (+minimize)",
            ["bool?=true:release framework caches before gc run"]);
        globals.cmdLine.registerCommand("gcmin", &cmdGCmin, "call GC.minimize");
        globals.cmdLine.registerCommand("gcstats", &testGCstats, "GC stats");
        globals.cmdLine.registerCommand("show_stuff", &cmdShowStuff, "-");

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
            "int?=0:depth (bits)",
            "bool?:fullscreen"]);
        globals.cmdLine.registerCommand("fullscreen", &cmdFS, "toggle fs",
            ["text?:pass 'desktop' to change to desktop resolution first"]);
        globals.cmdLine.registerCommand("framerate", &cmdFramerate,
            "set fixed framerate", ["int:framerate"]);
        globals.cmdLine.registerCommand("screenshot", &cmdScreenshot,
            "take a screenshot", ["text?:filename for saved image"]);
        globals.cmdLine.registerCommand("screenshotwnd", &cmdScreenshotWnd,
            "take a screenshot of the active window",
            ["text?:filename for saved image"]);

        globals.cmdLine.registerCommand("ps", &cmdPS, "list tasks");
        globals.cmdLine.registerCommand("spawn", &cmdSpawn, "create task",
            ["text:task name (get available ones with 'help_spawn')",
             "text?...:arguments for new task"],
            [&complete_spawn]);
        globals.cmdLine.registerCommand("kill", &cmdKill, "kill a task by ID",
            ["int:task id"]);
        globals.cmdLine.registerCommand("terminate", &cmdTerminate,
            "terminate a task by ID", ["int:task id"]);
        globals.cmdLine.registerCommand("help_spawn", &cmdSpawnHelp,
            "list tasks registered at task factory (use for spawn)");
        globals.cmdLine.registerCommand("grab", &cmdGrab, "-", ["bool:onoff"]);

        globals.cmdLine.registerCommand("res_load", &cmdResLoad,
            "load resources", ["text:filename"]);
        globals.cmdLine.registerCommand("res_unload", &cmdResUnload,
            "Unload unused resources", []);
        globals.cmdLine.registerCommand("res_list", &cmdResList,
            "List all resources", []);

        globals.cmdLine.registerCommand("release_caches", &cmdReleaseCaches,
            "Release caches (temporary data)", ["bool?=true:force"]);
        /+
        globals.cmdLine.registerCommand("caching", &cmdSetCaching,
            "Set if texture caching should be done", ["bool:if enabled"]);
        +/

        globals.cmdLine.registerCommand("times", &cmdShowTimers,
            "List timers", []);
        globals.cmdLine.registerCommand("show_fps", &cmdShowFps,
            "Enable/disable FPS display", ["bool:enable"]);
        globals.cmdLine.registerCommand("show_deltas", &cmdShowDeltas,
            "Toggle min/max frametime display", []);

        globals.cmdLine.registerCommand("fw_info", &cmdInfoString,
            "Query a info string from the framework, with no argument: list "
            "all info string names", ["text?:Name of the string or 'all'"],
            [&complete_fw_info]);
        /+
        globals.cmdLine.registerCommand("fw_debug", &cmdSetFWDebug,
            "Switch some debugging stuff in Framework on/off", ["bool:Value"]);
        +/

        globals.cmdLine.registerCommand("fw_settings", &cmdFwSettings,
            "Framework settings", null);

        //more like a test
        globals.cmdLine.registerCommand("widget_tree", &cmdWidgetTree, "-");
        globals.cmdLine.registerCommand("locale", &cmdLocale,
            "Change current locale (why are those help texts not translated??)",
            ["text:Language ID"]);
    }

    private void cmdShowFps(MyBox[] args, Output write) {
        mFPS.visible = args[0].unbox!(bool);
    }

    private void cmdShowDeltas(MyBox[] args, Output write) {
        mFPS.showDeltas = !mFPS.showDeltas;
    }

    private void cmdInfoString(MyBox[] args, Output write) {
        auto names = gFramework.getInfoStringNames();
        if (args[0].empty) {
            write.writefln("Strings:");
            foreach (char[] name, InfoString id; names) {
                write.writefln("  - {}", name);
            }
            return;
        }

        void show(InfoString s) {
            write.writef(gFramework.getInfoString(s));
        }

        char[] s = args[0].unbox!(char[]);
        if (s == "all") {
            foreach (char[] name, InfoString id; names) {
                write.writefln("{}:", name);
                show(id);
            }
        } else {
            if (s in names) {
                show(names[s]);
            } else {
                write.writefln("string '{}' not found", s);
            }
        }
    }

    private void cmdFwSettings(MyBox[] args, Output write) {
        auto t = new Task(taskManager); //grrr
        createPropertyEditWindow(t, gSettings, false,
            "Framework settings");
    }

    private char[][] complete_fw_info() {
        return gFramework.getInfoStringNames().keys;
    }

    private void cmdWidgetTree(MyBox[] args, Output write) {
        int maxdepth;
        int count;

        void showWidget(Widget w, int depth) {
            maxdepth = depth > maxdepth ? depth : maxdepth;
            count++;
            char[] pad; pad.length = depth*2; pad[] = ' ';
            write.writefln("{}{}", pad, w);
            w.enumChildren((Widget child) {
                showWidget(child, depth + 1);
            });
        }

        write.writefln("Widget tree:");
        showWidget(mGui.mainFrame, 0);
        write.writefln("maxdepth = {}, count = {}", maxdepth, count);
    }

    private void cmdReleaseCaches(MyBox[] args, Output write) {
        int released = gFramework.releaseCaches(args[0].unbox!(bool));
        write.writefln("released {} memory consuming house shoes", released);
    }

    private void cmdResList(MyBox[] args, Output write) {
        write.writefln("dumping to res.txt");
        auto file = new ConduitStream(castStrict!(Conduit)(
            new File("res.txt", File.WriteCreate)));
        write = new StreamOutput(file);
        int count;
        gResources.enumResources(
            (char[] full, ResourceItem res) {
                write.writefln("Full={}, Id={}", full, res.id);
                write.writefln(" loaded={},", res.isLoaded);
                count++;
            }
        );
        write.writefln("{} resources.", count);
        file.close();
    }

    private void cmdResUnload(MyBox[] args, Output write) {
        gResources.unloadAll();
    }

    private void cmdResLoad(MyBox[] args, Output write) {
        char[] s = args[0].unbox!(char[])();
        //xxx: catching any exception can be dangerous
        try {
            gResources.loadResources(s);
        } catch (Exception e) {
            write.writefln("failed: {}", e);
        }
    }

    private void cmdGrab(MyBox[] args, Output write) {
        auto state = args[0].unbox!(bool)();
        //gFramework.cursorVisible = !state;
        gFramework.mouseLocked = state;
    }

    private void cmdPS(MyBox[] args, Output write) {
        write.writefln("ID / toString()");
        foreach (Task t; taskManager.taskList) {
            write.writefln("  {:d2} / {}", t.taskID, t);
        }
    }

    private void cmdSpawn(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[])();
        char[] spawnArgs = args[1].unboxMaybe!(char[])();
        Task n;
        try {
            n = TaskFactory.instantiate(name, taskManager, spawnArgs);
        } catch (ClassNotFoundException e) {
            //xxx: and what if the Task was found, but the Task constructor
            //     throws this exception??
            write.writefln("not found ({})", e);
            return;
        }
        write.writefln("spawn: instantiated {} -> {}", name, n);
    }

    private char[][] complete_spawn() {
        return TaskFactory.classes;
    }

    private Task findTask(MyBox[] args, Output write) {
        int id = args[0].unbox!(int)();
        foreach (Task t; taskManager.taskList) {
            if (id == t.taskID) {
                return t;
            }
        }
        write.writefln("Task {} not found.", id);
        return null;
    }

    private void cmdKill(MyBox[] args, Output write) {
        Task t = findTask(args, write);
        if (t) {
            write.writefln("killing {}", t);
            t.kill();
            write.writefln("kill: done");
        }
    }

    private void cmdTerminate(MyBox[] args, Output write) {
        Task t = findTask(args, write);
        if (t) {
            write.writefln("terminating {}", t);
            t.terminate();
        }
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered task classes: {}", TaskFactory.classes);
    }

    private void cmdFramerate(MyBox[] args, Output write) {
        gFramework.fixedFramerate = args[0].unbox!(int)();
    }

    private void onVideoInit(bool depth_only) {
        globals.log("Changed video: {}", gFramework.screenSize);
        mGui.size = gFramework.screenSize;
        globals.saveVideoConfig();
    }

    private void cmdVideo(MyBox[] args, Output write) {
        int a = args[0].unbox!(int);
        int b = args[1].unbox!(int);
        int c = args[2].unbox!(int);
        bool fs = gFramework.fullScreen();
        if (!args[3].empty)
            fs = args[3].unbox!(bool);
        try {
            gFramework.setVideoMode(Vector2i(a, b), c, fs);
        } catch (FrameworkException e) {
            //failed to set video mode, try again in windowed mode
            gFramework.setVideoMode(Vector2i(a, b), c, false);
        }
    }

    private void cmdFS(MyBox[] args, Output write) {
        bool desktop = args[0].unboxMaybe!(char[]) == "desktop";
        try {
            if (desktop) {
                //go fullscreen in desktop mode
                gFramework.setVideoMode(gFramework.desktopResolution, -1, true);
            } else {
                //toggle fullscreen
                globals.setVideoFromConf(true);
            }
        } catch (FrameworkException e) {
            //fullscreen switch failed
            write.writefln("error: {}", e);
        }
    }

    const cScreenshotDir = "/screenshots/";

    private void cmdScreenshot(MyBox[] args, Output write) {
        char[] filename = args[0].unboxMaybe!(char[]);
        saveScreenshot(filename, false);
        write.writefln("Screenshot saved as '{}'", filename);
    }

    private void cmdScreenshotWnd(MyBox[] args, Output write) {
        char[] filename = args[0].unboxMaybe!(char[]);
        saveScreenshot(filename, true);
        write.writefln("Screenshot saved as '{}'", filename);
    }

    //save a screenshot to a png image
    //  activeWindow: only save area of active window, with decorations
    //    (screen contents of window area, also saves overlapping stuff)
    private void saveScreenshot(ref char[] filename,
        bool activeWindow = false)
    {
        //get active window, and its title
        auto topWnd = gWindowManager.activeWindow();
        char[] wndTitle;
        if (topWnd)
            wndTitle = topWnd.properties.windowTitle;
        else
            activeWindow = false;

        if (filename.length > 0) {
            //filename given, prepend screenshot directory
            filename = cScreenshotDir ~ filename;
        } else {
            //no filename, generate one
            int i;
            filename = gFS.getUniqueFilename(cScreenshotDir,
                activeWindow?"window-"~wndTitle~"{}":"screen{}", ".png", i);
        }

        scope surf = gFramework.screenshot();
        scope ssFile = gFS.open(filename, File.WriteCreate);
        scope(exit) ssFile.close();  //no close on delete? strange...
        if (activeWindow) {
            //copy out area of active window
            Rect2i r = topWnd.window.containedBounds;
            scope subsurf = surf.subrect(r);
            subsurf.saveImage(ssFile, "png");
        } else
            surf.saveImage(ssFile, "png");
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
                write.writefln("    {}='{}' ('{}')", bind,
                    keybindings.unparseBindString(code, mods),
                    globals.translateKeyshortcut(code, mods));
            }
        );
    }

    private void cmdNameit(MyBox[] args, Output write) {
        mKeyNameIt = true;
    }

    private void cmdLocale(MyBox[] args, Output write) {
        char[] lid = args[0].unbox!(char[]);
        globals.initLocale(lid);
    }

    private void showConsole(MyBox[], Output) {
        mGuiConsole.toggle();
    }
    public bool consoleVisible() {
        return mGuiConsole.consoleVisible();
    }

    private void killShortcut(MyBox[], Output) {
        gFramework.terminate();
    }

    private void testGC(MyBox[] args, Output write) {
        if (args[0].unbox!(bool)) {
            auto n = gFramework.releaseCaches(false);
            write.writefln("release caches: {} house shoes", n);
        }
        size_t getsize() { return gc_stat_get!(size_t)("usedSize"); }
        auto counter = new PerfTimer();
        auto a = getsize();
        counter.start();
        memory.GC.collect();
        counter.stop();
        auto b = getsize();
        write.writefln("GC fullcollect: {}, free'd {}", counter.time,
            str.sizeToHuman(a - b));
        memory.GC.minimize();
        auto c = getsize();
        write.writefln("  ...minimize: {}", str.sizeToHuman(c - b));
    }
    private void testGCstats(MyBox[] args, Output write) {
        static if (cGCStats) {
            foreach (k; memory.GC.stats().keys()) {
                write.writefln("{} = {}", k, gc_stat_get_r(k));
            }
        }
        write.writefln("C malloc stats:");
        size_t[3] bla;
        get_cmalloc_stats(bla);
        write.writefln("allocated: {}", str.sizeToHuman(bla[0]));
        write.writefln("free: {}", str.sizeToHuman(bla[1]));
        write.writefln("mmap'ed: {}", str.sizeToHuman(bla[2]));
    }
    private void cmdGCmin(MyBox[] args, Output write) {
        memory.GC.minimize();
    }
    private void cmdShowStuff(MyBox[] args, Output write) {
        show_stuff();
    }

    private void onUpdate() {
        debug {
            int gccount = gc_stat_get!(int)("gcCounter");
            if (gccount != mPrevGCCount) {
                registerLog("gc")("GC run detected");
                mPrevGCCount = gccount;
            }
        }

        mTaskTime.start();
        taskManager.doFrame();
        mTaskTime.stop();

        globals.callFrameCallBacks();

        mGuiFrameTime.start();
        mGui.frame();
        mGuiFrameTime.stop();

        globals.setCounter("soundchannels", gSoundManager.activeSources());
    }

    private void onFrame(Canvas c) {
        mGuiDrawTime.start();
        mGui.draw(c);
        mGuiDrawTime.stop();
    }

    private void onInput(InputEvent event) {
        //for debugging
        //but something similar will be needed for a proper keybindings editor
        if (mKeyNameIt && event.isKeyEvent) {
            if (!event.keyEvent.isDown())
                return;

            auto mods = event.keyEvent.mods;
            auto code = event.keyEvent.code;

            mGuiConsole.output.writefln("Key: '{}' '{}', code={} mods={}",
                keybindings.unparseBindString(code, mods),
                globals.translateKeyshortcut(code, mods),
                cast(int)code, cast(int)mods);

            //modifiers are also keys, ignore them
            if (!event.keyEvent.isModifierKey()) {
                mKeyNameIt = false;
            }

            return;
        }

        //execute global shortcuts
        if (event.isKeyEvent) {
            char[] bind = keybindings.findBinding(event.keyEvent);
            if (bind.length > 0) {
                if (event.keyEvent.isDown())
                    globals.cmdLine.execute(bind);
                return;
            }
        }

        //deliver event to the GUI
        mGui.putInput(event);
    }

    //app input focus changed
    private void onFocusChange(bool focused) {
        //when the app goes out of focus, limit framerate to 10fps to
        //limit cpu consumption. old fps limit is restored when focused again
        if (focused) {
            gFramework.fixedFramerate = mOldFixedFramerate;
        } else {
            mOldFixedFramerate = gFramework.fixedFramerate;
            gFramework.fixedFramerate = 10;
        }
        //xxx pause game?
    }
}

class ConsoleWindow : Task {
    this(TaskManager mgr, char[] args = "") {
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
import str = utils.string;

class StatsWindow : Task {
    TopLevel bla;
    int lastupdate = -1;
    Window wnd;
    TableContainer table;
    //stores strings for each line (each line 40 bytes)
    //this is to avoid memory allocation each frame
    char[40][] buffers;

    this(TaskManager mgr, char[] args = "") {
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

            int line = 0;

            char[] lineBuffer() {
                if (buffers.length <= line)
                    buffers.length = line+1;
                return buffers[line];
            }

            void addLine(char[] a, char[] b) {
                Label la, lb;
                if (line >= table.height) {
                    table.setSize(table.width, line+1);
                }
                if (!table.get(0, line)) {
                    la = new Label();
                    lb = new Label();
                    table.add(la, 0, line);
                    table.add(lb, 1, line, WidgetLayout.Aligned(+1, 0));
                } else {
                    la = cast(Label)table.get(0, line);
                    lb = cast(Label)table.get(1, line);
                }
                la.text = a;
                lb.text = b;

                line++;
            }

            //--commented out, because it allocates memory
            //--maybe that makes it VERY slow with many lines... or so
            //--wnd.client = null; //dirty trick to avoid relayouting all the time

            addLine("GC Used",
                str.sizeToHuman(gc_stat_get!(size_t)("usedSize"),
                lineBuffer()));
            addLine("GC Poolsize",
                str.sizeToHuman(gc_stat_get!(size_t)("poolSize"),
                lineBuffer()));
            addLine("GC count", myformat_s(lineBuffer(), "{}",
                gc_stat_get!(ulong)("gcCounter")));

            void gc_time(char[] disp, char[] name) {
                addLine(disp,
                    timeSecs(gc_stat_get!(real)(name))
                    .toString_s(lineBuffer()));
            }
            gc_time("GC m-time", "totalMarkTime");
            gc_time("GC s-time", "totalSweepTime");

            size_t[3] mstats;
            get_cmalloc_stats(mstats);
            addLine("C malloc", str.sizeToHuman(mstats[0], lineBuffer()));
            addLine("C malloc-mmap", str.sizeToHuman(mstats[2], lineBuffer()));

            addLine("Weak objects", myformat_s(lineBuffer(), "{}",
                gFramework.weakObjectsCount));

            bla.listTimers((char[] a, Time b) {
                auto buf = lineBuffer();
                auto s = b.toString_s(buf);
                addLine(a, s);
            });

            bla.listCounters((char[] a, long b) {
                auto s = myformat_s(lineBuffer(), "{}", b);
                addLine(a, s);
            });

            //--wnd.client = table;
            //avoid that the window resizes on each update
            wnd.acceptSize();
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("stats");
    }
}

//GUI to disable or enable log targets
class LogConfig : Task {
    Button[char[]] mLogButtons;
    BoxContainer mLogList;

    this(TaskManager mgr, char[] args = "") {
        super(mgr);

        mLogList = new BoxContainer(false);
        auto main = new BoxContainer(false);
        main.add(mLogList);
        auto save = new Button();
        save.text = "Save to disk";
        save.onClick = &onSave;
        main.add(save);

        addLogs();

        gWindowManager.createWindow(this, main, "Logging Configuration");
    }

    void onToggle(Button sender) {
        foreach (char[] name, Button b; mLogButtons) {
            if (sender is b) {
                registerLog(name).stfu = !sender.checked;
                return;
            }
        }
    }

    void onSave(Button sender) {
        ConfigNode config = loadConfig("logging");
        auto logs = config.getSubNode("logs");
        foreach (char[] name, Log log; gAllLogs) {
            logs.setValue!(bool)(name, !log.stfu);
        }
        saveConfig(config, "logging.conf");
    }

    void addLogs() {
        foreach (char[] name, Log log; gAllLogs) {
            auto pbutton = name in mLogButtons;
            Button button = pbutton ? *pbutton : null;
            if (!button) {
                //actually add
                button = new Button();
                button.isCheckbox = true;
                button.text = name;
                button.onClick = &onToggle;
                mLogButtons[name] = button;
                mLogList.add(button);
            }
            button.checked = !log.stfu;
        }
    }

    override void onFrame() {
        //every frame check for new log entries; stupid but robust
        addLogs();
    }

    static this() {
        TaskFactory.register!(typeof(this))("logconfig");
    }
}
