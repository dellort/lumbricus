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

    bool drawBorder;

    override Vector2i layoutSizeRequest() {
        return mFont.textSize(mText) + border * 2;
    }

    void text(char[] txt) {
        mText = txt;
        needRelayout();
    }
    char[] text() {
        return mText;
    }

    void font(Font font) {
        assert(font !is null);
        mFont = font;
        needRelayout();
    }
    Font font() {
        return mFont;
    }

    //(invisible!) border around text
    void border(Vector2i b) {
        mBorder = b;
        needRelayout();
    }
    Vector2i border() {
        return mBorder;
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
        mFont.drawText(canvas, mBorder, mText);
    }
}
