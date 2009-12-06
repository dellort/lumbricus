module game.text;

import common.visual;
import framework.framework;
import framework.font;
import game.game;
import game.controller;
import utils.color;
import utils.misc;
import utils.reflection;
import utils.vector2;

//text display within the game
//does onbly the annoying and disgusting job of wrapping unserializable
//  FormattedText in a serializable class; if our design was a bit cleaner, we
//  wouldn't need this
class RenderText {
    private {
        GameEngine mEngine;
        struct Transient {
            FormattedText renderer;
        }
        Transient mT;
        char[] mMarkupText;
        BoxProperties mBorder;
        Color mFontColor;
    }

    //if non-null, this is visible only if true is returned
    bool delegate(TeamMember t) visibility;

    this(GameEngine a_engine) {
        mEngine = a_engine;
        //init to what we had in the GUI in r865
        mBorder.border = Color(0.7);
        mBorder.back = Color(0);
        mBorder.cornerRadius = 3;
        mFontColor = Color(0.9);
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
        update();
    }

    Color color() {
        return mFontColor;
    }
    void color(Color c) {
        if (c == mFontColor)
            return;
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

    //--- non-determinstic functions following here

    private void update() {
        if (!mT.renderer) {
            mT.renderer = new FormattedText();
            mT.renderer.font = gFontManager.loadFont("wormfont");
        }
        mT.renderer.setBorder(mBorder);
        mT.renderer.setMarkup(mMarkupText);
        FontProperties p = mT.renderer.font.properties;
        auto p2 = p;
        p2.fore = mFontColor;
        if (p2 != p) {
            mT.renderer.font = gFontManager.create(p2);
        }
    }

    FormattedText renderer() {
        if (!mT.renderer) {
            update();
            assert(!!mT.renderer);
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
        auto getcontrolled = mEngine.callbacks.getControlledTeamMember;
        if (!getcontrolled)
            return true;
        return visibility(getcontrolled());
    }
}

