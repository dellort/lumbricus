module framework.sdl.font;

import framework.framework;
import framework.font;
import framework.sdl.framework;
import framework.sdl.rwops;
import derelict.sdl.sdl;
import derelict.sdl.ttf;
import std.stream;

import utils.weaklist;

package {
    struct FontData {
        TTF_Font* font;

        void doFree() {
            if (font)
                TTF_CloseFont(font);
        }
    }
    WeakList!(SDLFont, FontData) gFonts;
}

package class SDLFont : Font {
    private Texture frags[dchar];
    private bool mNeedBackPlain;   //false if background is completely transp.
    private bool mOpaque;
    private uint mHeight;
    private FontProperties props;
    private TTF_Font* font;
    // Stream is used by TTF_Font, this keeps the reference to it
    // possibly shared accross font instances
    private Stream font_stream;

    this(Stream str, FontProperties props, bool need_copy = true) {
        if (need_copy) {
            font_stream = new MemoryStream();
            str.seek(0,SeekPos.Set);
            font_stream.copyFrom(str);
        } else {
            font_stream = str;
        }
        init(props);
        gFonts.add(this);
    }

    void init(FontProperties props) {
        font_stream.seek(0,SeekPos.Set);
        this.props = props;
        SDL_RWops* rwops;
        rwops = rwopsFromStream(font_stream);
        font = TTF_OpenFontRW(rwops, 0, props.size);
        if (font == null) {
            throw new Exception("Could not load font.");
        }
        int styles = (props.bold ? TTF_STYLE_BOLD : 0)
            | (props.italic ? TTF_STYLE_ITALIC : 0)
            | (props.underline ? TTF_STYLE_UNDERLINE : 0);
        TTF_SetFontStyle(font, styles);

        mHeight = TTF_FontHeight(font);
        //assert(mHeight == props.size); bleh

        //Backplain not needed if it's fully transparent
        mNeedBackPlain = (props.back.a >= Color.epsilon);
        //or if it's fully opaque (see renderChar())
        mOpaque = (props.back.a > 1.0f - Color.epsilon);
        mNeedBackPlain = mNeedBackPlain && !mOpaque;
    }

    void doFree(bool finalizer) {
        FontData d;
        d.font = font;
        font = null;
        gFonts.remove(this, finalizer, d);
    }

    ~this() {
        doFree(true);
    }

    //warning: defered free etc.
    override public void free() {
        doFree(false);
    }

    bool valid() {
        return !!font;
    }

    int cachedGlyphs() {
        return frags.length;
    }

    int releaseCache() {
        int rel;
        foreach (Texture t; frags) {
            t.clearCache();
            t.getSurface().free();
            rel++;
        }
        frags = null;
        return rel;
    }

    public FontProperties properties() {
        return props;
    }

    public SDLFont clone(FontProperties new_props) {
        return new SDLFont(font_stream, new_props, false);
    }

    public Vector2i drawText(Canvas canvas, Vector2i pos, char[] text) {
        foreach (dchar c; text) {
            Texture surface = getGlyph(c);
            if (mNeedBackPlain) {
                canvas.drawFilledRect(pos, pos+surface.size, props.back, true);
            }
            canvas.draw(surface, pos);
            pos.x += surface.size.x;
        }
        return pos;
    }

    public void drawTextLimited(Canvas canvas, Vector2i pos, int width,
        char[] text)
    {
        Vector2i s = textSize(text);
        if (s.x <= width) {
            drawText(canvas, pos, text);
        } else {
            char[] dotty = "...";
            int ds = textSize(dotty).x;
            width -= ds;
            //draw manually (oh, this is an xxx)
            foreach (dchar c; text) {
                Texture surface = getGlyph(c);
                auto npos = pos.x + surface.size.x;
                if (npos > width)
                    break;
                if (mNeedBackPlain) {
                    canvas.drawFilledRect(pos, pos+surface.size, props.back,
                        true);
                }
                canvas.draw(surface, pos);
                pos.x = npos;
            }
            drawText(canvas, pos, dotty);
        }
    }

    public Vector2i textSize(char[] text, bool forceHeight = true) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            Texture surface = getGlyph(c);
            res.x += surface.size.x;
        }
        if (text.length > 0 || forceHeight)
            res.y = TTF_FontHeight(font);
        return res;
    }

    private Texture getGlyph(dchar c) {
        Texture* sptr = c in frags;
        if (!sptr) {
            frags[c] = renderChar(c);
            sptr = c in frags;
        }
        return *sptr;
    }

    //color: ignores the alpha value
    private SDLSurface doRender(dchar c, inout Color color) {
        dchar s[2];
        s[0] = c;
        s[1] = '\0';
        SDL_Color col = ColorToSDLColor(color);
        SDL_Surface* surface = TTF_RenderUNICODE_Blended(font,
            cast(ushort*)s.ptr, col);
        if (surface == null) {
            throw new Exception(format("could not render char %s", c));
        }
        auto res = new SDLSurface(surface, true);
        assert(mHeight == res.size.y);
        return res;
    }

    private Texture renderChar(dchar c) {
        auto tmp = doRender(c, props.fore);
        if (props.fore.a <= (1.0f - Color.epsilon)) {
            tmp.scaleAlpha(props.fore.a);
        }
        tmp.enableAlpha();
        if (mOpaque) {
            auto s = gFramework.createSurface(tmp.size, DisplayFormat.Screen,
                Transparency.None);
            auto d = s.startDraw();
            d.drawFilledRect(Vector2i(0), s.size, props.back, false);
            d.draw(tmp.createBitmapTexture(), Vector2i(0));
            d.endDraw();
            tmp.free();
            return s.createTexture();
        } else {
            return tmp.createTexture();
        }
    }
}
