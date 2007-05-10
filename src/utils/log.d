module utils.log;

import utils.output;
import stdformat = std.format;
import stdio = std.stdio;

/// Access to all Log objects created so far.
Log[char[]] gAllLogs;

/// Generic logging class. Implements interface Output, and all lines of text
/// written to it are prefixed with a descriptive header.
public class Log : Output {
    private char[] mCategory;

    Output backend;

    public this(char[] category, Output backend) {
        mCategory = category;
        this.backend = backend;

        gAllLogs[category] = this;
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
    }
}

/// Register a log-category. There's one Log object per category-string, i.e.
/// multiple calls with the same argument will return the same object.
public Log registerLog(char[] category) {
    if (category in gAllLogs) {
        return gAllLogs[category];
    }
    return new Log(category, StdioOutput.output_stdio);
}
