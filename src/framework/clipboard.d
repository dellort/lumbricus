module framework.clipboard;

interface ClipboardHandler {
    //make the passed text available to the clipboard
    //clipboard:
    //  true: the "hard" clipboard (mostly using the key shortcuts)
    //  false: the clipboard for the mouse (selecting text, middle mouse button)
    //Windows has only clipboard=true, and clipboard=false calls are ignored
    void copyText(bool clipboard, string text);
    //request text from the clipboard; cb() will be called with the clipboard
    //  text as soon as the other application currently holding the clipboard
    //  contents reacts (which may be never)
    //when cb() is actually called:
    //  Windows: immediately by this function
    //  Linux: somewhere from the framework event loop
    void pasteText(bool clipboard, void delegate(string text) cb);
    //remove the callback set by pasteText(); rarely needed because the callback
    //  gets automatically removed when it is called.
    void pasteCancel(void delegate(string text) cb);
}

ClipboardHandler gClipboardHandler;

//basically this class only checks for null gClipboardHandler
//also: emulate a process-local clipboard
class Clipboard {
static:
    string[2] gLocalClipboard;

    void copyText(bool clipboard, string text) {
        if (gClipboardHandler) {
            gClipboardHandler.copyText(clipboard, text);
        } else {
            gLocalClipboard[clipboard ? 1 : 0] = text;
        }
    }
    void pasteText(bool clipboard, void delegate(string text) cb) {
        if (gClipboardHandler) {
            gClipboardHandler.pasteText(clipboard, cb);
        } else {
            cb(gLocalClipboard[clipboard ? 1 : 0]);
        }
    }
    void pasteCancel(void delegate(string text) cb) {
        if (gClipboardHandler)
            gClipboardHandler.pasteCancel(cb);
    }
}
