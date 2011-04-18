//Linux + SDL + SDL X11 driver + X11
//(most dependencies come from glue code and initialization)
module framework.drivers.clipboard_x11;

version(linux):

import framework.clipboard;
import framework.sdl.sdl;
import derelict.sdl.sdl;
import utils.misc;

import str = utils.string;

//--- missing X11 specific definitions
//one could use full X11 bindings, but even then you'd have to edit the derelict
//  bindings to use them; that's all too much overhead and complication, so this
//  has to do

//ad-hoc bindings for all needed X11 stuff, mostly pasted from /usr/include/X11

import tango.stdc.config; //: c_ulong, c_long
import czstr = tango.stdc.stringz;
import tango.stdc.posix.dlfcn;

alias c_ulong XID;
alias XID Window;
alias c_ulong Atom;
alias c_ulong Time;

Atom XA_PRIMARY = 1;
Atom XA_ATOM = 4;
Atom XA_STRING = 31;
Time CurrentTime = 0;

alias int Bool;

struct Display;

enum {
    SelectionClear = 29,
    SelectionRequest = 30,
    SelectionNotify = 31,
};

struct XSelectionClearEvent {
    int type;
    c_ulong serial;   /* # of last request processed by server */
    Bool send_event;        /* true if this came from a SendEvent request */
    Display *display;       /* Display the event was read from */
    Window window;
    Atom selection;
    Time time;
}

struct XSelectionRequestEvent {
    int type;
    c_ulong serial;   /* # of last request processed by server */
    Bool send_event;        /* true if this came from a SendEvent request */
    Display *display;       /* Display the event was read from */
    Window owner;
    Window requestor;
    Atom selection;
    Atom target;
    Atom property;
    Time time;
}

struct XSelectionEvent {
    int type;
    c_ulong serial;   /* # of last request processed by server */
    Bool send_event;        /* true if this came from a SendEvent request */
    Display *display;       /* Display the event was read from */
    Window requestor;
    Atom selection;
    Atom target;
    Atom property;          /* ATOM or None */
    Time time;
}

union XEvent {
    int type;
    //most event types omitted (see Xlib.h)
    XSelectionClearEvent xselectionclear;
    XSelectionRequestEvent xselectionrequest;
    XSelectionEvent xselection;
    c_long[24] pad;
};


extern (C) {
    alias int function(Display*, char*, Bool) P_XInternAtom;
    alias int function(Display*, Atom, Window, Time) P_XSetSelectionOwner;
    alias int function(Display*, Atom, Atom, Atom, Window, Time)
        P_XConvertSelection;
    alias int function(Display*, Window, Atom, c_long, c_long, Bool, Atom,
        Atom*, int*, c_ulong*, c_ulong*, char**) P_XGetWindowProperty;
    alias int function(Display*, Window, Atom, Atom, int, int, char*, int)
        P_XChangeProperty;
    alias int function(Display*, Window, Bool, c_long, XEvent*) P_XSendEvent;
    alias int function(void*) P_XFree;
}

P_XInternAtom XInternAtom;
P_XSetSelectionOwner XSetSelectionOwner;
P_XConvertSelection XConvertSelection;
P_XGetWindowProperty XGetWindowProperty;
P_XChangeProperty XChangeProperty;
P_XSendEvent XSendEvent;
P_XFree XFree;

//fixed definitions for derelict.sdl, source: SDL_syswm.h

enum SDL_SYSWM_TYPE : int {
    SDL_SYSWM_X11 = 0,
}

struct SDL_SysWMmsg_ {
    SDL_version version_;
    SDL_SYSWM_TYPE subsystem;
    //(useless struct nesting from SDL_syswm.h omitted)
    XEvent xevent;
}

struct SDL_SysWMinfo_ {
    SDL_version version_;
    SDL_SYSWM_TYPE subsystem;
    //(useless struct nesting from SDL_syswm.h omitted)
    Display* display;
    Window window;
    extern(C) void function() lock_func;
    extern(C) void function() unlock_func;
    Window fswindow;
    Window wmwindow;
    Display* gfxdisplay;
}

//--- actual clipboard code
//this is mostly taken from FLTK (license is LGPL) and heavily edited

void delegate(string) gSelectionRequestor;
string[2] gSelectionBuffer;
bool[2] gIsOwnSelection;
string gPasteResult;

void* gXlib;
SDL_SysWMinfo_ gWMInfo;
Window gWindow;
Display* gDisplay;

