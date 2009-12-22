module game.text;

import framework.framework;
import framework.font;
import gui.renderbox;
import gui.rendertext;
import utils.color;
import utils.misc;
import utils.reflection;
import utils.vector2;

//text display within the game
//does only the annoying and disgusting job of wrapping unserializable
//  FormattedText in a serializable class; if our design was a bit cleaner, we
//  wouldn't need this
//you must call saveStyle() to ensure the default font and borders are saved
//  (after you change it in the renderer directly)
//you must set the text with RenderText methods to be sure it is saved
class RenderText {
    private {
        struct Transient {
            FormattedText renderer;
        }
        Transient mT;
        char[] mMarkupText;
        BoxProperties mBorder;
        FontProperties mFont;
    }

    //if non-null, this is visible only if true is returned
    //remember that the delegate is called in a non-deterministic way
    bool delegate(RenderText) visibility;

    this() {
        //create on instantiation
        //not called on deserialization, but then it's handled on demand
        renderer();
    }
    this(ReflectCtor c) {
        c.transient(this, &mT);
    }

    char[] markupText() {
        return mMarkupText;
    }
    void markupText(char[] txt) {
        if (mMarkupText == txt)
            return;
        mMarkupText = txt.dup; //copy for more safety
        renderer.setMarkup(mMarkupText);
    }

    //do:
    //  markupText = format(fmt, ...);
    //the good thing about this method is, that it doesn't allocate memory if
    //  the text doesn't change => you can call this method every frame, even
    //  if nothing changes, without trashing memory
    void setFormatted(char[] fmt, ...) {
        char[80] buffer = void;
        //(markupText setter compares and then copies anyway)
        markupText = formatfx_s(buffer, fmt, _arguments, _argptr);
    }

    void saveStyle() {
        if (!mT.renderer)
            return;
        mBorder = renderer.border;
        mFont = renderer.font.properties;
    }

    //--- non-determinstic functions following here

    FormattedText renderer() {
        if (!mT.renderer) {
            mT.renderer = new FormattedText();
            mT.renderer.setBorder(mBorder);
            mT.renderer.font = gFontManager.create(mFont);
            mT.renderer.setMarkup(mMarkupText);
        }
        return mT.renderer;
    }

    void draw(Canvas c, Vector2i pos) {
        if (visible())
            renderer.draw(c, pos);
    }

    Vector2i size() {
        return renderer.textSize();
    }

    bool visible() {
        if (!visibility)
            return true;
        return visibility(this);
    }
}

