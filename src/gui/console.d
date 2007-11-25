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
        CommandLine mCmdline;

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
    }

    final Output output() {
        return mLogWindow;
    }
    //"compatibility"
    final Output console() {
        return output();
    }
    final CommandLine cmdline() {
        return mCmdline;
    }

    override bool canHaveFocus() {
        return consoleVisible;
    }
    override bool greedyFocus() {
        return true;
    }

    private const cBorder = 4;

    //standalone: if false: hack to keep "old" behaviour of the system console
    this(bool standalone = true) {
        mBackColor = Color(0.5,0.5,0.5,0.5); //freaking alpha transparency!!!

        auto font = globals.framework.getFont(standalone
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
        if (!standalone && parseColor(globals.anyConfig.getSubNode("console")
            .getStringValue("backcolor"), console_color))
        {
            mBackColor = console_color;
            mDrawBackground = true;
        }

        mCmdline = new CommandLine(mLogWindow);

        mFadeinTime = timeMsecs(150);
        mLastTime = gFramework.getCurrentTime();
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
            Time dt = gFramework.getCurrentTime() - mLastTime;
            mOffset -= mShowFlag * (dt * mHeight).msecs / mFadeinTime.msecs;
            if (mOffset > mHeight)
                mOffset = mHeight;
            if (mOffset < 0)
                mOffset = 0;
        }

        changeHeight();

        mLastTime = gFramework.getCurrentTime();

        super.simulate();
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
