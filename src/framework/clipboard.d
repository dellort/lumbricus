module framework.clipboard;

version(Windows) {

import tango.sys.win32.UserGdi;
import tango.stdc.stringz : fromString16z;
import tutf = tango.text.convert.Utf;
import str = utils.string;

//Windows clipboard implementation
class Clipboard {
    //return text in the clipboard; if the format is not CF_UNICODETEXT,
    //  it will be converted by Windows if possible
    //returns empty string on error
    static char[] getText() {
        if (!OpenClipboard(null)) {
            return null;
        }
        scope(exit) CloseClipboard();

        HANDLE hData = GetClipboardData(CF_UNICODETEXT);
        if (hData == null) {
            return null;
        }

        wchar* data = cast(wchar*)GlobalLock(hData);
        if (data == null) {
            return null;
        }
        scope(exit) GlobalUnlock(hData);

        char[] ret = tutf.toString(fromString16z(data));
        //correct Windows newlines
        return str.replace(ret, "\r", "");
    }

    //put text into the clipboard as unicode text
    //xxx does nothing on error, maybe add exception
    static void setText(char[] text) {
        if (!OpenClipboard(null)) {
            return;
        }
        scope(exit) CloseClipboard();
        EmptyClipboard();

        wchar[] wtxt = tutf.toString16(text);
        //ownership of this memory passes to Windows with the
        //  SetClipboardData() call
        HGLOBAL hGlobal = GlobalAlloc(GMEM_MOVEABLE, (wtxt.length + 1)
            * wchar.sizeof);
        if (!hGlobal) {
            return;
        }

        wchar* data = cast(wchar*)GlobalLock(hGlobal);
        assert(data);
        data[0..wtxt.length] = wtxt[0..$];
        data[wtxt.length] = '\0';
        GlobalUnlock(hGlobal);

        SetClipboardData(CF_UNICODETEXT, hGlobal);
    }

    static void clear() {
        if (!OpenClipboard(null)) {
            return;
        }
        scope(exit) CloseClipboard();
        EmptyClipboard();
    }
}

} // version(Windows)
else {

//Linux clipboard implementation
//xxx I don't think this will ever get implemented
class Clipboard {
    static char[] getText() {
        return null;
    }

    static void setText(char[] text) {
    }

    static void clear() {
    }
}

}
