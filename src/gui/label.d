module gui.label;

import gui.widget;
import common.common;
import common.scene;
import common.visual;
import framework.framework;
import framework.font;
import framework.i18n;
import utils.configfile;
import utils.misc;

class Label : Widget {
    private {
        TrCache mText;
        Font mFont;
        Vector2i mBorder;
        bool mShrink, mCenterX;
        Texture mImage;
        //calculated by layoutSizeRequest
        Vector2i mFinalBorderSize;
        Vector2i mTextSize;
        FontColors mFontColors;

        const cSpacing = 3; //between images and text
    }

    //disgusting hack etc...
    Color borderCustomColor = Color(0,0,0,0);
    bool borderColorIsBackground;
    override void get_border_style(ref BoxProperties b) {
        if (!(borderCustomColor.a > 0))
            return;
        if (borderColorIsBackground) {
            b.back = borderCustomColor;
        } else {
            b.border = borderCustomColor;
        }
    }

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

    override Vector2i layoutSizeRequest() {
        auto csize = mFont.textSize(mText.text, !mImage);
        mTextSize = csize;
        if (mShrink) {
            csize.x = 0;
        }
        if (mImage) {
            csize.x += mImage.size.x + (mText.text.length ? cSpacing : 0);
            csize.y = max(csize.y, mImage.size.y);
        }
        return csize + border*2;
    }

    void text(char[] txt) {
        if (txt == mText.text)
            return;
        mText.text = txt;
    }
    char[] text() {
        return mText.text;
    }

    void font(Font font) {
        assert(font !is null);
        mFont = font;
        needResize(true);
    }
    Font font() {
        return mFont;
    }

    void fontCustomColor(Color col) {
        mFontColors.fore = col;
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

    void centerX(bool c) {
        mCenterX = c;
    }
    bool centerX() {
        return mCenterX;
    }

    this(Font font = null) {
        mText = new TrCache();
        mText.onChange = &trTextChange;
        mFont = font ? font : gFramework.getFont("label_default");
        mBorder = Vector2i(0,0);
    }

    private void trTextChange(TrCache sender) {
        needResize(true);
    }

    override void onDraw(Canvas canvas) {
        auto b = border;
        //xxx replace manual centering code etc. by sth. automatic
        auto diff = size - b*2;
        int x = b.x;
        if (mImage) {
            auto s = size - b*2;
            if (mText.text.length)
                s.x = mImage.size.x;
            auto ipos = b + s/2 - mImage.size/2;
            canvas.draw(mImage, ipos);
            x = ipos.x + mImage.size.x + cSpacing;
        }
        if (!mText.text.length)
            return;
        Vector2i p = Vector2i(x, b.y);
        if (mCenterX && mTextSize.x <= diff.x)
            p = p + diff/2 - mTextSize/2;
        else
            p.y = p.y + diff.y/2 - mTextSize.y/2;
        if (!mShrink) {
            mFont.drawText(canvas, p, mText.text, mFontColors);
        } else {
            mFont.drawTextLimited(canvas, p, (size-b*2-p).x, mText.text,
                mFontColors);
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto fnt = gFramework.fontManager.loadFont(
            node.getStringValue("font"), false);
        if (fnt)
            mFont = fnt;

        mText.translator = loader.locale();
        mText.update(node.getStringValue("text"));
        parseVector(node.getStringValue("border"), mBorder);
        mShrink = node.getBoolValue("shrink", mShrink);
        mCenterX = node.getBoolValue("center_x", mCenterX);

        char[] img = node.getStringValue("image");
        if (img.length > 0) {
            image = globals.guiResources.get!(Surface)(img);
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("label");
    }
}
