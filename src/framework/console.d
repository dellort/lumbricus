module framework.console;

import framework.framework;
import framework.font;
import utils.time;
import utf = std.utf;
import utils.output;

public class Console : Output {
    //maximum entries the backlog stores
    //if backlog would grow larger, old entries are thrown away
    private const int BACKLOG_LENGTH = 30;

    //currently showing (1) or hiding (-1)
    private int mShowFlag;
    //console height, dropped down from top
    private int mHeight;
    //current height, considering sliding
    private int mCurHeight;
    //time for a full slide
    private Time mFadeinTime;
    //background color (no alpha, sry...)
    private Color mBackColor;
    //offset (pixels) from left border
    private int mBorderOffset;

    private Time mLastTime;
    //output font (from constructor)
    private Font mConsoleFont;
    //height of a line of text (with space)
    private int mLineHeight;

    //current input line
    private char[] mCurLine;
    //cursor position
    private int mCursorPos;

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
        mHeight = 300;
        mShowFlag = -1;
        mCurHeight = 0;
        mBorderOffset = 4;
        mFadeinTime = timeMsecs(150);
        mLastTime = gFramework.getCurrentTime();
        mBackColor = Color(0.5,0.5,0.5,0.5); //freaking alpha transparency!!!
        mConsoleFont = consoleFont;
        mLineHeight = consoleFont.properties.size + 3;
        mCurLine = "";
        mBackLogIdx = 0;
        mBackLogLen = 0;
        mScrollPos = 0;
    }

    public Color backcolor() {
        return mBackColor;
    }
    public void backcolor(Color col) {
        mBackColor = col;
    }

    ///call this every frame to draw console to the screen
    public void frame(Canvas scrCanvas) {
        Time dt;
        dt = gFramework.getCurrentTime() - mLastTime;

        //sliding console in/out
        if ((mShowFlag < 0 && mCurHeight > 0) || ((mShowFlag > 0 &&
            mCurHeight < mHeight)))
        {
            mCurHeight += mShowFlag * (dt * mHeight).msecs / mFadeinTime.msecs;
            if (mCurHeight > mHeight)
                mCurHeight = mHeight;
            if (mCurHeight < 0)
                mCurHeight = 0;
        }

        int renderWidth = scrCanvas.realSize.x - mBorderOffset*2;

        if (mCurHeight > 0) {
            //draw background rect
            scrCanvas.drawFilledRect(Vector2i(0,0),
                Vector2i(scrCanvas.realSize.x,mCurHeight),mBackColor);

            //draw output backlog
            //maximum number of lines that fits on the screen
            int cMaxLines = (mCurHeight-mLineHeight)/mLineHeight;
            for (int i = 0; i < mBackLogLen && i < cMaxLines; i++) {
                int idx = mBackLogIdx-i-1-mScrollPos;
                if (idx < 0)
                    idx += BACKLOG_LENGTH;
                if (idx >= 0)
                    renderTextLine(scrCanvas,mBackLog[idx],
                        Vector2i(mBorderOffset,mCurHeight-mLineHeight*(i+2)),
                        renderWidth);
            }
            char[] prompt = "> ";
            char[] cmdline = prompt~mCurLine;
            auto cmdsp = Vector2i(mBorderOffset, mCurHeight-mLineHeight);
            mConsoleFont.drawText(scrCanvas,cmdsp,cmdline);
            auto offs = mConsoleFont.textSize(cmdline[0..prompt.length+mCursorPos]);
            //the cursor
            scrCanvas.drawFilledRect(cmdsp+Vector2i(offs.x, 0), cmdsp+offs
                +Vector2i(1, 0), mConsoleFont.properties.fore);
        }

        mLastTime = gFramework.getCurrentTime();
    }

    private void renderTextLine(Canvas outCanvas, char[] text, Vector2i pos,
        int maxWidth)
    {
        mConsoleFont.drawText(outCanvas,pos,text);//utf.toUTF8(text));
        //xxx missing method to get drawn character width
        //foreach (dchar ch; text) {
        //    mConsoleFont.drawText(outCanvas,pos,utf.toUTF8(ch));
        //}
    }

    ///update cursor position (array index, e.g. 0 = del will remove first char)
    public void setCursorPos(int pos) {
        mCursorPos = pos;
    }

    ///set the input text (displayed on bottom)
    public void setCurLine(char[] line) {
        mCurLine = line;
    }

    ///i.e. reset the scorll state
    public void touchConsole() {
        //reset scroll state
        mScrollPos = 0;
    }

    void writef(...) {
        writef_ind(false, _arguments, _argptr);
    }
    void writefln(...) {
        writef_ind(true, _arguments, _argptr);
    }
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr) {
        writeString(sformat_ind(newline, arguments, argptr));
    }

    //NOTE: parses '\n's
    void writeString(char[] s) {
    restart:
        foreach (int index, char c; s) {
            if (c == '\n') {
                print(s[0..index]);
                s = s[index+1..$];
                goto restart; //sry was too lazy!
            }
        }
    }

    ///output one line of text, drawn on bottom-most position
    ///current text is moved up
    ///don't parse '\n's
    public void print(char[] line) {
        touchConsole();
        mBackLog[mBackLogIdx] = line;
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

    ///show console
    public void show() {
        mShowFlag = 1;
    }

    ///hide console
    public void hide() {
        mShowFlag = -1;
    }

    ///toggle display of console
    public void toggle() {
        mShowFlag = -mShowFlag;
    }

    ///get height (pixels)
    public int height() {
        return mHeight;
    }

    ///set height (pixels)
    public void height(int val) {
        mHeight = val;
    }

    public bool visible() {
        return mShowFlag == 1;
    }
}
