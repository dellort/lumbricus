//stuff that was in object.d
module stdx.base;

//Walter loves printf, especially in unittests
debug {
    version (Tango) {
        public import tango.stdc.stdio : printf;
    } else {
        public import std.c.stdio : printf;
    }
}

version (Tango) {
    //xxx: va_arg doesn't work with LDC??
    public import tango.stdc.stdarg : va_list;

    //Tango doesn't define string (yet?)
    //Phobos defines it, although it's TOTALLY CRAPTISTICALLY USELESS

    alias char[] string;
    alias wchar[] wstring;
    alias dchar[] dstring;

} else {
    public import std.stdarg;
}

