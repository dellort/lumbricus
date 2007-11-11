module gui.edit;

import framework.font;
import framework.framework;
import gui.widget;
import utils.array;
import utils.time;
import utils.timer;
import utils.vector2;

///simple editline
//xxx ripped out violently from framework.commandline and .console
//    (minus history, tab completion and commandline-window)
class EditLine : Widget {
    private {
        char[] mCurline;
        uint mCursor;
        Font mFont;
        bool mCursorVisible = true;
        Timer mCursorTimer;
    }

    ///text line has changed (not called when assigned to text)
    void delegate(EditLine sender) onChange;

    this() {
        mFont = gFramework.getFont("editline");
        mCursorTimer = new Timer(timeMsecs(500), &onTimer);
    }

    private bool handleKeyPress(KeyInfo infos) {
        if (infos.code == Keycode.RIGHT) {
            if (mCursor < mCurline.length)
                mCursor = charNext(mCurline, mCursor);
            return true;
        } else if (infos.code == Keycode.LEFT) {
            if (mCursor > 0)
                mCursor = charPrev(mCurline, mCursor);
            return true;
        } else if (infos.code == Keycode.BACKSPACE) {
            if (mCursor > 0) {
                int del = mCursor - charPrev(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor-del] ~ mCurline[mCursor .. $];
                mCursor -= del;
                doOnChange();
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (mCursor < mCurline.length) {
                int del = utf.stride(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor] ~ mCurline[mCursor+del .. $];
                doOnChange();
            }
            return true;
        } else if (infos.code == Keycode.HOME) {
            mCursor = 0;
            return true;
        } else if (infos.code == Keycode.END) {
            mCursor = mCurline.length;
            return true;
        } else if (infos.isPrintable()) {
            //printable char
            char[] append;
            if (!utf.isValidDchar(infos.unicode)) {
                append = "?";
            } else {
                append = utf.toUTF8([infos.unicode]);
            }
            mCurline = mCurline[0 .. mCursor] ~ append ~ mCurline[mCursor .. $];
            mCursor += utf.stride(mCurline, mCursor);
            doOnChange();
            return true;
        }
        return false;
    }

    private void doOnChange() {
        if (onChange)
            onChange(this);
    }

    override bool onKeyEvent(KeyInfo info) {
        if (info.isPress && handleKeyPress(info)) {
            //make cursor visible when a keypress was handled
            mCursorVisible = true;
            mCursorTimer.reset();
            return true;
        }
        if (info.isMouseButton) { //take focus when clicked
            claimFocus();
            return true;
        }
        return super.onKeyEvent(info);
    }

    override Vector2i layoutSizeRequest() {
        return mFont.textSize("hallo");
    }

    override bool canHaveFocus() {
        return true;
    }

    override void onDraw(Canvas c) {
        mFont.drawText(c, Vector2i(0), mCurline);
        if (focused) {
            mCursorTimer.enabled = true;
            if (mCursorVisible) {
                auto offs = mFont.textSize(mCurline[0..mCursor]);
                c.drawFilledRect(offs.X, offs + Vector2i(1, 0),
                    mFont.properties.fore);
            }
            mCursorTimer.update();
        } else {
            mCursorVisible = true;
            mCursorTimer.enabled = false;
        }
    }

    private void onTimer(Timer sender) {
        mCursorVisible = !mCursorVisible;
    }

    public char[] text() {
        return mCurline;
    }
    public void text(char[] newtext) {
        mCurline = newtext;
        mCursor = 0;
    }

    public uint cursorPos() {
        return mCursor;
    }
    public void cursorPos(uint newPos) {
        mCursor = newPos;
        if (mCursor > mCurline.length)
            mCursor = mCurline.length;
    }

    static this() {
        WidgetFactory.register!(typeof(this))("editline");
    }
}
