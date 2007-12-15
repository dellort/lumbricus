module framework.sdl.font;

import framework.framework;
import framework.font;
import framework.sdl.framework;
import framework.sdl.rwops;
import framework.texturepack;
import derelict.sdl.sdl;
import derelict.sdl.ttf;

import std.stream;
import std.string;

class SDLFont : DriverFont {
    private {
        TextureRef mFrags[dchar];
        TexturePack mPacker; //if null => one surface per glyph
        bool mNeedBackPlain;   //false if background is completely transp.
        bool mOpaque;
        uint mHeight;
        FontProperties props;
        TTF_Font* font;
        // Stream is used by TTF_Font, this keeps the reference to it
        // possibly shared accross font instances
        Stream mFontStream;
    }

    package int refcount = 1;

    this(Stream str, FontProperties props) {
        mFontStream = str;
        mFontStream.seek(0,SeekPos.Set);
        this.props = props;
        SDL_RWops* rwops;
        rwops = rwopsFromStream(mFontStream);
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

        if (gSDLDriver.mUseFontPacker) {
            mPacker = new TexturePack();
        }
    }

    void free() {
        releaseCache();
        TTF_CloseFont(font);
        font = null;
        mFontStream = null;
    }

    int cachedGlyphs() {
        return mFrags.length;
    }

    int releaseCache() {
        int rel;
        if (mPacker) {
            mPacker.free();
        } else {
            foreach (TextureRef t; mFrags) {
                t.surface.free();
                rel++;
            }
            mFrags = null;
        }
        return rel;
    }

    public FontProperties properties() {
        return props;
    }

    Vector2i draw(Canvas canvas, Vector2i pos, int w, char[] text) {
        if (w == int.max) {
            return drawText(canvas, pos, text);
        } else {
            return drawTextLimited(canvas, pos, w, text);
        }
    }

    private Vector2i drawText(Canvas canvas, Vector2i pos, char[] text) {
        foreach (dchar c; text) {
            TextureRef surface = getGlyph(c);
            if (mNeedBackPlain) {
                canvas.drawFilledRect(pos, pos+surface.size, props.back, true);
            }
            surface.draw(canvas, pos);
            pos.x += surface.size.x;
        }
        return pos;
    }

    private Vector2i drawTextLimited(Canvas canvas, Vector2i pos, int width,
        char[] text)
    {
        Vector2i s = textSize(text, true);
        if (s.x <= width) {
            return drawText(canvas, pos, text);
        } else {
            char[] dotty = "...";
            int ds = textSize(dotty, true).x;
            width -= ds;
            //draw manually (oh, this is an xxx)
            foreach (dchar c; text) {
                TextureRef surface = getGlyph(c);
                auto npos = pos.x + surface.size.x;
                if (npos > width)
                    break;
                if (mNeedBackPlain) {
                    canvas.drawFilledRect(pos, pos+surface.size, props.back,
                        true);
                }
                surface.draw(canvas, pos);
                pos.x = npos;
            }
            pos = drawText(canvas, pos, dotty);
            return pos;
        }
    }

    Vector2i textSize(char[] text, bool forceHeight) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            TextureRef surface = getGlyph(c);
            res.x += surface.size.x;
        }
        if (text.length > 0 || forceHeight)
            res.y = TTF_FontHeight(font);
        return res;
    }

    private TextureRef getGlyph(dchar c) {
        TextureRef* sptr = c in mFrags;
        if (!sptr) {
            mFrags[c] = renderChar(c);
            sptr = c in mFrags;
        }
        return *sptr;
    }

    //color: ignores the alpha value
    private Surface doRender(dchar c, inout Color color) {
        dchar s[2];
        s[0] = c;
        s[1] = '\0';
        SDL_Color col = ColorToSDLColor(color);
        assert(!!font);
        SDL_Surface* surface = TTF_RenderUNICODE_Blended(font,
            cast(ushort*)s.ptr, col);
        if (surface == null) {
            throw new Exception(format("could not render char %s", c));
        }
        auto res = gSDLDriver.convertFromSDLSurface(surface, Transparency.Alpha,
            true);
        assert(mHeight == res.size.y);
        return res;
    }

    private Surface doRenderChar2(dchar c) {
        auto tmp = doRender(c, props.fore);
        if (props.fore.a <= (1.0f - Color.epsilon)) {
            tmp.scaleAlpha(props.fore.a);
        }
        if (mOpaque) {
            auto s = gFramework.createSurface(tmp.size, Transparency.None);
            auto d = gSDLDriver.startOffscreenRendering(s);
            d.drawFilledRect(Vector2i(0), s.size, props.back, false);
            d.draw(tmp, Vector2i(0));
            d.endDraw();
            tmp.free();
            return s;
        } else {
            return tmp;
        }
    }

    private TextureRef renderChar(dchar c) {
        Surface s = doRenderChar2(c);
        if (mPacker) {
            return mPacker.add(s);
        } else {
            return TextureRef(s, Vector2i(0), s.size);
        }
    }

    char[] getInfos() {
        return format("glyphs=%d, pages=%d", cachedGlyphs,
            mPacker ? mPacker.pages : -1);
    }
}

class SDLFontDriver : FontDriver {
    private {
        SDLFont[FontProperties] mFonts;
    }

    this() {
        DerelictSDLttf.load();

        if (TTF_Init()==-1) {
            throw new Exception(format("TTF_Init: %s\n",
                std.string.toString(TTF_GetError())));
        }
    }

    void destroy() {
        assert(mFonts.length == 0);
        TTF_Quit();
        DerelictSDLttf.unload();
    }

    DriverFont createFont(FontProperties props) {
        SDLFont* ph = props in mFonts;
        if (ph) {
            SDLFont r = *ph;
            r.refcount++;
            return r;
        }

        Stream data = gFramework.fontManager.findFace(props.face);
        auto f = new SDLFont(data, props);
        mFonts[props] = f;

        return f;
    }

    void destroyFont(inout DriverFont a_handle) {
        auto handle = cast(SDLFont)a_handle;
        assert(!!handle);
        auto p = handle.props;
        assert(handle is mFonts[p]);
        handle.refcount--;
        if (handle.refcount < 1) {
            assert(handle.refcount == 0);
            handle.releaseCache();
            handle.free();
            mFonts.remove(p);
        }
        a_handle = null;
    }

    int releaseCaches() {
        int count;
        foreach (SDLFont fh; mFonts) {
            count += fh.releaseCache();
            count++;
        }
        return count;
    }
}
