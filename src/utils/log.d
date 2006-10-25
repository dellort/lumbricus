module utils.log;

import utils.output;
import stdformat = std.format;
import stdio = std.stdio;

public class Log : Output {
    private char[] mCategory;
    Output backend;

    public this(char[] category, Output backend) {
        mCategory = category;
        this.backend = backend;
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

    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        assert(backend);

        backend.writef(mCategory, ": ");
        backend.writef_ind(newline, arguments, argptr);
    }
}

//pseudo-backend to dump onto stdio
private class PseudoBackend : Output {
    package static PseudoBackend output_stdio;

    void writef(...) {
        writef_ind(false, _arguments, _argptr);
    }
    void writefln(...) {
        writef_ind(true, _arguments, _argptr);
    }

    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        void putc(dchar c) {
            stdio.writef(c);
        }

        stdformat.doFormat(&putc, arguments, argptr);
        if (newline) {
            stdio.writefln();
        }
    }

    static this() {
        output_stdio = new PseudoBackend();
    }
}

public Log registerLog(char[] category) {
    return new Log(category, PseudoBackend.output_stdio);
}
