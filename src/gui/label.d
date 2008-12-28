module gui.label;

import gui.widget;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import utils.configfile;
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
        int mTextHeight;

        const cSpacing = 3; //between images and text
    }

    Color background = {0,0,0,0};

    //no mouse events
    override bool onTestMouse(Vector2i) {
        return false;
    }

    void image(Texture img) {
        if (img is mImage)
            return;
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
        auto csize = mFont.textSize(mText,!mImage);
        mTextHeight = csize.y;
        if (mShrink) {
            csize.x = 0;
        }
        if (mImage) {
            csize.x += mImage.size.x + (mText.length ? cSpacing : 0);
            csize.y = max(csize.y, mImage.size.y);
        }
        mFinalBorderSize = border;
        if (mDrawBorder) {
            auto corner = mBorderStyle.cornerRadius/3;
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
        mFont = font ? font : gFramework.getFont("label_default");
        drawBorder = true;
        mBorder = Vector2i(0,0);
    }

    override void onDraw(Canvas canvas) {
        if (background.a >= Color.epsilon) {
            canvas.drawFilledRect(Vector2i(0), size, background);
        }
        auto b = mFinalBorderSize;
        if (drawBorder) {
            drawBox(canvas, widgetBounds, mBorderStyle);
        }
        //xxx replace manual centering code etc. by sth. automatic
        auto diff = size - b*2;
        int x = b.x;
        if (mImage) {
            auto s = size - b*2;
            if (mText.length)
                s.x = mImage.size.x;
            auto ipos = b + s/2 - mImage.size/2;
            canvas.draw(mImage, ipos);
            x = ipos.x + mImage.size.x + cSpacing;
        }
        if (!mText.length)
            return;
        Vector2i p = Vector2i(x, b.y);
        p.y = p.y + diff.y/2 - mTextHeight/2;
        if (!mShrink) {
            mFont.drawText(canvas, p, mText);
        } else {
            mFont.drawTextLimited(canvas, p, (size-b*2-p).x, mText);
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto fnt = gFramework.fontManager.loadFont(
            node.getStringValue("font"), false);
        if (fnt)
            mFont = fnt;

        mText = loader.locale()(node.getStringValue("text", mText));
        parseVector(node.getStringValue("border"), mBorder);
        mShrink = node.getBoolValue("shrink", mShrink);
        mDrawBorder = node.getBoolValue("draw_border", mDrawBorder);

        auto bnode = node.findNode("border_style");
        if (bnode)
            mBorderStyle.loadFrom(bnode);

        //xxx: maybe also load image

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("label");
    }
}
