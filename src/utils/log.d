module utils.log;

import utils.output;
import stdformat = std.format;
import stdio = std.stdio;

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
public class Log : Output {
    private char[] mCategory;

    Output backend;
    char[] backend_name;

    public this(char[] category) {
        mCategory = category;
        setBackend(gDefaultOutput, "default");

        gAllLogs[category] = this;
    }

    void setBackend(Output backend, char[] backend_name) {
        this.backend = backend;
        this.backend_name = backend_name;
    }

    char[] category() {
        return mCategory;
    }

    void writef(...) {
        writef_ind(false, _arguments, _argptr);
    }
    void writefln(...) {
        writef_ind(true, _arguments, _argptr);
    }

    void writeString(char[] str) {
    	assert(backend !is null);

	backend.writeString(str);
    }

    void opCall(...) {
        writef_ind(true, _arguments, _argptr);
    }

    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        assert(backend !is null);

        backend.writef("%s: ", mCategory);
        backend.writef_ind(newline, arguments, argptr);

        gLogEverything.writef("%s: ", mCategory);
        gLogEverything.writef_ind(newline, arguments, argptr);
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
    if (category in gAllLogs) {
        return gAllLogs[category];
    }
    return null;
}