Atom TARGETS, CLIPBOARD, TEXTPLAINUTF, TEXTPLAIN, XA_TEXT, UTF8_STRING;

void xlocked(void delegate() cb) {
    if (gWMInfo.lock_func) {
        gWMInfo.lock_func();
        cb();
        gWMInfo.unlock_func();
    } else {
        cb();
    }
}

public void copyText(bool clipboard, string text) {
    int buffer = clipboard ? 1 : 0;
    gSelectionBuffer[buffer] = text;
    gIsOwnSelection[buffer] = true;
    Atom property = clipboard ? CLIPBOARD : XA_PRIMARY;
    xlocked({
        XSetSelectionOwner(gDisplay, property, gWindow, CurrentTime);
    });
}

public void pasteText(bool clipboard, void delegate(string text) cb) {
    int buffer = clipboard ? 1 : 0;
    if (gIsOwnSelection[buffer]) {
        cb(gSelectionBuffer[buffer]);
        return;
    }
    gSelectionRequestor = cb;
    Atom property = clipboard ? CLIPBOARD : XA_PRIMARY;
    xlocked({
        XConvertSelection(gDisplay, property, TARGETS, property, gWindow,
            CurrentTime);
    });
}

public void pasteCancel(void delegate(string text) cb) {
    if (gSelectionRequestor == cb)
        gSelectionRequestor = null;
}

//called under xlocked
bool handle_xevent(XEvent* xevent) {
    switch (xevent.type) {
    case SelectionNotify: {
        if (!gSelectionRequestor)
            return false;
        if (!xevent.xselection.property)
            return true;
        string buffer;
        long read = 0;
        for (;;) {
            Atom actual; int format; c_ulong count, remaining;
            char* portion;
            //GDK source says deleting the property here causes race conditions,
            //  but apparently FLTK doesn't care => I don't care either
            if (XGetWindowProperty(gDisplay, xevent.xselection.requestor,
                xevent.xselection.property, read/4, 65536, 1, 0, &actual,
                &format, &count, &remaining, &portion))
            {
                break; // quit on error
            }
            if ((format == 32) && (actual == TARGETS || actual == XA_ATOM)) {
                Atom type = XA_STRING;
                // see if it offers a better type:
                for (c_ulong i = 0; i < count; i++) {
                    Atom t = (cast(Atom*)portion)[i];
                    if (t == TEXTPLAINUTF || t == TEXTPLAIN
                        || t == UTF8_STRING)
                    {
                        type = t;
                        break;
                    }
                    if (t == XA_TEXT) type = t;
                }
                XFree(portion);
                Atom property = xevent.xselection.property;
                XConvertSelection(gDisplay, property, type, property, gWindow,
                    CurrentTime);
                return true;
            }
            buffer ~= portion[0..count*format/8];
            read += count*format/8;

            XFree(portion);

            if (!remaining)
                break;
        }

        //use this outside this function, because we still hold some SDL
        //  specific lock for xlib; whatever that lock is, better don't call
        //  user code under it
        gPasteResult = buffer;

        return true;
    }
    case SelectionClear: {
        int buffer = xevent.xselectionclear.selection == CLIPBOARD ? 1 : 0;
        gIsOwnSelection[buffer] = false;
        return true;
    }
    case SelectionRequest: {
        XSelectionEvent e;
        e.type = SelectionNotify;
        e.requestor = xevent.xselectionrequest.requestor;
        e.selection = xevent.xselectionrequest.selection;
        e.target = xevent.xselectionrequest.target;
        e.time = xevent.xselectionrequest.time;
        e.property = xevent.xselectionrequest.property;
        int buffer = e.selection == CLIPBOARD ? 1 : 0;
        if (!gSelectionBuffer[buffer].length) {
            e.property = 0;
        } else if (e.target == TARGETS) {
            Atom a[3];
            a[0] = UTF8_STRING; a[1] = XA_STRING; a[2] = XA_TEXT;
            XChangeProperty(gDisplay, e.requestor, e.property,
                XA_ATOM, 32, 0, cast(char*)a.ptr, 3);
        } else if (e.target == UTF8_STRING || e.target == XA_STRING
            || e.target == XA_TEXT || e.target == TEXTPLAIN
            || e.target == TEXTPLAINUTF)
        {
            // clobber the target type, this seems to make some applications
            // behave that insist on asking for XA_TEXT instead of UTF8_STRING
            // Does not change XA_STRING as that breaks xclipboard.
            if (e.target != XA_STRING)
                e.target = UTF8_STRING;
            XChangeProperty(gDisplay, e.requestor, e.property, e.target, 8, 0,
                gSelectionBuffer[buffer].ptr, gSelectionBuffer[buffer].length);
        } else {
            e.property = 0;
        }
        XSendEvent(gDisplay, e.requestor, 0, 0, cast(XEvent*)&e);
        return true;
    }
    default:
        return false;
    }
    assert(false);
}

