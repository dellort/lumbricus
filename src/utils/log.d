//a glorified printf()
//not multithreading-safe
module utils.log;

import utils.strparser;
import utils.time;
import utils.misc;

import array = utils.array;
import str = utils.string;

/// Access to all Log objects created so far.
Log[string] gAllLogs;

//anonymous log, if you just want to output something
Log gLog;

static this() {
    gLog = registerLog("general");
}

//numerical higher values mean more importance
//would be nice to keep this in sync with utils.lua/log_priorities
enum LogPriority : int {
    //noisy debugging messages, sometimes useful, need to explicitly do
    //  something to display them (like increasing log level)
    //you almost never want to see them
    Trace,
    //message that always should be output somewhere, but not too overt; e.g.
    //  somewhere on the console or in the log file, but not in the game GUI
    Minor,
    //message that should be actually user-visible (e.g. in the game GUI), but
    //  the message still indicates no danger or possible malfunction
    Notice,
    //non-fatal error or problem, of which the user should be informed
    Warn,
    //like Warn, but higher fatality (program may still continue, though)
    Error,
}

static this() {
    enumStrings!(LogPriority, "Trace,Minor,Notice,Warn,Error");
}

struct LogEntry {
    LogPriority pri;
    Log source;
    Time time;
    //txt contains only the original log text, use .fmt() to get a full string
    //warning: txt may point to temporary memory; use .dup() to be sure
    const(char)[] txt;

    LogEntry dup() {
        LogEntry e = this;
        e.txt = e.txt.dup;
        return e;
    }

    //some sort of default formatting
    void fmt(scope void delegate(cstring) sink) {
        //trying to keep heap activity down with that buffer thing
        char[80] buffer = void;
        myformat_cb(sink, "[%s] [%s] [%s] %s\n", time.toString_s(buffer[]),
            typeToString(pri), source.category, txt);
    }
}

//the caller must copy e.txt, as the buffer behind it may be reused
alias void delegate(LogEntry e) LogSink;

private LogBackend[] gLogBackends;
//this backend is only active if gLogBackends.length==0
//it's intended as fallback if the user forgets to add any backends
private LogBackend gDefaultBackend;

final class LogBackend {
    private {
        LogSink mSink;
        LogEntry[] mBuffered;
        string mName;
        bool mEnabled = true;
    }

    //all log events below that aren't passed to LogBackend.add()
    //NOTE: most Trace events will be invisible even if LogBackend.minPriority
    //  is set to Trace, because Log.minPriority is Minor by default
    LogPriority minPriority;

    this(string a_name, LogPriority a_minPriority, LogSink a_sink,
        bool add = true)
    {
        mName = a_name;
        minPriority = a_minPriority;
        mSink = a_sink;
        if (add)
            gLogBackends ~= this;
    }

    //remove from backend list, but don't reset internal state
    //stupid name for stupid semantics
    void retire() {
        array.arrayRemove(gLogBackends, this, true);
    }

    void sink(LogSink a_sink) {
        mSink = a_sink;
        if (a_sink) {
            auto x = mBuffered;
            mBuffered = null;
            foreach (e; x) {
                add(e);
            }
        }
    }
    LogSink sink() {
        return mSink;
    }

    //return unwritten log entries and clear them from internal list
    LogEntry[] flushLogEntries() {
        auto res = mBuffered;
        mBuffered = null;
        return res;
    }

    //if enabled=false, log events are never accepted
    //unlike as when sink is null, events aren't logged either
    bool enabled() {
        return mEnabled;
    }
    void enabled(bool s) {
        mEnabled = s;
        //forget the buffer if disabled
        if (!mEnabled)
            mBuffered = null;
    }

    string name() {
        return mName;
    }

    //if add() will actually use a LogEntry of that priority
    bool want(LogPriority pri) {
        return mEnabled && pri >= minPriority;
    }

    void add(LogEntry e) {
        if (!want(e.pri))
            return;

        if (mSink) {
            mSink(e);
        } else {
            mBuffered ~= e.dup();
        }
    }
}

static this() {
    void dump(LogEntry e) {
        void write(cstring s) { Trace.write(s); }
        e.fmt(&write);
    }
    gDefaultBackend = new LogBackend("def", LogPriority.Minor, &dump, false);
}

/// Generic logging class. Implements interface Output, and all lines of text
/// written to it are prefixed with a descriptive header.
final class Log {
    private {
        string mCategory;
        static array.Appender!(char) gBuffer;
    }

    //this is to selectively disable (potentially costly) Trace log calls
    LogPriority minPriority = LogPriority.Minor;

    //use registerLog()
    private this(string category) {
        mCategory = category;
        gAllLogs[category] = this;
    }

    //makes it completely silent, will not even write into logall.txt
    //this also should make all logging calls zero-cost
    void shutup() {
        minPriority = LogPriority.Minor;
    }

    string category() {
        return mCategory;
    }

    //same as calling trace(), mainly for compatibility
    void opCall(T...)(string fmt, T args) {
        emitx(LogPriority.Trace, fmt, args);
    }

