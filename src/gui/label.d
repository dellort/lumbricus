module gui.label;

import gui.global;
import gui.styles;
import gui.widget;
import gui.renderbox;
import gui.rendertext;
import framework.framework;
import framework.font;
import framework.i18n;
import utils.configfile;
import utils.misc;

class Label : Widget {
    private {
        FormattedText mText;
        bool mShrink, mCenterX;
        Surface mImage;
        //calculated by layoutSizeRequest
        Vector2i mTextSize;

        bool mFontOverride;

        const cSpacing = 3; //between images and text
    }

    this() {
        focusable = false;
        mText = new FormattedText();
    }

    //no mouse events
    override bool onTestMouse(Vector2i) {
        return false;
    }

    void image(Surface img) {
        if (img is mImage)
            return;
        mImage = img;
        needResize();
    }
    Surface image() {
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
        return csize;
    }

    void text(char[] txt) {
        setText(false, txt);
    }
    void textMarkup(char[] txt) {
        setText(true, txt);
    }
    char[] text() {
        char[] txt;
        bool is_markup;
        mText.getText(is_markup, txt);
        return txt;
    }
    //txt can become invalid after this function is called
    void setText(bool as_markup, char[] txt) {
        setTextFmt(as_markup, "{}", txt);
    }
    //like FormattedText.setTextFmt()
    void setTextFmt(bool as_markup, char[] fmt, ...) {
        setTextFmt_fx(as_markup, fmt, _arguments, _argptr);
    }
    void setTextFmt_fx(bool as_markup, char[] fmt,
        TypeInfo[] arguments, va_list argptr)
    {
        if (mText.setTextFmt_fx(as_markup, fmt, arguments, argptr)) {
            //text was changed; possibly relayout
            needResize();
        }
    }

    void font(Font font) {
        assert(font !is null);
        if (font is mText.font || font.properties == mText.font.properties)
            return;
        //xxx I don't know... styles stuff kinda sucks
        //    ^ "make it better"
        mFontOverride = true;
        mText.font = font;
        needResize();
    }

    Font font() {
        return mText.font;
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
        needResize();
    }

    override void onDraw(Canvas canvas) {
        //xxx replace manual centering code etc. by sth. automatic
        int x = 0;
        if (mImage) {
            auto s = size;
            //(mText.size.x was text.length)
            if (mText.size.x)
                s.x = mImage.size.x;
            auto ipos = s/2 - mImage.size/2;
            canvas.draw(mImage, ipos);
            x = ipos.x + mImage.size.x + cSpacing;
        }
        Vector2i p = Vector2i(x, 0);
        if (mCenterX && mTextSize.x <= size.x)
            p = p + size/2 - mTextSize/2;
        else
            p.y = p.y + size.y/2 - mTextSize.y/2;
        //xxx need replacement for drawTextLimited
        //    FormattedText should do this all by itself
        //if (!mShrink) {
            mText.draw(canvas, p);
        //} else {
        //    mFont.drawTextLimited(canvas, p, (size-b*2-p).x, text);
        //}
    }

    override void readStyles() {
        super.readStyles();
        if (!mFontOverride) {
            auto props = styles.get!(FontProperties)("text-font");
            //NOTE: not assigning to "font", because that triggers a resize
            mText.font = gFontManager.create(props);
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mText.clear();

        //xxx: it would be simpler to read the "locale" field directly, and
        //     then just concatenate it with the "text" value
        mText.translator = loader.locale();

        //haw haw... but it's ok?
        setTextFmt(true, r"\t({})", node.getStringValue("text"));

        mShrink = node.getBoolValue("shrink", mShrink);
        mCenterX = node.getBoolValue("center_x", mCenterX);

        char[] img = node.getStringValue("image");
        if (img.length > 0) {
            image = gGuiResources.get!(Surface)(img);
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("label");
    }
}
