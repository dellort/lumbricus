module framework.clipboard;

version(Windows) {

import tango.sys.win32.UserGdi;
import tango.stdc.stringz : fromString16z;
import tutf = tango.text.convert.Utf;

class Clipboard {
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

        return tutf.toString(fromString16z(data));
    }

    static void setText(char[] text) {
        if (!OpenClipboard(null)) {
            return;
        }
        scope(exit) CloseClipboard();
        EmptyClipboard();

        wchar[] wtxt = tutf.toString16(text);
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
