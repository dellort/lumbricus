module utils.output;

import utils.misc;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
//xxx maybe replace this interface by a handy class, so the number of interface
//functions could be kept to a minimum (i.e. only writeString())
public interface Output {
    void writef(string fmt, ...);
    void writefln(string fmt, ...);
    void writef_ind(bool newline, string fmt, TypeInfo[] arguments,
        va_list argptr);
    void writeString(string str);
}

/// A helper for implementers only, users shall use interface Output instead.
/// implements everything except writeString
public class OutputHelper : Output {
    char[200] buffer;

    void writef(string fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    void writefln(string fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }
    void writef_ind(bool newline, string fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        writeString(myformat_s_fx(buffer, fmt, arguments, argptr));
        if (newline)
            writeString("\n");
    }
    abstract void writeString(string str);
}

/// Implements the Output interface and writes all text into a string variable.
public class StringOutput : OutputHelper {
    /// All text written to the Output interface is appended to this
    public string text;
    void writeString(string str) {
        text ~= str;
    }
}
