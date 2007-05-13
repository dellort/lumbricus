module utils.output;

import std.format;
import std.utf;
import stdio = std.stdio;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
//xxx maybe replace this interface by a handy class, so the number of interface
//functions could be kept to a minimum (i.e. only writeString())
public interface Output {
    void writef(...);
    void writefln(...);
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr);
    void writeString(char[] str);
}

//small nasty helper
char[] sformat_ind(bool newline, TypeInfo[] arguments, void* argptr) {
    //xxx inefficient and stupid
    char[] ret;
    void putc(dchar c) {
        encode(ret, c);
    }
    doFormat(&putc, arguments, argptr);
    if (newline) putc('\n');
    return ret;
}

/// A helper for implementers only, users shall use interface Output instead.
public class OutputHelper : Output {
    void writef(...) {
        writef_ind(false, _arguments, _argptr);
    }
    void writefln(...) {
        writef_ind(true, _arguments, _argptr);
    }
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        writeString(sformat_ind(newline, arguments, argptr));
    }
    abstract void writeString(char[] str);
}

/// Implements the Output interface and writes all text to stdio.
public class StdioOutput : OutputHelper {
    public static Output output;

    void writeString(char[] str) {
    	stdio.writef("%s", str);
    }

    static this() {
        output = new StdioOutput();
    }
}

/// Implements the Output interface and writes all text into a string variable.
public class StringOutput : OutputHelper {
    /// All text written to the Output interface is appended to this
    public char[] text;
    void writeString(char[] str) {
        text ~= str;
    }
}

/// Implements the Output interface and throws away all text written to it.
public class DevNullOutput : OutputHelper {
    public static Output output;
    void writeString(char[] str) {
    }
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
    }

    static this() {
        output = new DevNullOutput();
    }
}

