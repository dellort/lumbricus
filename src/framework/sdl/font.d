module framework.sdl.font;

import derelict.opengl.gl;
import derelict.sdl.sdl;
import derelict.sdl.ttf;

import framework.framework;
import framework.font;
import framework.sdl.framework;
import framework.sdl.rwops;
import framework.texturepack;

import stdx.stream;
import stdx.string;

//renderer and cache for font glyphs
class GlyphCache {
    private {
        TextureRef mFrags[dchar];
        TexturePack mPacker; //if null => one surface per glyph
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

        mOpaque = props.isOpaque;

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

    //return a (part) of a surface with that glyph
    //it will be non-transparent for fully opaque fonts, but if the background
    //contains alpha, the surface is alpha blended and actually doesn't contain
    //anything of the background color
    TextureRef getGlyph(dchar c) {
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
        if (!surface) {
            //error fallback, render as '?'
            surface = TTF_RenderUNICODE_Blended(font,
                cast(ushort*)("?\0"d.ptr), col);
        }
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
        if (props.fore.hasAlpha()) {
            tmp.scaleAlpha(props.fore.a);
        }
        if (mOpaque) {
            auto s = gFramework.createSurface(tmp.size, Transparency.None);
            auto d = gSDLDriver.startOffscreenRendering(s);
            d.drawFilledRect(Vector2i(0), s.size, props.back);
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
}

class SDLFont : DriverFont {
    private {
        GlyphCache mCache;
        FontProperties mProps;
        bool mNeedBackPlain, mUseGL;
    }

    package int refcount = 1;

    this(GlyphCache glyphs, FontProperties props) {
        mCache = glyphs;
        mProps = props;
        mNeedBackPlain = props.needsBackPlain;
        mUseGL = gSDLDriver.mOpenGL  && !props.isOpaque;
    }

    Vector2i draw(Canvas canvas, Vector2i pos, int w, char[] text) {
        if (mUseGL) {
            glPushAttrib(GL_CURRENT_BIT);
            glColor4f(mProps.fore.r, mProps.fore.g, mProps.fore.b,
                mProps.fore.a);
        }
        scope(exit) if (mUseGL) {
            glPopAttrib();
        }
        if (w == int.max) {
            return drawText(canvas, pos, text);
        } else {
            return drawTextLimited(canvas, pos, w, text);
        }
    }

    private void drawGlyph(Canvas c, TextureRef glyph, Vector2i pos) {
        if (mNeedBackPlain) {
            c.drawFilledRect(pos, pos+glyph.size, mProps.back);
        }
        glyph.draw(c, pos);
    }

    private Vector2i drawText(Canvas canvas, Vector2i pos, char[] text) {
        foreach (dchar c; text) {
            auto glyph = mCache.getGlyph(c);
            drawGlyph(canvas, glyph, pos);
            pos.x += glyph.size.x;
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
                auto glyph = mCache.getGlyph(c);
                auto npos = pos.x + glyph.size.x;
                if (npos > width)
                    break;
                drawGlyph(canvas, glyph, pos);
                pos.x = npos;
            }
            pos = drawText(canvas, pos, dotty);
            return pos;
        }
    }

    Vector2i textSize(char[] text, bool forceHeight) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            TextureRef surface = mCache.getGlyph(c);
            res.x += surface.size.x;
        }
        if (text.length > 0 || forceHeight)
            res.y = mCache.mHeight;
        return res;
    }

    char[] getInfos() {
        return format("glyphs=%d, pages=%d", mCache.cachedGlyphs,
            mCache.mPacker ? mCache.mPacker.pages : -1);
    }
}

class SDLFontDriver : FontDriver {
    private {
        SDLFont[FontProperties] mFonts;
        GlyphCache[FontProperties] mGlyphCaches;
    }

    this() {
        DerelictSDLttf.load();

        if (TTF_Init()==-1) {
            throw new Exception(format("TTF_Init: %s\n",
                .toString(TTF_GetError())));
        }
    }

    void destroy() {
        assert(mFonts.length == 0); //Framework's error
        assert(mGlyphCaches.length == 0); //our error
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

        FontProperties gc_props = props;
        //on OpenGL, you can color up surfaces at no costs, so...
        //not for opaque surfaces, these are rendered as a single surface
        if (gSDLDriver.mOpenGL && !gc_props.isOpaque) {
            //normalize to a standard color
            gc_props.back = Color(0,0,0,0); //fully transparent
            gc_props.fore = Color(1,1,1);   //white
        }

        GlyphCache* pgc = gc_props in mGlyphCaches;
        GlyphCache gc = pgc ? *pgc : null;

        if (!gc) {
            Stream data = gFramework.fontManager.findFace(gc_props.face);
            gc = new GlyphCache(data, gc_props);
            mGlyphCaches[gc_props] = gc;
        } else {
            gc.refcount++;
        }

        auto f = new SDLFont(gc, props);
        mFonts[props] = f;

        return f;
    }

    void destroyFont(inout DriverFont a_handle) {
        auto handle = cast(SDLFont)a_handle;
        assert(!!handle);
        auto p = handle.mProps;
        assert(handle is mFonts[p]);
        handle.refcount--;
        if (handle.refcount < 1) {
            assert(handle.refcount == 0);
            mFonts.remove(p);
            GlyphCache cache = handle.mCache;
            cache.refcount--;
            if (cache.refcount < 1) {
                cache.releaseCache();
                cache.free();
                mGlyphCaches.remove(cache.props);
            }
        }
        a_handle = null;
    }

    int releaseCaches() {
        int count;
        foreach (SDLFont fh; mFonts) {
            count += fh.mCache.releaseCache();
            count++;
        }
        return count;
    }
}
