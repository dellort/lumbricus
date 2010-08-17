module common.debugstuff;

import common.common;
import common.task;
import framework.commandline;
import framework.main;
import framework.sound;
import gui.boxcontainer;
import gui.button;
import gui.console;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.window;
import utils.array;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.mybox;
import utils.output;
import utils.perf;
import utils.stream;
import utils.time;
import utils.vector2;

import str = utils.string;

import memory = tango.core.Memory;
import conv = tango.util.Convert;

debug {
} else {
    //not debug
    static assert("debugstuff.d should be included in debug mode only");
}

//gc_stats() API, which Tango doesn't expose to the user for very retarded
//  reasons, and there have been various attempts to expose such functionality
//  to the user, which all failed - see Tango #1702
//well, fuck this, instead I'll just using some violence to access this
struct GCStats //from gcstats.d
{
    size_t poolsize;        // total size of pool
    size_t usedsize;        // bytes allocated
    size_t freeblocks;      // number of blocks marked FREE
    size_t freelistsize;    // total of memory on free lists
    size_t pageblocks;      // number of blocks marked PAGE
}
extern (C) GCStats gc_stats(); //from gc.d

Time gGcTime = Time.Null;
Time gGcLastTime = Time.Null;
size_t gGcCounter;

//was added after 0.99.9 to trunk (xxx: remove the static if on next release)
static if (is(typeof(&memory.GC.monitor))) {

Time gGcStart;
//these callbacks are called by the GC on start/end of a collection
//they must be async-signal safe (they also are protected by the gc lock)
void gc_monitor_begin() {
    gGcCounter++;
    gGcStart = perfThreadTime();
}
//no idea what these params are; they return sizes, but why the hell are
//  these ints, and not size_t? (they may fix it later)
void gc_monitor_end(int a, int b) {
    gGcLastTime = perfThreadTime() - gGcStart;
    gGcTime += gGcLastTime;
}
static this() {
    //not using toDelegate() here, because the wrappers would be GC'ed
    memory.GC.monitor(() { gc_monitor_begin(); },
        (int a, int b) { gc_monitor_end(a, b); });
}

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

Stuff gStuff;

static this() {
    new Stuff();
}

class Stuff {
    Time[PerfTimer] mLastTimerValues;
    long[char[]] mLastCounterValues;
    size_t[char[]] mLastSizeStatValues;

    const cTimerStatsUpdateTimeMs = 1000;

    Time mLastTimerStatsUpdate;
    int mLastTimerStatsFrames;
    bool mLastTimerInitialized;
    int mTimerStatsGeneration;

    PerfTimer mFrameTime;

    int mPrevGCCount;

    private this() {
        assert(!gStuff);
        gStuff = this;

        mFrameTime = globals.newTimer("frame_time");

        globals.cmdLine.registerCommand("gc", &testGC, "", ["bool?=true"]);
        globals.cmdLine.registerCommand("gcmin", &cmdGCmin, "");

        gFramework.onFrameEnd = &onFrameEnd;

        addTask(&onFrame);
    }

    private bool onFrame() {
        debug {
            int gccount = gGcCounter;
            if (gccount != mPrevGCCount) {
                gLog.minor("GC run detected ({} total)", gccount);
                mPrevGCCount = gccount;
            }
        }

        globals.setCounter("soundchannels", gSoundManager.activeSources());

        return true;
    }

    private void onFrameEnd() {
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

    private void testGC(MyBox[] args, Output write) {
        if (args[0].unbox!(bool)) {
            auto n = gFramework.releaseCaches(false);
            write.writefln("release caches: {} house shoes", n);
        }
        size_t getsize() { return gc_stats().usedsize; }
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
    private void cmdGCmin(MyBox[] args, Output write) {
        memory.GC.minimize();
    }

}


class StatsWindow {
    Stuff bla;
    int lastupdate = -1;
    WindowWidget wnd;
    TableContainer table;
    //stores strings for each line (each line 40 bytes)
    //this is to avoid memory allocation each frame
    char[40][] buffers;

    this() {
        bla = gStuff;
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

            void number(char[] name, long n) {
                addLine(name, myformat_s(lineBuffer(), "{}", n));
            }
            void size(char[] name, size_t s) {
                addLine(name, str.sizeToHuman(s, lineBuffer()));
            }
            void time(char[] name, Time t) {
                addLine(name, t.toString_s(lineBuffer()));
            }

            auto gcs = gc_stats();

            size("gc.poolsize", gcs.poolsize);
            size("gc.usedsize", gcs.usedsize);
            size("gc.freelistsize", gcs.freelistsize);
            number("gc.freeblocks", gcs.freeblocks);
            number("gc.pageblocks", gcs.pageblocks);
            number("GC count", gGcCounter);
            time("GC collect time", gGcLastTime);
            time("GC collect time (sum)", gGcTime);

            size_t[3] mstats;
            get_cmalloc_stats(mstats);
            size("C malloc", mstats[0]);
            size("C malloc-mmap", mstats[2]);

            size("C malloc (BigArray)", gBigArrayMemory);

            number("Weak objects", gFramework.weakObjectsCount);

            bla.listTimers(&time);
            bla.listCounters(&number);
            bla.listSizeStats(&size);

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

static this() {
    registerTask("console", function(char[] args) {
        gWindowFrame.createWindowFullscreen(new GuiConsole(globals.real_cmdLine),
            "Console");
    });
}
