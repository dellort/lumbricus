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
    private uint mHeight;
    private FontProperties props;
    private TTF_Font* font;
    // Stream is used by TTF_Font, this keeps the reference to it
    private MemoryStream font_stream;

    this(Stream str, FontProperties props) {
        font_stream = new MemoryStream();
        str.seek(0,SeekPos.Set);
        font_stream.copyFrom(str);
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

        //Backplain not needed if it's fully transparent
        mNeedBackPlain = (props.back.a >= Color.epsilon);
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

/+
it worked, but was useless: FontManager considers Fonts to be immutable
    //setting is expensive, but at least works
    public void properties(FontProperties props) {
        close();
        init(props);
    }
+/

    public void drawText(Canvas canvas, Vector2i pos, char[] text) {
        foreach (dchar c; text) {
            Texture surface = getGlyph(c);
            if (mNeedBackPlain) {
                canvas.drawFilledRect(pos, pos+surface.size, props.back, true);
            }
            canvas.draw(surface, pos);
            pos.x += surface.size.x;
        }
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
                if (mNeedBackPlain) {
                    canvas.drawFilledRect(pos, pos+surface.size, props.back, true);
                }
                auto npos = pos.x + surface.size.x;
                if (npos > width)
                    break;
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
        auto res = new SDLSurface(surface);
        return res;
    }

    private Texture renderChar(dchar c) {
        auto tmp = doRender(c, props.fore);
        tmp.scaleAlpha(props.fore.a);
        tmp.enableAlpha();
        //xxx: be able to free it?
        return tmp.createTexture();
    }
}
