module gui.label;

import gui.guiobject;
import game.common;
import game.scene;
import game.visual;
import framework.framework;
import framework.font;
import utils.misc;

//xxx: mostly duplicated from visual.d; maybe kill visual.d, the GUI is _here_
class GuiLabel : GuiObjectOwnerDrawn {
    private char[] mText;
    private Font mFont;
    private Vector2i mBorder;

    bool drawBorder;

    override void getLayoutConstraints(out LayoutConstraints lc) {
        lc.minSize = mFont.textSize(mText) + border * 2;
    }

    void text(char[] txt) {
        mText = txt;
        needRelayout();
    }
    char[] text() {
        return mText;
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
            drawBox(canvas, bounds.p1, size);
        }
        mFont.drawText(canvas, bounds.p1+mBorder, mText);
    }
}
