module framework.drivers.clipboard_win32;

//XXXTANGO ditched this
version(none):
version(Windows):

import framework.clipboard;
import tango.sys.win32.UserGdi;
import tango.stdc.stringz : fromString16z;
import tutf = tango.text.convert.Utf;
import str = utils.string;

//Windows clipboard implementation
class Win32Clipboard : ClipboardHandler {
    //first the functions for ClipboardHandler
    void copyText(bool clipboard, string text) {
        if (clipboard)
            setText(text);
    }
    void pasteText(bool clipboard, void delegate(string text) cb) {
        if (clipboard)
            cb(getText());
    }
    void pasteCancel(void delegate(string text) cb) {
    }

    //return text in the clipboard; if the format is not CF_UNICODETEXT,
    //  it will be converted by Windows if possible
    //returns empty string on error
    static string getText() {
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

        string ret = tutf.toString(fromString16z(data));
        //correct Windows newlines
        return str.replace(ret, "\r", "");
    }

    //put text into the clipboard as unicode text
    //xxx does nothing on error, maybe add exception
    static void setText(string text) {
        if (!OpenClipboard(null)) {
            return;
        }
        scope(exit) CloseClipboard();
        EmptyClipboard();

        wstring wtxt = tutf.toString16(text);
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

static this() {
    gClipboardHandler = new Win32Clipboard();
}
