module gui.label;

import gui.widget;
import gui.styles;
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
        FormattedText mText;
        Vector2i mBorder;
        bool mShrink, mCenterX;
        Texture mImage;
        //calculated by layoutSizeRequest
        Vector2i mFinalBorderSize;
        Vector2i mTextSize;

        //only when set by the user
        bool mUserTextValid, mUserTextMarkup;
        char[] mUserText;
        bool mFontOverride;

        const cSpacing = 3; //between images and text
    }

    this() {
        focusable = false;
        styleRegisterString("text-font");
        mText = new FormattedText();
        mText.font = gFontManager.loadFont("label_default");
        mBorder = Vector2i(0,0);
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

    private Vector2i textSize() {
        return mText.textSize(!mImage);
    }

    override Vector2i layoutSizeRequest() {
        auto csize = textSize();
        mTextSize = csize;
        if (mShrink) {
            csize.x = 0;
        }
        if (mImage) {
            //(mText.size.x was mText.length)
            csize.x += mImage.size.x + (mText.size.x ? cSpacing : 0);
            csize.y = max(csize.y, mImage.size.y);
        }
        return csize + border*2;
    }

    void text(char[] txt) {
        setText(txt, false);
    }
    void textMarkup(char[] txt) {
        setText(txt, true);
    }
    char[] text() {
        //don't know, could also just add a mText.text and return that
        return mUserTextValid ? mUserText : "";
    }
    //txt can become invalid after this function is called
    void setText(char[] txt, bool as_markup) {
        if (mUserTextValid && mUserTextMarkup == as_markup && mUserText == txt)
            return;
        txt = txt.dup;
        mUserTextValid = true;
        mUserText = txt;
        mUserTextMarkup = as_markup;
        mText.setText(txt, as_markup);
        needResize(true);
    }

    void font(Font font) {
        assert(font !is null);
        if (font is mText.font || font.properties == mText.font.properties)
            return;
        //xxx I don't know... styles stuff kinda sucks
        mFontOverride = true;
        mText.font = font;
        needResize(true);
    }
    Font font() {
        return mText.font;
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

    override void onLocaleChange() {
        mText.update();
        needResize(true);
    }

    override void onDraw(Canvas canvas) {
        auto b = border;
        //xxx replace manual centering code etc. by sth. automatic
        auto diff = size - b*2;
        int x = b.x;
        if (mImage) {
            auto s = size - b*2;
            //(mText.size.x was text.length)
            if (mText.size.x)
                s.x = mImage.size.x;
            auto ipos = b + s/2 - mImage.size/2;
            canvas.draw(mImage, ipos);
            x = ipos.x + mImage.size.x + cSpacing;
        }
        //if (!text.length)
          //  return;
        Vector2i p = Vector2i(x, b.y);
        if (mCenterX && mTextSize.x <= diff.x)
            p = p + diff/2 - mTextSize/2;
        else
            p.y = p.y + diff.y/2 - mTextSize.y/2;
        //xxx need replacement for drawTextLimited
        //    FormattedText should do this all by itself
        //if (!mShrink) {
            mText.draw(canvas, p);
        //} else {
        //    mFont.drawTextLimited(canvas, p, (size-b*2-p).x, text);
        //}
    }

    override protected void check_style_changes() {
        super.check_style_changes();
        if (!mFontOverride) {
            char[] fontId = styles.getValue!(char[])("text-font");
            font = gFontManager.loadFont(fontId);
            mFontOverride = false;
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mUserTextValid = false;
        mText.clear();

        //xxx: it would be simpler to read the "locale" field directly, and
        //     then just concatenate it with the "text" value
        mText.translator = loader.locale();

        //haw haw... but it's ok?
        mText.setMarkup(r"\t(" ~ node.getStringValue("text") ~ ")");
        mText.update();

        mBorder = node.getValue("border", mBorder);
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
