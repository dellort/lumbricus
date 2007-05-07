module utils.output;

import std.format;
import std.utf;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
public interface Output {
    void writef(...);
    void writefln(...);
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr);
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
