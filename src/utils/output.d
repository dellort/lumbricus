module utils.output;

import std.format;
import std.utf;

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

//another small nasty helper: writes all output into a string
public class StringOutput : Output {
    public char[] text;

    void writef(...) {
        writef_ind(false, _arguments, _argptr);
    }
    void writefln(...) {
        writef_ind(true, _arguments, _argptr);
    }
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        text ~= sformat_ind(newline, arguments, argptr);
    }
    void writeString(char[] str) {
        text ~= str;
    }
}

