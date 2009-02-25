module gui.console;

import framework.commandline;
import framework.framework;
import framework.event;
import common.common;
import gui.boxcontainer;
import gui.container;
import gui.edit;
import gui.logwindow;
import gui.widget;
import utils.output;
import utils.time;

class GuiConsole : Container {
    private {
        CommandLine mRealCmdline;
        CommandLineInstance mCmdline;

        LogWindow mLogWindow;
        EditLine mEdit;
        BoxContainer mBox;
        bool mDrawBackground;
        //background color, if enabled
        Color mBackColor;

        int mHeightDiv;

        //currently showing (1) or hiding (-1)
        int mShowFlag;
        //current height, considering sliding
        int mOffset, mHeight;
        //time for a full slide
        Time mFadeinTime;
        Time mLastTime;
    }

    class ConsoleEditLine : EditLine {
        private void selHistory(int dir) {
            text = mCmdline.selectHistory(text, dir);
            cursorPos = text.length;
        }

        override protected bool handleKeyPress(KeyInfo infos) {
            if (infos.code == Keycode.TAB) {
                auto txt = text.dup;
                mCmdline.tabCompletion(txt, cursorPos,
                    (int start, int end, char[] ins) {
                        txt = txt[0..start] ~ ins ~ txt[end..$];
                        //set text and put cursor at end of completion
                        text = txt;
                        cursorPos = start + ins.length;
                    }
                );
            } else if (infos.code == Keycode.UP) {
                selHistory(-1);
            } else if (infos.code == Keycode.DOWN) {
                selHistory(+1);
            } else if (infos.code == Keycode.PAGEUP) {
                mLogWindow.scrollBack(+1);
            } else if (infos.code == Keycode.PAGEDOWN) {
                mLogWindow.scrollBack(-1);
            } else if (infos.code == Keycode.RETURN) {
                mCmdline.execute(text);
                text = null;
            } else {
                return super.handleKeyPress(infos);
            }
            return true;
        }

        //needs <tab> for autocompletion
        override protected bool usesTabKey() {
            return true;
        }
    }

    final Output output() {
        return mLogWindow;
    }
    //"compatibility"
    final Output console() {
        return output();
    }
    final CommandLine cmdline() {
        return mRealCmdline;
    }

    override bool canHaveFocus() {
        return consoleVisible;
    }
    override bool greedyFocus() {
        return true;
    }

    private const cBorder = 4;

    //standalone: if false: hack to keep "old" behaviour of the system console
    //cmdline: use that cmdline, if null create a new one
    this(bool standalone = true, CommandLine cmdline = null) {
        mBackColor = Color(0.5,0.5,0.5,0.5); //freaking alpha transparency!!!

        auto font = gFramework.getFont(standalone
            ? "sconsole" : "console");

        mHeightDiv = standalone ? 1 : 2;

        mLogWindow = new LogWindow(font);
        mEdit = new ConsoleEditLine();
        mEdit.font = font;
        mEdit.prompt = "> ";
        mBox = new BoxContainer(false);
        mBox.add(mLogWindow);
        mBox.add(mEdit, WidgetLayout.Expand(true));

        //how much should be visible => modify fill value of layout
        auto lay = mBox.layout();
        lay.fill[1] = 1.0f/mHeightDiv;
        lay.alignment[1] = 0;
        lay.pad = cBorder;
        mBox.setLayout(lay);

        consoleVisible = standalone; //system console hidden by default
        Color console_color;
        if (!standalone) {
            //(backcolor was once in anything.conf, if you want to make it
            // configurable again, find a clean solution!)
            mBackColor = Color(0.7, 0.7, 0.7, 0.7);
            mDrawBackground = true;
        }

        mRealCmdline = cmdline ? cmdline : new CommandLine(mLogWindow);
        mCmdline = new CommandLineInstance(mRealCmdline, mLogWindow);

        mFadeinTime = timeMsecs(150);
        mLastTime = timeCurrentTime();
    }

    private void changeHeight() {
        //0: normal, -height: totally invisible
        mBox.setAddToPos(Vector2i(0, -mOffset));
        bool visible = (mOffset != mHeight);
        if (visible != !!(mBox.parent)) {
            if (visible) {
                addChild(mBox);
                mEdit.claimFocus();
            } else {
                removeChild(mBox);
            }
        }
    }

    override void simulate() {
        //sliding console in/out
        if ((mShowFlag < 0 && mOffset < mHeight) || ((mShowFlag > 0 &&
            mOffset > 0)))
        {
            Time dt = timeCurrentTime() - mLastTime;
            mOffset -= mShowFlag * (dt * mHeight).msecs / mFadeinTime.msecs;
            if (mOffset > mHeight)
                mOffset = mHeight;
            if (mOffset < 0)
                mOffset = 0;
        }

        changeHeight();

        mLastTime = timeCurrentTime();

        super.simulate();
    }

    //catch all events
    override void onKeyEvent(KeyInfo infos) {
        mEdit.claimFocus();
    }

    override protected void layoutSizeAllocation() {
        bool reset = (mShowFlag < 0) && (mOffset == mHeight);
        mHeight = size.y/mHeightDiv; //similar height to mBox.size.y
        if (reset)
            mOffset = mHeight;
        super.layoutSizeAllocation();
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

    public bool consoleVisible() {
        return mShowFlag == 1;
    }

    ///force toggle/visibility state
    void consoleVisible(bool set) {
        if (set) {
            mShowFlag = 1;
            mOffset = 0;
        } else {
            mShowFlag = -1;
            mOffset = mHeight;
        }
        changeHeight();
    }

    override void onDraw(Canvas c) {
        //draw background rect
        bool ok = !!mBox.parent;
        if (ok && mDrawBackground) {
            auto rc = mBox.containedBounds();
            rc.extendBorder(Vector2i(cBorder)); //add border back, looks better
            rc += mBox.getAddToPos();
            c.drawFilledRect(rc.p1,rc.p2,mBackColor);
        }
        //draw children
        super.onDraw(c);
    }

    public Color backcolor() {
        return mBackColor;
    }
    public void backcolor(Color col) {
        mBackColor = col;
    }
}
