module gui.label;

import gui.widget;
import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import utils.misc;

class Label : Widget {
    private {
        char[] mText;
        Font mFont;
        Vector2i mBorder;
        bool mShrink;
        Texture mImage;
        BoxProperties mBorderStyle;
        bool mDrawBorder;
        //calculated by layoutSizeRequest
        Vector2i mFinalBorderSize;
    }

    void image(Texture img) {
        mImage = img;
        needResize(true);
    }
    Texture image() {
        return mImage;
    }

    void borderStyle(BoxProperties style) {
        mBorderStyle = style;
        needResize(true);
    }
    BoxProperties borderStyle() {
        return mBorderStyle;
    }

    override Vector2i layoutSizeRequest() {
        auto csize = mFont.textSize(mText);
        if (mImage) {
            csize = csize.max(mImage.size);
        }
        if (mShrink) {
            csize.x = 0;
        }
        mFinalBorderSize = border;
        if (mDrawBorder) {
            auto corner = mBorderStyle.cornerRadius/2;
            mFinalBorderSize += Vector2i(mBorderStyle.borderWidth + corner);
        }
        return csize + mFinalBorderSize*2;
    }

    void drawBorder(bool set) {
        mDrawBorder = set;
        needResize(true);
    }
    bool drawBorder() {
        return mDrawBorder;
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

    //(invisible!) border around text (additional to the box)
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
        mBorder = Vector2i(0,0);
    }

    override void onDraw(Canvas canvas) {
        auto b = mFinalBorderSize;
        if (drawBorder) {
            drawBox(canvas, widgetBounds, mBorderStyle);
        }
        if (mImage) {
            canvas.draw(mImage, b);
        }
        if (!mShrink) {
            mFont.drawText(canvas, b, mText);
        } else {
            auto sz = size;
            sz -= b*2;
            mFont.drawTextLimited(canvas, b, sz.x, mText);
        }
    }
}
