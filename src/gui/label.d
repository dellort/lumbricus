module gui.label;

import gui.global;
import gui.styles;
import gui.widget;
import gui.renderbox;
import gui.rendertext;
import framework.drawing;
import framework.font;
import framework.i18n;
import framework.surface;
import utils.configfile;
import utils.misc;

class Label : Widget {
    private {
        FormattedText mText;
        bool mShrink, mCenterX;
        //calculated by layoutSizeRequest
        Vector2i mTextSize;

        bool mFontOverride;

        const cSpacing = 3; //between images and text
    }

    this() {
        focusable = false;
        isClickable = false;
        doClipping = true;
        mText = new FormattedText();
    }

    final FormattedText renderer() {
        return mText;
    }

    override Vector2i layoutSizeRequest() {
        auto csize = mText.textSize();
        mTextSize = csize;
        if (mShrink) {
            csize.x = 0;
        }
        return csize;
    }

    override void layoutSizeAllocation() {
        mText.setArea(size, mCenterX ? 0 : -1, 0);
    }

    void text(string txt) {
        setText(false, txt);
    }
    void textMarkup(string txt) {
        setText(true, txt);
    }
    string text() {
        string txt;
        bool is_markup;
        mText.getText(is_markup, txt);
        return txt;
    }
    //txt can become invalid after this function is called
    void setText(bool as_markup, string txt) {
        setTextFmt(as_markup, "%s", txt);
    }
    //like FormattedText.setTextFmt()
    void setTextFmt(T...)(bool as_markup, string fmt, T args) {
        if (mText.setTextFmt(as_markup, fmt, args)) {
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
        needResize();
    }
    bool shrink() {
        return mShrink;
    }

    void centerX(bool c) {
        mCenterX = c;
        needResize();
    }
    bool centerX() {
        return mCenterX;
    }

    override void onLocaleChange() {
        mText.update();
        needResize();
    }

    override void onDraw(Canvas canvas) {
        mText.draw(canvas, Vector2i(0));
    }

    override void readStyles() {
        super.readStyles();
        if (!mFontOverride) {
            //NOTE: not assigning to "font", because that triggers a resize
            mText.font = styles.get!(Font)("text-font");
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        mText.clear();

        //xxx: it would be simpler to read the "locale" field directly, and
        //     then just concatenate it with the "text" value
        mText.translator = loader.locale();

        //haw haw... but it's ok?
        setTextFmt(true, r"\t(%s)", node.getStringValue("text"));

        mShrink = node.getBoolValue("shrink", mShrink);
        mCenterX = node.getBoolValue("center_x", mCenterX);

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("label");
    }
}

class ImageLabel : Widget {
    private {
        Surface mImage;
    }

    this() {
        focusable = false;
        isClickable = false;
    }

    this(Surface img) {
        this();
        image = img;
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

    override Vector2i layoutSizeRequest() {
        return mImage ? mImage.size : Vector2i(0);
    }

    override void onDraw(Canvas canvas) {
        if (mImage)
            canvas.draw(mImage, size/2 - mImage.size/2);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("imagelabel");
    }
}
