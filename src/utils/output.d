module utils.output;

import utils.stream;
import utils.misc : formatfx_s, va_list, Trace;
import ic = tango.io.model.IConduit;

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

/// A helper for implementers only, users shall use interface Output instead.
/// implements everything except writeString
public class OutputHelper : Output {
    char[200] buffer;

    void writef(char[] fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    void writefln(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }
    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        writeString(formatfx_s(buffer, fmt, arguments, argptr));
        if (newline)
            writeString("\n");
    }
    abstract void writeString(char[] str);
}

public class PipeOutput : OutputHelper {
    PipeOut writer;

    this(PipeOut w) {
        writer = w;
    }

    void writeString(char[] str) {
        writer.write(cast(ubyte[])str);
    }
}

/// Implements the Output interface and writes all text to stdio.
public class StdioOutput : OutputHelper {
    public static Output output;

    void writeString(char[] str) {
        Trace.format("{}", str);
        //oh hell, format() doesn't seem to flush, WHAT IS THE POINT OF THIS?
        Trace.flush();
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
            mTo.writeExact(cast(ubyte[])str);
        }
    }

    this(Stream to) {
        mTo = to;
    }
}

public class TangoStreamOutput : OutputHelper {
    private ic.OutputStream mTo;

    void writeString(char[] str) {
        if (mTo) {
            mTo.write(str);
        }
    }

    this(ic.OutputStream to) {
        mTo = to;
    }
}

/// Implements the Output interface and throws away all text written to it.
public class DevNullOutput : Output {
    public static Output output;

    void writef(char[] fmt, ...) {}
    void writefln(char[] fmt, ...) {}
    void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr) {}
    void writeString(char[] str) {}

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
