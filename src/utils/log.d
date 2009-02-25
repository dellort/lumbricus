module utils.log;

import utils.output;
import utils.time;
import utils.misc : va_list;

/// Access to all Log objects created so far.
Log[char[]] gAllLogs;
RedirectOutput gDefaultOutput;
RedirectOutput gLogEverything;
Log gDefaultLog;

static this() {
    gDefaultOutput = new RedirectOutput(StdioOutput.output);
    gDefaultLog = registerLog("unknown");
    gLogEverything = new RedirectOutput(DevNullOutput.output);
}

/// Generic logging class. Implements interface Output, and all lines of text
/// written to it are prefixed with a descriptive header.
public final class Log : Output {
    private char[] mCategory;

    Output backend;
    char[] backend_name;
    bool stfu;
    bool show_time = true;

    public this(char[] category) {
        mCategory = category;
        setBackend(gDefaultOutput, "default");

        gAllLogs[category] = this;
    }

    void setBackend(Output backend, char[] backend_name) {
        this.backend = backend;
        this.backend_name = backend_name;
        stfu = false;
    }

    //makes it completely silent, will not even write into logall.txt
    //this also should make all logging calls zero-cost
    void shutup() {
        stfu = true;
    }

    char[] category() {
        return mCategory;
    }

    override void writef(char[] fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    override void writefln(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }

    void writeString(char[] str) {
        if (stfu)
            return;

        assert(backend !is null);
        //same xxx as in writef_ind.writeTo
        backend.writeString(str);
        gLogEverything.writeString(str);
    }

    void opCall(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }

    override void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        if (stfu)
            return;

        void writeTo(Output o) {
            //xxx: to do it correctly, we had to scan the formatted string for
            //     newlines, and then prepend the time/category before each line
            if (show_time) {
                o.writef("[{}] ", timeCurrentTime());
            }
            o.writef("{}: ", mCategory);
            o.writef_ind(newline, fmt, arguments, argptr);
        }

        assert(backend !is null);
        writeTo(backend);
        writeTo(gLogEverything);
    }

    char[] toString() {
        return "Log: >" ~ mCategory ~ "<";
    }
}

/// Register a log-category. There's one Log object per category-string, i.e.
/// multiple calls with the same argument will return the same object.
public Log registerLog(char[] category) {
    auto log = findLog(category);
    if (!log) {
        log = new Log(category);
        //log.setBackend(StdioOutput.output, "null");
    }
    return log;
}

public Log findLog(char[] category) {
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

    void opCall(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }

    void setBackend(Output backend, char[] backend_name) {
        check();
        mLog.setBackend(backend, backend_name);
    }

    char[] category() {
        return cId;
    }

    void writef(char[] fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    void writefln(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }

    void writeString(char[] str) {
        check();
        mLog.writeString(str);
    }

    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        check();
        mLog.writef_ind(newline, fmt, arguments, argptr);
    }
}
