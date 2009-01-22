module stdx.varghelper;

version (Tango) {
    public import tango.stdc.stdarg : va_list;
} else {
    public import std.stdarg;
}

///return an array that maps each argument to a void*
///e.g. 3rd element: type=_arguments[2], ptr=getArgs(...etc...)[2]
///if storage is an array <= _arguments.length, it is sliced and used as return
///value
//adapted from
//http://dsource.org/projects/tango/docs/current/source/tango.text.convert.Layout.html
void*[] getArgs(TypeInfo[] arguments, void* argptr, void*[] storage = null) {
    version (GNU) {
        //helpful error message
        static assert(false, "don't use gdc, it sucks");
    }
    void*[] arglist;
    if (storage.length >= arguments.length) {
        //(setting length of arglist will only change the slice)
        arglist = storage;
    }
    arglist.length = arguments.length;
    foreach (i, arg; arguments) {
        arglist[i] = argptr;
        argptr += (arg.tsize + size_t.sizeof - 1) & ~ (size_t.sizeof - 1);
    }
    return arglist;
}
