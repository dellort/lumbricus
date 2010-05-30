//a glorified printf()
//not multithreading-safe
module utils.log;

import utils.strparser;
import utils.time;
import utils.misc;

import array = utils.array;
import str = utils.string;

import layout = tango.text.convert.Layout;

/// Access to all Log objects created so far.
Log[char[]] gAllLogs;

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
    //like Warning, but higher fatality (program may still continue, though)
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
    char[] txt;

    LogEntry dup() {
        LogEntry e = *this;
        e.txt = e.txt.dup;
        return e;
    }

    //some sort of default formatting
    void fmt(void delegate(char[]) sink) {
        //trying to keep heap activity down with that buffer thing
        char[80] buffer = void;
        myformat_cb(sink, "[{}] [{}] [{}] {}\n", time.toString_s(buffer),
            source.category, typeToString(pri), txt);
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
        char[] mName;
        bool mEnabled = true;
    }

    //all log events below that aren't passed to LogBackend.add()
    //NOTE: most Trace events will be invisible even if LogBackend.minPriority
    //  is set to Trace, because Log.minPriority is Minor by default
    LogPriority minPriority;

    this(char[] a_name, LogPriority a_minPriority, LogSink a_sink,
        bool add = true)
    {
        mName = a_name;
        minPriority = a_minPriority;
        mSink = a_sink;
        if (add)
            gLogBackends ~= this;
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

    char[] name() {
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
        void write(char[] s) { Trace.write(s); }
        e.fmt(&write);
    }
    gDefaultBackend = new LogBackend("def", LogPriority.Minor, &dump, false);
}

/// Generic logging class. Implements interface Output, and all lines of text
/// written to it are prefixed with a descriptive header.
final class Log {
    private {
        char[] mCategory;
        static array.Appender!(char) gBuffer;
    }

    //this is to selectively disable (potentially costly) Trace log calls
    LogPriority minPriority = LogPriority.Minor;

    //use registerLog()
    private this(char[] category) {
        mCategory = category;
        gAllLogs[category] = this;
    }

    //makes it completely silent, will not even write into logall.txt
    //this also should make all logging calls zero-cost
    void shutup() {
        minPriority = LogPriority.Minor;
    }

    char[] category() {
        return mCategory;
    }

    //same as calling trace(), mainly for compatibility
    void opCall(char[] fmt, ...) {
        emitx(LogPriority.Trace, fmt, _arguments, _argptr);
    }

    void trace(char[] fmt, ...) {
        emitx(LogPriority.Trace, fmt, _arguments, _argptr);
    }
    void minor(char[] fmt, ...) {
        emitx(LogPriority.Minor, fmt, _arguments, _argptr);
    }
    void notice(char[] fmt, ...) {
        emitx(LogPriority.Notice, fmt, _arguments, _argptr);
    }
    void warn(char[] fmt, ...) {
        emitx(LogPriority.Warn, fmt, _arguments, _argptr);
    }
    void error(char[] fmt, ...) {
        emitx(LogPriority.Error, fmt, _arguments, _argptr);
    }

    void emit(LogPriority pri, char[] fmt, ...) {
        emitx(pri, fmt, _arguments, _argptr);
    }

    void emitx(LogPriority pri, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
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
        void sink(char[] s) {
            gBuffer ~= s;
        }
        myformat_cb_fx(&sink, fmt, arguments, argptr);

        //distribute log event
        LogEntry e;
        e.pri = pri;
        e.source = this;
        e.time = timeCurrentTime();
        char[] txt = gBuffer[];
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

    char[] toString() {
        return "Log: >" ~ mCategory ~ "<";
    }
}

/// Register a log-category. There's one Log object per category-string, i.e.
/// multiple calls with the same argument will return the same object.
Log registerLog(char[] category) {
    auto log = findLog(category);
    if (!log) {
        log = new Log(category);
        //log.setBackend(StdioOutput.output, "null");
    }
    return log;
}

Log findLog(char[] category) {
    auto plog = category in gAllLogs;
    return plog ? *plog : null;
}

///Stupid proxy that allows to specify the log identifier with the declaration,
///and have the log created on demand, i.e.
///  private LogStruct!("mylog") log;
struct LogStruct(char[] cId) {
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

    char[] category() {
        return cId;
    }

    void emitx(LogPriority pri, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        check();
        mLog.emitx(pri, fmt, arguments, argptr);
    }

    //------ sigh... copied from Log
    void opCall(char[] fmt, ...) {
        emitx(LogPriority.Trace, fmt, _arguments, _argptr);
    }

    void trace(char[] fmt, ...) {
        emitx(LogPriority.Trace, fmt, _arguments, _argptr);
    }
    void minor(char[] fmt, ...) {
        emitx(LogPriority.Minor, fmt, _arguments, _argptr);
    }
    void notice(char[] fmt, ...) {
        emitx(LogPriority.Notice, fmt, _arguments, _argptr);
    }
    void warn(char[] fmt, ...) {
        emitx(LogPriority.Warn, fmt, _arguments, _argptr);
    }
    void error(char[] fmt, ...) {
        emitx(LogPriority.Error, fmt, _arguments, _argptr);
    }

    void emit(LogPriority pri, char[] fmt, ...) {
        emitx(pri, fmt, _arguments, _argptr);
    }
    //------
}
