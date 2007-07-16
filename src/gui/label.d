module gui.label;

import gui.widget;
import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import utils.misc;

//xxx: mostly duplicated from visual.d; maybe kill visual.d, the GUI is _here_
class GuiLabel : GuiObjectOwnerDrawn {
    private char[] mText;
    private Font mFont;
    private Vector2i mBorder;
    private bool mShrink;

    bool drawBorder;

    override Vector2i layoutSizeRequest() {
        auto size = mFont.textSize(mText) + border * 2;
        if (mShrink) {
            size.x = 0;
        }
        return size;
    }

    void text(char[] txt) {
        mText = txt;
        needResize(true);
    }
    char[] text() {
        return mText;
    }

    void font(Font font) {
        assert(font !is null);
        mFont = font;
        needResize(true);
    }
    Font font() {
        return mFont;
    }

    //(invisible!) border around text
    void border(Vector2i b) {
        mBorder = b;
        needResize(true);
    }
    Vector2i border() {
        return mBorder;
    }

    //if true, report size as 0 and then draw in a special way (see .draw())
    void shrink(bool s) {
        mShrink = s;
        needRelayout();
    }
    bool shrink() {
        return mShrink;
    }

    this(Font font = null) {
        mFont = font ? font : globals.framework.getFont("messages");
        drawBorder = true;
        mBorder = Vector2i(2,1);
    }

    override void draw(Canvas canvas) {
        if (drawBorder) {
            drawBox(canvas, Vector2i(0), size);
        }
        if (!mShrink) {
            mFont.drawText(canvas, mBorder, mText);
        } else {
            auto sz = size;
            sz -= mBorder*2;
            mFont.drawTextLimited(canvas, mBorder, size.x, mText);
        }
    }
}
