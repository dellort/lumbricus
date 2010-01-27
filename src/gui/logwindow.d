module gui.logwindow;

import framework.framework;
import framework.font;
import gui.widget;
import utils.time;
import utils.output;
import utils.misc : min, max, va_list, formatfx;

import str = utils.string;

public class LogWindow : Widget, Output {
    //maximum entries the backlog stores
    //if backlog would grow larger, old entries are thrown away
    private {
        const int BACKLOG_LENGTH = 100;

        //output font (from constructor)
        Font mConsoleFont;
        //height of a line of text (with space)
        int mLineHeight;

        //backlog buffer
        struct BufferEntry {
            char[] text;
            Time timestamp;
        }
        BufferEntry[BACKLOG_LENGTH] mBackLog;
        //index into backlog pointing to next empty line
        int mBackLogIdx;
        //number of valid entries
        int mBackLogLen;
        //number of lines to scroll back
        int mScrollPos;
        //time after which old lines are faded out (0 to disable)
        Time mFadeDelay;
        //time over which to fade alpha from visible to invisible
        const cFadeTime = timeSecs(1);
    }

    //break lines on window width (primitive algorithm)
    //quite inefficient algorithm, which is why it can be deactivated here
    bool breakLines = true;

    ///initialize console, consoleFont will be used for rendering text
    public this(Font consoleFont = null) {
        focusable = false;
        font = consoleFont ? consoleFont : gFontManager.loadFont("console");
        mBackLogIdx = 0;
        mBackLogLen = 0;
        mScrollPos = 0;
    }

    void font(Font fnt) {
        mConsoleFont = fnt;
        mLineHeight = fnt.properties.size + 3;
    }

    void fadeDelay(Time delay) {
        mFadeDelay = delay;
    }
    Time fadeDelay() {
        return mFadeDelay;
    }

    void onDraw(Canvas scrCanvas) {
        //scope(exit) scrCanvas.setBlend(Color(1,1,1,1));
        Vector2i size = scrCanvas.clientSize;

        int renderWidth = size.x;

        //draw output backlog
        //xxx if BACKLOG_LENGTH is less than the number of lines that can be
        //  displayed on the screen, bad wrap-around occurs (looks fugly)
        auto height = size.y;
        int idx = mBackLogIdx-1-mScrollPos;
        int i = 0;
        auto cur = Vector2i(0, size.y);
        Time curTime = timeCurrentTime();
        while (cur.y > 0) {
            if (idx < 0)
                idx += BACKLOG_LENGTH;
            auto entry = mBackLog[idx];
            idx--;
            if (mFadeDelay != Time.Null) {
                //fade out (or hide entirely) old entries
                //(if enabled by setting fadeDelay)
                Time entryOverAge = curTime - entry.timestamp - mFadeDelay;
                if (entryOverAge > cFadeTime) {
                    //the entry is beyond display age, only older entries
                    //can follow
                    break;
                } else if (entryOverAge > Time.Null) {
                    //currently fading; entryOverAge is in [0; cFadeTime]
                    float delta = entryOverAge.secsf / cFadeTime.secsf;
                    //delta == 1.0f -> fully faded out
                    scrCanvas.setBlend(Color(1,1,1,1.0f - delta));
                }
            }
            if (!breakLines) {
                cur.y -= mLineHeight;
                mConsoleFont.drawText(scrCanvas, cur, entry.text);
            } else {
                //hurf hurf use the stack to save the text positions
                //(because we want to render the text from bottom to top, but
                //  break from top to bottom)
                //the first part is the symbol "Rightwards Arrow With Hook"
                const cBreaker = "\u21aa ";
                void bla(char[] txt, int frame) {
                    if (frame > 0 && (txt.length == 0 || cur.y < 0))
                        return;
                    int w = renderWidth;
                    //possibly prepend wrap-around symbol
                    if (frame > 0)
                        w -= mConsoleFont.textSize(cBreaker).x;
                    uint n = mConsoleFont.textFit(txt, w, true);
                    if (n == 0) {
                        //pathologic case, avoid infinite recursion
                        if (txt.length)
                            n = str.stride(txt, 0);
                    }
                    //output the bottom lines first
                    bla(txt[n..$], frame + 1);
                    //then ours
                    cur.y -= mLineHeight;
                    auto pos = cur;
                    if (frame > 0)
                        pos = mConsoleFont.drawText(scrCanvas, pos, cBreaker);
                    mConsoleFont.drawText(scrCanvas, pos, txt[0..n]);
                }
                bla(entry.text, 0);
            }
        }
    }

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
        writeString(formatfx(fmt, arguments, argptr));
        if (newline)
            writeString("\n");
    }

    private char[] mLineBuffer;

    //NOTE: parses '\n's
    //xxx might be inefficient; at least it's correct, unlike the last version
    void writeString(char[] s) {
        foreach (char c; s) {
            if (c == '\n') {
                println();
            } else if (c == '\t') {
                //wrap to next tab; fill with space
                int md = mLineBuffer.length % 8;
                md = md ? 8 - md : 1;
                while (md > 0) {
                    mLineBuffer ~= ' ';
                    md--;
                }
            } else {
                mLineBuffer ~= c;
            }
        }
    }

    private void println() {
        touchConsole();
        mBackLog[mBackLogIdx].text = mLineBuffer;
        mBackLog[mBackLogIdx].timestamp = timeCurrentTime();
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
        //reset entry visibility
        foreach (ref entry; mBackLog) {
            entry.timestamp = timeCurrentTime();
        }
    }

    ///clear backlog and output display
    ///input line is not touched
    public void clear() {
        touchConsole();
        mBackLogIdx = 0;
        mBackLogLen = 0;
        mBackLog[] = null;
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override bool onKeyDown(KeyInfo infos) {
        bool wd = infos.code == Keycode.MOUSE_WHEELDOWN;
        bool wu = infos.code == Keycode.MOUSE_WHEELUP;
        if (wd || wu) {
            scrollBack(wu ? +1 : -1);
            return true;
        }
        return false;
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto fnt = gFontManager.loadFont(node.getStringValue("font"), false);
        if (fnt)
            font = fnt;

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("logwindow");
    }
}
