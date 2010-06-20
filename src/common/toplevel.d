//connects GUI, Task-stuff and the framework; also contains general stuff
module common.toplevel;

import framework.font;
import framework.globalsettings;
import framework.imgwrite;
import framework.keysyms;
import framework.framework;
import framework.sound;
import framework.commandline;
import framework.i18n;
import utils.timesource;
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
import gui.window;
import common.common;
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
    SystemConsole mGuiConsole;

    bool mKeyNameIt = false;

    PerfTimer mTaskTime, mGuiDrawTime, mGuiFrameTime;
    PerfTimer mFrameTime;

    Time[PerfTimer] mLastTimerValues;
    long[char[]] mLastCounterValues;
    size_t[char[]] mLastSizeStatValues;

    const cTimerStatsUpdateTimeMs = 1000;

    Time mLastTimerStatsUpdate;
    int mLastTimerStatsFrames;
    bool mLastTimerInitialized;
    int mTimerStatsGeneration;

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
            foreach (char[] name, ref size_t sz; globals.size_stats) {
                mLastSizeStatValues[name] = sz;
                sz = 0;
            }
        }
        mLastTimerStatsFrames++;

        mFrameTime.start();
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
    void listSizeStats(void delegate(char[] name, size_t sz) cb) {
        foreach (char[] name, size_t sz; globals.size_stats) {
            size_t* ps = name in mLastSizeStatValues;
            size_t s = 0;
            if (ps)
                s = *ps;
            cb(name, s);
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

        GuiFps fps = new GuiFps();
        fps.zorder = GUIZOrder.FPS;
        mGui.mainFrame.add(fps);

        mGuiConsole = new SystemConsole();
        mGuiConsole.zorder = GUIZOrder.Console;
        WidgetLayout clay;
        clay.fill[1] = 1.0f/2;
        clay.alignment[1] = 0;
        clay.border = Vector2i(4);
        mGui.mainFrame.add(mGuiConsole, clay);

        initConsole();

        gWindowFrame = new WindowFrame();
        mGui.mainFrame.add(gWindowFrame);

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
    }

    public void deinitialize() {
    }

    private void initConsole() {
        globals.cmdLine = mGuiConsole.cmdline;
        globals.cmdLine.commands.helpTranslator = localeRoot.bindNamespace(
            "console_commands.global");

        globals.defaultOut = mGuiConsole.output;

        globals.cmdLine.registerCommand("gc", &testGC, "", ["bool?=true"]);
        globals.cmdLine.registerCommand("gcmin", &cmdGCmin, "");
        globals.cmdLine.registerCommand("gcstats", &testGCstats, "");

        globals.cmdLine.registerCommand("quit", &killShortcut, "");
        globals.cmdLine.registerCommand("toggle", &showConsole, "");
        globals.cmdLine.registerCommand("nameit", &cmdNameit, "");
        globals.cmdLine.registerCommand("video", &cmdVideo, "",
            ["int", "int", "int?=0", "bool?"]);
        globals.cmdLine.registerCommand("fullscreen", &cmdFS, "", ["text?"]);
        globals.cmdLine.registerCommand("screenshot", &cmdScreenshot,
            "", ["text?"]);
        globals.cmdLine.registerCommand("screenshotwnd", &cmdScreenshotWnd,
            "", ["text?"]);

        globals.cmdLine.registerCommand("spawn", &cmdSpawn, "",
            ["text", "text?..."], [&complete_spawn]);
        globals.cmdLine.registerCommand("help_spawn", &cmdSpawnHelp, "");

        globals.cmdLine.registerCommand("res_load", &cmdResLoad, "", ["text"]);
        globals.cmdLine.registerCommand("res_unload", &cmdResUnload, "", []);

        globals.cmdLine.registerCommand("release_caches", &cmdReleaseCaches,
            "", ["bool?=true"]);

        globals.cmdLine.registerCommand("fw_settings", &cmdFwSettings,
            "", null);

        //settings
        globals.cmdLine.registerCommand("settings_set", &cmdSetSet, "",
            ["text", "text..."]);
        globals.cmdLine.registerCommand("settings_help", &cmdSetHelp, "",
            ["text"]);
        globals.cmdLine.registerCommand("settings_list", &cmdSetList, "", []);
        //used for key shortcuts
        globals.cmdLine.registerCommand("settings_cycle", &cmdSetCycle, "",
            ["text"]);
    }

    private void cmdFwSettings(MyBox[] args, Output write) {
        createPropertyEditWindow("Framework settings");
    }

    private void cmdSetSet(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        char[] value = args[1].unbox!(char[]);
        setSetting(name, value);
    }

    private void cmdSetHelp(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        write.writefln("{}", settingValueHelp(name));
    }

    private void cmdSetList(MyBox[] args, Output write) {
        foreach (s; gSettings) {
            write.writefln("{} = {}", s.name, s.value);
        }
    }

    private void cmdSetCycle(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[]);
        settingCycle(name, +1);
    }

    private void cmdReleaseCaches(MyBox[] args, Output write) {
        int released = gFramework.releaseCaches(args[0].unbox!(bool));
        write.writefln("released {} memory consuming house shoes", released);
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

    private void cmdSpawn(MyBox[] args, Output write) {
        char[] name = args[0].unbox!(char[])();
        char[] spawnArgs = args[1].unboxMaybe!(char[])();
        if (!spawnTask(name, spawnArgs)) {
            write.writefln("not found ({})", name);
        }
    }

    private char[][] complete_spawn() {
        return taskList();
    }

    private void cmdSpawnHelp(MyBox[] args, Output write) {
        write.writefln("registered task classes: {}", taskList());
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
        } catch (CustomException e) {
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
        } catch (CustomException e) {
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
        WindowWidget topWnd = gWindowFrame.activeWindow();
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
            Rect2i r = topWnd.containedBounds;
            scope subsurf = surf.subrect(r);
            saveImage(subsurf, ssFile, "png");
        } else
            saveImage(surf, ssFile, "png");
    }

    private void cmdNameit(MyBox[] args, Output write) {
        mKeyNameIt = true;
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

    private void onUpdate() {
        debug {
            int gccount = gc_stat_get!(int)("gcCounter");
            if (gccount != mPrevGCCount) {
                registerLog("gc")("GC run detected");
                mPrevGCCount = gccount;
            }
        }

        mTaskTime.start();
        runTasks();
        mTaskTime.stop();

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
            if (!event.keyEvent.isDown)
                return;

            BindKey key = BindKey.FromKeyInfo(event.keyEvent);

            mGuiConsole.output.writefln("Key: '{}' '{}', code={} mods={}",
                key.unparse(), globals.translateKeyshortcut(key),
                key.code, key.mods);

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
                if (event.keyEvent.isDown)
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

static this() {
    registerTask("console", function(char[] args) {
        gWindowFrame.createWindowFullscreen(new GuiConsole(globals.cmdLine),
            "Console");
    });
}

import gui.tablecontainer;
import gui.label;
import str = utils.string;

class StatsWindow {
    TopLevel bla;
    int lastupdate = -1;
    WindowWidget wnd;
    TableContainer table;
    //stores strings for each line (each line 40 bytes)
    //this is to avoid memory allocation each frame
    char[40][] buffers;

    this() {
        bla = gTopLevel;
        table = new TableContainer(2, 0, Vector2i(10, 0));
        //rettet die statistik
        wnd = gWindowFrame.createWindow(table, "Statistics");
        auto props = wnd.properties;
        props.zorder = WindowZOrder.High;
        wnd.properties = props;

        addTask(&onFrame);
    }

    private bool onFrame() {
        if (wnd.wasClosed())
            return false;

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

            bla.listSizeStats((char[] a, size_t sz) {
                auto s = str.sizeToHuman(sz, lineBuffer());
                addLine(a, s);
            });

            //--wnd.client = table;
            //avoid that the window resizes on each update
            wnd.acceptSize();
        }

        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("stats");
    }
}

//GUI to disable or enable log targets
class LogConfig {
    CheckBox[char[]] mLogButtons;
    BoxContainer mLogList;
    WindowWidget mWindow;

    this() {
        mLogList = new BoxContainer(false);
        auto main = new BoxContainer(false);
        main.add(mLogList);
        auto save = new Button();
        save.text = "Save to disk";
        save.onClick = &onSave;
        main.add(save);

        addLogs();

        mWindow = gWindowFrame.createWindow(main, "Logging Configuration");

        addTask(&onFrame);
    }

    void onToggle(CheckBox sender) {
        foreach (char[] name, CheckBox b; mLogButtons) {
            if (sender is b) {
                registerLog(name).minPriority =
                    sender.checked ? LogPriority.Trace : LogPriority.Minor;
                return;
            }
        }
    }

    void onSave(Button sender) {
        char[] fname = "logconfig.conf";
        ConfigNode config = loadConfig(fname, true, true);
        config = config ? config : new ConfigNode();
        auto logs = config.getSubNode("logs");
        foreach (char[] name, Log log; gAllLogs) {
            logs.setValue!(bool)(name, log.minPriority <= LogPriority.Trace);
        }
        saveConfig(config, fname);
    }

    void addLogs() {
        foreach (char[] name, Log log; gAllLogs) {
            auto pbutton = name in mLogButtons;
            CheckBox button = pbutton ? *pbutton : null;
            if (!button) {
                //actually add
                button = new CheckBox();
                button.text = name;
                button.onClick = &onToggle;
                mLogButtons[name] = button;
                mLogList.add(button);
            }
            button.checked = log.minPriority <= LogPriority.Trace;
        }
    }

    private bool onFrame() {
        if (mWindow.wasClosed())
            return false;
        //every frame check for new log entries; stupid but robust
        addLogs();
        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("logconfig");
    }
}