    void trace(T...)(string fmt, T args) {
        emitx(LogPriority.Trace, fmt, args);
    }
    void minor(T...)(string fmt, T args) {
        emitx(LogPriority.Minor, fmt, args);
    }
    void notice(T...)(string fmt, T args) {
        emitx(LogPriority.Notice, fmt, args);
    }
    void warn(T...)(string fmt, T args) {
        emitx(LogPriority.Warn, fmt, args);
    }
    void error(T...)(string fmt, T args) {
        emitx(LogPriority.Error, fmt, args);
    }

    void emit(T...)(LogPriority pri, string fmt, T args) {
        emitx(pri, fmt, args);
    }

    void emitx(T...)(LogPriority pri, string fmt, T args)
    {
        //see if there's anything that wants this log entry
        if (pri < minPriority)
            return;

        bool want = false;
        bool write_to_default = true;
        foreach (b; gLogBackends) {
            write_to_default = false;
            if (b.want(pri)) {
                want = true;
                break;
            }
        }

        if (!want && !write_to_default)
            return;

        //format into temporary buffer
        gBuffer.length = 0;
        void sink(cstring s) {
            gBuffer ~= s;
        }
        myformat_cb(&sink, fmt, args);

        //distribute log event
        LogEntry e;
        e.pri = pri;
        e.source = this;
        e.time = timeCurrentTime();
        const(char)[] txt = gBuffer[];
        //generate multiple events if there are line breaks
        while (txt.length) {
            int idx = str.find(txt, '\n');
            if (idx >= 0) {
                e.txt = txt[0 .. idx];
                txt = txt[idx + 1 .. $];
            } else {
                e.txt = txt;
                txt = null;
            }
            foreach (b; gLogBackends) {
                b.add(e);
            }
            if (write_to_default)
                gDefaultBackend.add(e);
        }
    }

    string toString() {
        return "Log: >" ~ mCategory ~ "<";
    }
}

/// Register a log-category. There's one Log object per category-string, i.e.
/// multiple calls with the same argument will return the same object.
Log registerLog(string category) {
    auto log = findLog(category);
    if (!log) {
        log = new Log(category);
        //log.setBackend(StdioOutput.output, "null");
    }
    return log;
}

Log findLog(string category) {
    auto plog = category in gAllLogs;
    return plog ? *plog : null;
}

///Stupid proxy that allows to specify the log identifier with the declaration,
///and have the log created on demand, i.e.
///  private LogStruct!("mylog") log;
struct LogStruct(string cId) {
    private Log mLog;

    private Log check() {
        if (!mLog)
            mLog = registerLog(cId);
        return mLog;
    }

    Log logClass() {
        check();
        return mLog;
    }
    alias logClass get;

    string category() {
        return cId;
    }

    void emitx(T...)(LogPriority pri, string fmt, T args)
    {
        check();
        mLog.emitx(pri, fmt, args);
    }

    //------ sigh... copied from Log
    void opCall(T...)(string fmt, T args) {
        emitx(LogPriority.Trace, fmt, args);
    }

    void trace(T...)(string fmt, T args) {
        emitx(LogPriority.Trace, fmt, args);
    }
    void minor(T...)(string fmt, T args) {
        emitx(LogPriority.Minor, fmt, args);
    }
    void notice(T...)(string fmt, T args) {
        emitx(LogPriority.Notice, fmt, args);
    }
    void warn(T...)(string fmt, T args) {
        emitx(LogPriority.Warn, fmt, args);
    }
    void error(T...)(string fmt, T args) {
        emitx(LogPriority.Error, fmt, args);
    }

    void emit(T...)(LogPriority pri, string fmt, T args) {
        emitx(pri, fmt, args);
    }
    //------
}

//xxx probably there are better places where to put this code, maybe reconsider
//  after killing utils.output, but then again it doesn't matter & nobody cares
//xxx2 this is made for a dark background
void writeColoredLogEntry(scope void delegate(cstring) cb, LogEntry e,
    bool show_source)
{
    enum string[] cColorString = [
        LogPriority.Trace: "0000ff",
        LogPriority.Minor: "bbbbbb",
        LogPriority.Notice: "ffffff",
        LogPriority.Warn: "ffff00",
        LogPriority.Error: "ff0000"
    ];
    string c = "ffffff";
    if (indexValid(cColorString, e.pri))
        c = cColorString[e.pri];
    char[40] buffer;
    string source;
    if (show_source)
        source = myformat_s(buffer, "[%s] ", e.source.category);
    //the \litx prevents tag interpretation in msg
    auto msg = e.txt;
    myformat_cb(cb, "\\c(%s)%s\\litx(%s,%s)", c, source, msg.length, msg);
}

//Java style!
//write the backtrace (and possibly any other information we can get) to the
//  log, using Minor log level
//the idea is that, when catching an exception, you:
//  1. log a human readable error message with LogPriority.Error to the screen
//  2. spam the logfile with the precious backtrace using this function
void traceException(Log dest, Exception e, string what = "") {
    if (e) {
        string buffer;
        buffer ~= "Exception backtrace";
        if (what.length)
            buffer ~= " (" ~ what ~ ")";
        buffer ~= ":\n";
        //XXXTANGO e.writeOut( (string txt) { buffer ~= txt; } );
        dest.minor("%s", e);
        buffer ~= "Backtrace end.\n";
        dest.minor("%s", buffer);
    } else {
        dest.minor("error: no error");
    }
}
