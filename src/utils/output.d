module utils.output;

import stdx.format;
import stdx.utf;
import tango.io.Stdout;
import stdx.stream;
import utils.misc : formatfx, va_list;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
//xxx maybe replace this interface by a handy class, so the number of interface
//functions could be kept to a minimum (i.e. only writeString())
public interface Output {
    void writef(char[] fmt, ...);
    void writefln(char[] fmt, ...);
    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr);
    void writeString(char[] str);
}

char[] sformat_ind(bool newline, char[] fmt, TypeInfo[] arguments,
    va_list argptr)
{
    auto s = formatfx(fmt, arguments, argptr);
    if (newline)
        s ~= '\n';
    return s;
}

/// A helper for implementers only, users shall use interface Output instead.
public class OutputHelper : Output {
    void writef(char[] fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    void writefln(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }
    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        writeString(sformat_ind(newline, fmt, arguments, argptr));
    }
    abstract void writeString(char[] str);
}

/// Implements the Output interface and writes all text to stdio.
public class StdioOutput : OutputHelper {
    public static Output output;

    void writeString(char[] str) {
        Stdout(str).flush;
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

public class StreamOutput : OutputHelper {
    private Stream mTo;

    void writeString(char[] str) {
        if (mTo) {
            mTo.writeExact(str.ptr, str.length);
        }
    }

    this(Stream to) {
        mTo = to;
    }
}

/// Implements the Output interface and throws away all text written to it.
public class DevNullOutput : OutputHelper {
    public static Output output;
    void writeString(char[] str) {
    }
    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        void* argptr)
    {
    }

    static this() {
        output = new DevNullOutput();
    }
}

public class RedirectOutput : OutputHelper {
    Output destination;
    void writeString(char[] str) {
        if (destination)
            destination.writeString(str);
    }
    this(Output to) {
        destination = to;
    }
}
