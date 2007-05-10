module utils.log;

//make it simpler to rip out code without needing MyList
version = WithLists;

import utils.output;
import stdformat = std.format;
import stdio = std.stdio;

version (WithLists) {
    import utils.mylist;


    List!(Log) gAllLogs;

    static this() {
        gAllLogs = new List!(Log)(Log.node.getListNodeOffset());
    }
}

public class Log : Output {
    private char[] mCategory;
    Output backend;

    version (WithLists) {
        mixin ListNodeMixin node;
    }

    public this(char[] category, Output backend) {
        mCategory = category;
        this.backend = backend;

        version (WithLists) {
            gAllLogs.insert_tail(this);
        }
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
            stdio.writef("%s", c);
        }

        stdformat.doFormat(&putc, arguments, argptr);
        if (newline) {
            stdio.writefln();
        }
    }

    void writeString(char[] str) {
    	stdio.writef("%s", str);
    }

    static this() {
        output_stdio = new PseudoBackend();
    }
}

public Log registerLog(char[] category) {
    return new Log(category, PseudoBackend.output_stdio);
}
