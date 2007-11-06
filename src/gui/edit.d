module gui.edit;

import framework.font;
import framework.framework;
import gui.widget;
import utils.array;
import utils.vector2;

///simple editline
//xxx ripped out violently from framework.commandline and .console
//    (minus history, tab completion and commandline-window)
class EditLine : Widget {
    private {
        char[] mCurline;
        uint mCursor;
        Font mFont;
    }

    this() {
        mFont = gFramework.getFont("editline");
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
            }
            return true;
        } else if (infos.code == Keycode.DELETE) {
            if (mCursor < mCurline.length) {
                int del = utf.stride(mCurline, mCursor);
                mCurline = mCurline[0 .. mCursor] ~ mCurline[mCursor+del .. $];
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
            return true;
        }
        return false;
    }

    override bool onKeyEvent(KeyInfo info) {
        if (info.isPress && handleKeyPress(info))
            return true;
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
        auto offs = mFont.textSize(mCurline[0..mCursor]);
        c.drawFilledRect(offs.X, offs + Vector2i(1, 0), mFont.properties.fore);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("editline");
    }
}
