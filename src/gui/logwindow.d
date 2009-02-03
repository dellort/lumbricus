module gui.logwindow;

import framework.framework;
import framework.font;
import gui.widget;
import utils.time;
import utf = stdx.utf;
import utils.output;
import utils.misc : min, max, va_list;

public class LogWindow : Widget, Output {
    //maximum entries the backlog stores
    //if backlog would grow larger, old entries are thrown away
    private const int BACKLOG_LENGTH = 100;

    //output font (from constructor)
    private Font mConsoleFont;
    //height of a line of text (with space)
    private int mLineHeight;

    //backlog buffer
    private char[][BACKLOG_LENGTH]  mBackLog;
    //index into backlog pointing to next empty line
    private int mBackLogIdx;
    //number of valid entries
    private int mBackLogLen;
    //number of lines to scroll back
    private int mScrollPos;

    ///initialize console, consoleFont will be used for rendering text
    public this(Font consoleFont) {
        mConsoleFont = consoleFont;
        mLineHeight = consoleFont.properties.size + 3;
        mBackLogIdx = 0;
        mBackLogLen = 0;
        mScrollPos = 0;
    }

    void onDraw(Canvas scrCanvas) {
        Vector2i size = scrCanvas.clientSize;

        int renderWidth = size.x;

        //draw output backlog
        //maximum number of lines that fits on the screen
        auto height = size.y;
        int cMaxLines = min((height+mLineHeight-1)/mLineHeight,
            mBackLogLen - mScrollPos);
        for (int i = 0; i < cMaxLines; i++) {
            int idx = mBackLogIdx-i-1-mScrollPos;
            if (idx < 0)
                idx += BACKLOG_LENGTH;
            renderTextLine(scrCanvas,mBackLog[idx],
                Vector2i(0,height-mLineHeight*(i+1)), renderWidth);
        }
    }

    private void renderTextLine(Canvas outCanvas, char[] text, Vector2i pos,
        int maxWidth)
    {
        mConsoleFont.drawText(outCanvas,pos,text);
    }

    ///i.e. reset the scorll state
    public void touchConsole() {
        //reset scroll state
        mScrollPos = 0;
    }

    override void writef(char[] fmt, ...) {
        writef_ind(false, fmt, _arguments, _argptr);
    }
    override void writefln(char[] fmt, ...) {
        writef_ind(true, fmt, _arguments, _argptr);
    }
    override void writef_ind(bool newline, char[] fmt, TypeInfo[] arguments,
        va_list argptr)
    {
        writeString(sformat_ind(newline, fmt, arguments, argptr));
    }

    private char[] mLineBuffer;

    //NOTE: parses '\n's
    //xxx might be inefficient; at least it's correct, unlike the last version
    void writeString(char[] s) {
        foreach (char c; s) {
            if (c == '\n') {
                println();
            } else {
                mLineBuffer ~= c;
            }
        }
    }

    private void doprint(char[] text) {
        mLineBuffer ~= text;
    }

    private void println() {
        touchConsole();
        mBackLog[mBackLogIdx] = mLineBuffer;
        mLineBuffer = null;
        mBackLogIdx = (mBackLogIdx + 1) % BACKLOG_LENGTH;
        mBackLogLen++;
        if (mBackLogLen > BACKLOG_LENGTH)
            mBackLogLen = BACKLOG_LENGTH;
    }

    ///scroll backlog display back dLines > 0 lines
    ///dLines < 0 to scroll forward
    public void scrollBack(int dLines) {
        mScrollPos += dLines;
        if (mScrollPos < 0)
            mScrollPos = 0;
        if (mScrollPos >= mBackLogLen)
            mScrollPos = mBackLogLen-1;
    }

    ///clear backlog and output display
    ///input line is not touched
    public void clear() {
        touchConsole();
        mBackLogIdx = 0;
        mBackLogLen = 0;
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override protected void onKeyEvent(KeyInfo infos) {
        bool wd = infos.code == Keycode.MOUSE_WHEELDOWN;
        bool wu = infos.code == Keycode.MOUSE_WHEELUP;
        if (wd || wu) {
            if (infos.isDown()) {
                scrollBack(wu ? +1 : -1);
            }
        }
    }
}