//--- end code stolen from FLTK

bool handle_event(SDL_Event* event) {
    bool res = false;
    if (event.type == SDL_SYSWMEVENT) {
        SDL_SysWMmsg_* event2 = cast(SDL_SysWMmsg_*)event.syswm.msg;
        if (event2.subsystem == SDL_SYSWM_TYPE.SDL_SYSWM_X11) {
            xlocked({
                res = handle_xevent(&event2.xevent);
            });
        }
    }

    if (gPasteResult) {
        string data = gPasteResult;
        auto sel = gSelectionRequestor;
        gPasteResult = null;
        gSelectionRequestor = null;
        if (sel) {
            data = str.sanitize(data);
            sel(data);
        }
    }

    return res;
}

void loadfuncs(T...)() {
    static if (T.length > 1) {
        loadfuncs!(T[1..$])();
    }
    static if (T.length == 0)
        return;
    //this is evil, but works... get the name the function as declared as
    //blame Walter for adding underspecified obscure features to his language
    const name = T[0].stringof;
    void* sym = dlsym(gXlib, czstr.toStringz(name));
    assert(!!sym, "symbol not found: "~name);
    //this also may be evil: assign the actual variable
    T[0] = cast(typeof(T[0]))sym;
}

bool load() {
    //NOTE: retarded derelict explicitly enables loading SDL_GetWMInfo only for
    //  Windows, so you have to edit the derelict sources to remove the
    //  "version(Windows)"; otherwise it will be null even after SDL is loaded
    if (!SDL_GetWMInfo)
        return false;
    SDL_SysWMinfo_ wminfo;
    SDL_VERSION(&wminfo.version_);
    if (SDL_GetWMInfo(cast(SDL_SysWMinfo*)&wminfo) != 1)
        return false; //failure
    if (wminfo.subsystem != SDL_SYSWM_TYPE.SDL_SYSWM_X11)
        return false;
    if (!wminfo.display)
        return false;

    SDL_EventState(SDL_SYSWMEVENT, SDL_ENABLE);

    //... load xlib functions
    //lumbricus doesn't get statically linked to xlib; only SDL is
    //although there's no real value in it, I wanted to keep it that way

    gXlib = dlopen("libX11.so.6", RTLD_NOW);
    if (!gXlib)
        return false;

    loadfuncs!(XInternAtom, XSetSelectionOwner, XConvertSelection,
        XGetWindowProperty, XChangeProperty, XSendEvent, XFree)();

    gWMInfo = wminfo;
    gDisplay = gWMInfo.display;
    gWindow = gWMInfo.window;
    assert(gDisplay);
    assert(gWindow);

    void atom(ref Atom a, string name) {
        a = XInternAtom(gDisplay, czstr.toStringz(name), 0);
    }

    atom(TARGETS, "TARGETS");
    atom(CLIPBOARD, "CLIPBOARD");
    atom(TEXTPLAINUTF, "text/plain;charset=UTF-8");
    atom(TEXTPLAIN, "text/plain");
    atom(XA_TEXT, "TEXT");
    atom(UTF8_STRING, "UTF8_STRING");

    return true;
}

void unload() {
    gWMInfo = gWMInfo.init;
    if (gXlib)
        dlclose(gXlib);
    gXlib = null;
}

void onVideoInit(bool is_loading) {
    if (is_loading) {
        if (load())
            gClipboardHandler = new Handler();
    } else {
        gClipboardHandler = null;
        unload();
    }
}

class Handler : ClipboardHandler {
    void copyText(bool a, string b) { .copyText(a, b); }
    void pasteText(bool a, void delegate(string) b) { .pasteText(a, b); }
    void pasteCancel(void delegate(string) a) { .pasteCancel(a); }
}

//loads itself when SDL is loaded
static this() {
    assert(!gOnSDLVideoInit);
    gOnSDLVideoInit = &onVideoInit;
    assert(!gSDLEventFilter);
    gSDLEventFilter = &handle_event;
}
