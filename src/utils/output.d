module utils.output;

import utils.misc;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
//xxx maybe replace this interface by a handy class, so the number of interface
//functions could be kept to a minimum (i.e. only writeString())
public class Output {
    void writef(T...)(string fmt, T args) { writef_ind(false, fmt, args); }
    void writefln(T...)(string fmt, T args) { writef_ind(true, fmt, args); }
    void writef_ind(T...)(bool newline, string fmt, T args) {
        myformat_cb(&writeString, fmt, args);
        if (newline)
            writeString("\n");
    }
    abstract void writeString(in char[] str);
}

/// A helper for implementers only, users shall use interface Output instead.
/// implements everything except writeString
public class OutputHelper : Output {
    //abstract void writeString(string str);
}

/// Implements the Output interface and writes all text into a string variable.
public class StringOutput : OutputHelper {
    /// All text written to the Output interface is appended to this
    public string text;
    void writeString(string str) {
        text ~= str;
    }
}
