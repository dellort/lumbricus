module framework.sdl.fontft;

import derelict.opengl.gl;
import derelict.freetype.ft;
import derelict.util.exception;

import framework.framework;
import framework.sdl.framework;
import framework.font;
import framework.texturepack;

import utils.array;
import utils.vector2;

import stdx.stream;

private struct GlyphData {
    TextureRef tex;     //glyph texture
    Vector2i offset;    //texture drawing offset, relative to text top
    Vector2i size;      //space this glyph takes (!= tex.size)
}

//thx SDL_ttf
/* Handy routines for converting from fixed point */
private int FT_Floor(FT_Long x) {
    return (x & -64) / 64;
}
private int FT_Ceil(FT_Long x) {
    return ((x + 63) & -64) / 64;
}

//renderer and cache for font glyphs
class FTGlyphCache {
    private {
        GlyphData mFrags[dchar];
        TexturePack mPacker; //if null => one surface per glyph
        bool mOpaque;
        int mHeight;
        int mBaseline;
        int mLineSkip;
        int mUnderlineOffset, mUnderlineHeight;
        FontProperties props;
        FT_Face mFace;
        // Stream is used by TTF_Font, this keeps the reference to it
        // possibly shared accross font instances
        MemoryStream mFontStream;
        bool mDoBold, mDoItalic;
    }

    package int refcount = 1;

    this(FTFontDriver driver, FontProperties props) {
        if (!gFramework.fontManager.faceExists(props.face, props.getFaceStyle))
        {
            mDoBold = props.bold;
            mDoItalic = props.italic;
        }
        //will fall back to default style if specified was not found
        mFontStream = gFramework.fontManager.findFace(props.face,
            props.getFaceStyle);
        if (!mFontStream) {
            throw new Exception("Failed to load font '" ~ props.face
                ~ "': Face file not found.");
        }
        mFontStream.seek(0,SeekPos.Set);
        this.props = props;
        if (FT_New_Memory_Face(driver.library, mFontStream.data.ptr,
            mFontStream.size, 0, &mFace))
        {
            throw new Exception("Freetype failed to load font '"
                ~ props.face ~ "'.");
        }

        //only supports scalable fonts
        if (!FT_IS_SCALABLE(mFace))
            throw new Exception("Invalid font: Not scalable.");
        //using props.size as pointsize with default dpi (72)
        FT_Set_Char_Size(mFace, 0, props.size * 64, 0, 0);
        //calculate font metrics
        FT_Fixed scale = mFace.size.metrics.y_scale;
        mBaseline = FT_Ceil(FT_MulFix(mFace.ascender, scale));
        int descent = FT_Ceil(FT_MulFix(mFace.descender, scale));
        mHeight = mBaseline - descent + 1;
        mLineSkip = FT_Ceil(FT_MulFix(mFace.height, scale));
	    mUnderlineOffset = FT_Floor(FT_MulFix(mFace.underline_position,scale));
	    mUnderlineHeight = FT_Floor(FT_MulFix(mFace.underline_thickness,scale));
	    if (mUnderlineHeight < 1)
            mUnderlineHeight = 1;

        mOpaque = props.isOpaque;

        if (gSDLDriver.mUseFontPacker) {
            //all fonts into one packer, saves texture memory
            mPacker = driver.getPacker();
        }
    }

    void free() {
        releaseCache();
        FT_Done_Face(mFace);
        mFontStream = null;
    }

    int cachedGlyphs() {
        return mFrags.length;
    }

    int releaseCache() {
        int rel;
        if (!mPacker) {
            foreach (GlyphData g; mFrags) {
                g.tex.surface.free();
                rel++;
            }
            mFrags = null;
        }
        return rel;
    }

    //maximum size of glyphs
    int height() {
        return mHeight;
    }

    //offset from one baseline to the next
    int lineSkip() {
        return mLineSkip;
    }

    //offset from top to font baseline
    int baselineOffset() {
        return mBaseline;
    }

    //return a (part) of a surface with that glyph
    //it will be non-transparent for fully opaque fonts, but if the background
    //contains alpha, the surface is alpha blended and actually doesn't contain
    //anything of the background color
    GlyphData* getGlyph(dchar c) {
        GlyphData* sptr = c in mFrags;
        if (!sptr) {
            loadGlyph(c);
            sptr = c in mFrags;
        }
        return sptr;
    }

