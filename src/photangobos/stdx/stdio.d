
// Written in the D programming language.

/* Written by Walter Bright and Andrei Alexandrescu
 * www.digitalmars.com
 * Placed in the Public Domain.
 */

/********************************
 * Standard I/O functions that extend $(B std.c.stdio).
 * $(B std.c.stdio) is automatically imported when importing
 * $(B std.stdio).
 * Macros:
 *	WIKI=Phobos/StdStdio
 */

module stdx.stdio;

import stdx.format;

version (Tango) {
    import tango.io.Console;
    import stdx.utf;

    public import stdx.base;

    private
    void writefx(TypeInfo[] arguments, void* argptr, int newline=false)
    {
        void putcw(dchar c)
        {
            char[5] buffer = void;
            buffer[] = '\0';
            char[] s = buffer;
            encode_inplace(s, c);
            //xxx Cout doesn't work?
            printf("%s", buffer.ptr);
            //Cout(s);
        }

        stdx.format.doFormat(&putcw, arguments, argptr);
        if (newline) {
            putcw('\n');
            //Cout.flush();
        }
    }


    /***********************************
    * Arguments are formatted per the
    * $(LINK2 std_format.html#format-string, format strings)
    * and written to $(B stdout).
    */

    void writef(...)
    {
        writefx(_arguments, _argptr, 0);
    }

    /***********************************
    * Same as $(B writef), but a newline is appended
    * to the output.
    */

    void writefln(...)
    {
        writefx(_arguments, _argptr, 1);
    }
} else {
    public import std.stdio;
}


//yyy removed
//void fwritef(FILE* fp, ...)
//void fwritefln(FILE* fp, ...)
//char[] readln(FILE* fp = stdin)
//size_t readln(FILE* fp, inout char[] buf)
//size_t readln(inout char[] buf)