    private void loadGlyph(dchar ch) {
        if (ch in mFrags)
            return;   //glyph already loaded

        //Load the Glyph for our character.
        if (FT_Load_Glyph(mFace, FT_Get_Char_Index(mFace, ch), FT_LOAD_DEFAULT))
            throw new Exception("FT_Load_Glyph failed");

        //this is quite ugly, better use a specific face file
        //xxx missing italic, don't know how to do that
        if (mDoBold) {
            FT_GlyphSlot_Embolden(mFace.glyph);
        }

        //Move the face's glyph into a Glyph object.
        FT_GlyphSlot glyph = mFace.glyph;

        //Render the glyph
        FT_Render_Glyph(glyph, FT_Render_Mode.FT_RENDER_MODE_NORMAL);

        //create a surface for the glyph
        Surface tmp = gFramework.createSurface(
            Vector2i(glyph.bitmap.width, glyph.bitmap.rows),
            Transparency.Alpha);

        struct RGBA32 {
            ubyte r, g, b, a;
        }
        RGBA32 forecol;
        forecol.r = cast(ubyte)(props.fore.r*255);
        forecol.g = cast(ubyte)(props.fore.g*255);
        forecol.b = cast(ubyte)(props.fore.b*255);

        //copy the (monochrome) glyph data to the 32bit surface
        //color values come from foreground color, alpha from glyph data
        void* sdata; uint spitch;
        ubyte* srcptr = glyph.bitmap.buffer;
        tmp.lockPixelsRGBA32(sdata, spitch);
        for (int y = 0; y < tmp.size.y; y++) {
            RGBA32* data = cast(RGBA32*)(sdata + spitch*y);
            ubyte* src = srcptr + tmp.size.x*y;
            for (int x = 0; x < tmp.size.x; x++) {
                //copy foreground color, and use glyph data for alpha channel
                *data = forecol;
                data.a = cast(ubyte)(*src * props.fore.a);
                data++;
                src++;
            }
        }
        tmp.unlockPixels(tmp.rect);

        //fill glyph data structure
        GlyphData ret;
        ret.size.x = mFace.glyph.advance.x >> 6;
        ret.size.y = mHeight;

        //if necessary, draw the background
        Surface surf;
        if (mOpaque) {
            //create a surface for the full glyph area with background
            //(ret.tex.size == ret.size)
            surf = gFramework.createSurface(ret.size, Transparency.None);
            auto d = gSDLDriver.startOffscreenRendering(surf);
            d.drawFilledRect(Vector2i(0), surf.size, props.back);
            d.draw(tmp, Vector2i(glyph.bitmap_left, mBaseline-glyph.bitmap_top));
            d.endDraw();
            tmp.free();
            ret.offset.x = 0;
            ret.offset.y = 0;
        } else {
            //surface only contains the actual glyph
            surf = tmp;
            ret.offset.x = glyph.bitmap_left;
            ret.offset.y = mBaseline-glyph.bitmap_top;
        }

        if (mPacker) {
            ret.tex = mPacker.add(surf);
        } else {
            ret.tex = TextureRef(surf, Vector2i(0), surf.size);
        }

        mFrags[ch] = ret;
    }
}

class FTFont : DriverFont {
    private {
        FTGlyphCache mCache;
        FontProperties mProps;
        bool mNeedBackPlain, mUseGL;
    }

    package int refcount = 1;

    this(FTGlyphCache glyphs, FontProperties props) {
        mCache = glyphs;
        mProps = props;
        mNeedBackPlain = props.needsBackPlain;
        mUseGL = gSDLDriver.mOpenGL  && !props.isOpaque;
    }

    Vector2i draw(Canvas canvas, Vector2i pos, int w, char[] text) {
        if (mUseGL) {
            glPushAttrib(GL_CURRENT_BIT);
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

    private void drawGlyph(Canvas c, GlyphData* glyph, Vector2i pos) {
        if (mNeedBackPlain) {
            c.drawFilledRect(pos, pos+glyph.size, mProps.back);
        }
        if (mUseGL) {
            glColor4f(mProps.fore.r, mProps.fore.g, mProps.fore.b,
                mProps.fore.a);
        }
        glyph.tex.draw(c, pos+glyph.offset);
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
            auto glyph = mCache.getGlyph(c);
            res.x += glyph.size.x;
        }
        if (text.length > 0 || forceHeight)
            res.y = mCache.height;
        return res;
    }

    char[] getInfos() {
        return myformat("glyphs={}, pages={}", mCache.cachedGlyphs,
            mCache.mPacker ? mCache.mPacker.pages : -1);
    }
}

class FTFontDriver : FontDriver {
    private {
        FT_Library library;
        FTFont[FontProperties] mFonts;
        FTGlyphCache[FontProperties] mGlyphCaches;
        TexturePack mPacker;
    }

    this() {
        Derelict_SetMissingProcCallback(&missingProcCb);
        DerelictFT.load();
        Derelict_SetMissingProcCallback(null);
        if (FT_Init_FreeType(&library))
            throw new Exception("FT_Init_FreeType failed");
    }

    void destroy() {
        assert(mFonts.length == 0); //Framework's error
        assert(mGlyphCaches.length == 0); //our error
        FT_Done_FreeType(library);
        DerelictFT.unload();
    }

    DriverFont createFont(FontProperties props) {
        FTFont* ph = props in mFonts;
        if (ph) {
            FTFont r = *ph;
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

        FTGlyphCache gc = aaIfIn(mGlyphCaches, gc_props);

        if (!gc) {
            gc = new FTGlyphCache(this, gc_props);
            mGlyphCaches[gc_props] = gc;
        } else {
            gc.refcount++;
        }

        auto f = new FTFont(gc, props);
        mFonts[props] = f;

        return f;
    }

    void destroyFont(inout DriverFont a_handle) {
        auto handle = cast(FTFont)a_handle;
        assert(!!handle);
        auto p = handle.mProps;
        assert(handle is mFonts[p]);
        handle.refcount--;
        if (handle.refcount < 1) {
            assert(handle.refcount == 0);
            mFonts.remove(p);
            FTGlyphCache cache = handle.mCache;
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
        foreach (FTFont fh; mFonts) {
            count += fh.mCache.releaseCache();
            count++;
        }
        if (mPacker)
            mPacker.free();
        return count;
    }

    private TexturePack getPacker() {
        if (!mPacker)
            mPacker = new TexturePack();
        return mPacker;
    }
}

private bool missingProcCb(char[] libName, char[] procName)
{
    if (procName == "FT_Library_SetLcdFilter")
        return true;
    return false;
}
