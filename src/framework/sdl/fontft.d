module framework.sdl.fontft;

import derelict.opengl.gl;
import derelict.freetype.ft;
import derelict.util.exception;

import framework.framework;
import framework.sdl.framework;
import framework.font;
import framework.texturepack;

import utils.array;
import utils.misc;
import utils.vector2;

import stdx.stream;

private struct GlyphData {
    TextureRef tex;     //glyph texture
    TextureRef border;  //second texture for border, can be null
    Vector2i offset;    //texture drawing offset, relative to text top
    Vector2i border_offset; //same for border
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

        int ftres;

        //xxx: error handling doesn't free stuff allocated from FT
        //(also, I check allocating functions only)
        void ftcheck(char[] name) {
            if (ftres)
                throw new Exception(myformat("fontft.d failed: err={} in {}",
                    ftres, name));
        }

        //Load the Glyph for our character.
        ftres = FT_Load_Glyph(mFace, FT_Get_Char_Index(mFace, ch),
            FT_LOAD_DEFAULT);
        ftcheck("FT_Load_Glyph");

        //this is quite ugly, better use a specific face file
        if (mDoBold) {
            FT_GlyphSlot_Embolden(mFace.glyph);
        }
        if (mDoItalic) {
            //this function is undocumented, but mplayer uses it for italics
            FT_GlyphSlot_Oblique(mFace.glyph);
        }

        FT_Glyph glyph;
        ftres = FT_Get_Glyph(mFace.glyph, &glyph);
        ftcheck("FT_Get_Glyph");

        //Render the glyph
        ftres = FT_Glyph_To_Bitmap(&glyph, FT_Render_Mode.FT_RENDER_MODE_NORMAL,
            null, 1);
        ftcheck("FT_Glyph_To_Bitmap");

        FT_BitmapGlyph glyph_bitmap = cast(FT_BitmapGlyph)glyph;
        FT_Bitmap* glyph_bmp = &glyph_bitmap.bitmap;
        assert (glyph_bmp.pixel_mode == FT_Pixel_Mode.FT_PIXEL_MODE_GRAY);

        GlyphData ret;

        ret.tex = ftbitmapToTex(glyph_bmp, props.fore);

        //surface only contains the actual glyph
        ret.offset.x = glyph_bitmap.left;
        ret.offset.y = mBaseline - glyph_bitmap.top;

        //border is an additional texture
        if (props.border_width > 0) {
            FT_Glyph border_glyph;
            FT_Get_Glyph(mFace.glyph, &border_glyph);
            ftcheck("FT_Get_Glyph (2)");

            FT_Stroker stroker;
            //xxx: first parameter (are the bindings wrong? I dumb? wtf?)
            ftres = FT_Stroker_New(cast(FT_MemoryRec*)mFace.glyph.library,
                &stroker);
            ftcheck("FT_Stroker_New");
            FT_Stroker_Set(stroker, props.border_width << 6,
                FT_Stroker_LineCap.FT_STROKER_LINECAP_ROUND,
                FT_Stroker_LineJoin.FT_STROKER_LINEJOIN_ROUND, 0);
            FT_Glyph_StrokeBorder(&border_glyph, stroker, 0, 1);
            FT_Stroker_Done(stroker);

            //render another glpyh for the border
            ftres = FT_Glyph_To_Bitmap(&border_glyph,
                FT_Render_Mode.FT_RENDER_MODE_NORMAL, null, 1);
            ftcheck("FT_Glyph_To_Bitmap (2)");

            FT_BitmapGlyph border_bitmap = cast(FT_BitmapGlyph)border_glyph;
            FT_Bitmap* border_bmp = &border_bitmap.bitmap;
            assert (border_bmp.pixel_mode == FT_Pixel_Mode.FT_PIXEL_MODE_GRAY);

            ret.border_offset.x = border_bitmap.left;
            ret.border_offset.y = mBaseline - border_bitmap.top;

            //do the same weird stuff mplayer does
            //first find out the common subrect
            auto rc1 = Rect2i.Span(ret.offset, ret.tex.size);
            auto rc2 = Rect2i.Span(ret.border_offset,
                Vector2i(border_bmp.width, border_bmp.rows));
            auto rci = rc1.intersection(rc2);
            assert (rci.isNormal());
            auto p1 = rci.p1 - ret.offset;
            auto p2 = rci.p1 - ret.border_offset;
            for (int y = rci.p1.y; y < rci.p2.y; y++) {
                ubyte* pn = glyph_bmp.buffer + p1.y*glyph_bmp.pitch + p1.x;
                ubyte* pb = border_bmp.buffer + p2.y*border_bmp.pitch + p2.x;
                for (int x = rci.p1.x; x < rci.p2.x; x++) {
                    *pb = *pb > *pn ? *pb : 0;
                    pn++; pb++;
                }
                p1.y++; p2.y++;
            }

            ret.border = ftbitmapToTex(border_bmp, props.border_color);

            FT_Done_Glyph(border_glyph);
        }

        FT_Done_Glyph(glyph);

        ret.size.x = mFace.glyph.advance.x >> 6;
        //small hack
        //ret.size.x += props.border_width;
        ret.size.y = mHeight;

        mFrags[ch] = ret;
    }

    private TextureRef ftbitmapToTex(FT_Bitmap* bmp, Color color) {
        //create a surface for a glyph
        Surface tmp = gFramework.createSurface(
            Vector2i(bmp.width, bmp.rows),
            Transparency.Alpha);

        Color.RGBA32 forecol = color.toRGBA32();

        //copy the (monochrome) glyph data to the 32bit surface
        //color values come from foreground color, alpha from glyph data
        Color.RGBA32* sdata; uint spitch;
        ubyte* srcptr = bmp.buffer;
        tmp.lockPixelsRGBA32(sdata, spitch);
        for (int y = 0; y < tmp.size.y; y++) {
            Color.RGBA32* data = sdata + spitch*y;
            ubyte* src = srcptr + bmp.pitch*y;
            for (int x = 0; x < tmp.size.x; x++) {
                //copy foreground color, and use glyph data for alpha channel
                *data = forecol;
                data.a = cast(ubyte)(*src * forecol.a / 256);
                data++;
                src++;
            }
        }
        tmp.unlockPixels(tmp.rect);

        TextureRef ret;
        if (mPacker) {
            ret = mPacker.add(tmp);
            tmp.free();
        } else {
            ret = TextureRef(tmp, Vector2i(0), tmp.size);
        }
        return ret;
    }
}

class FTFont : DriverFont {
    private {
        FTGlyphCache mCache;
        FontProperties mProps;
        bool mUseGL;
    }

    package int refcount = 1;

    this(FTGlyphCache glyphs, FontProperties props) {
        mCache = glyphs;
        mProps = props;
        mUseGL = gSDLDriver.mOpenGL;
    }

    Vector2i draw(Canvas canvas, Vector2i pos, int w, char[] text) {
        /+if (mUseGL) {
            glPushAttrib(GL_CURRENT_BIT);
        }
        scope(exit) if (mUseGL) {
            glPopAttrib();
        }+/
        if (w == int.max) {
            return drawText(canvas, pos, w, text);
        } else {
            Vector2i s = textSize(text, true);
            if (s.x <= w) {
                return drawText(canvas, pos, w, text);
            } else {
                char[] dotty = "...";
                int ds = textSize(dotty, true).x;
                w -= ds;
                pos = drawText(canvas, pos, w, text);
                pos = drawText(canvas, pos, ds, dotty);
                return pos;
            }
        }
    }

    private void drawGlyph(Canvas c, GlyphData* glyph, Vector2i pos) {
        void setColor(Color c) {
            if (mUseGL)
                glColor3f(c.r, c.g, c.b);
        }

        if (mProps.back.a > 0)
            c.drawFilledRect(Rect2i.Span(pos, glyph.size), mProps.back);

        setColor(mProps.fore);
        glyph.tex.draw(c, pos+glyph.offset);

        if (glyph.border.surface) {
            setColor(mProps.border_color);
            glyph.border.draw(c, pos+glyph.border_offset);
        }

        //GL cleanup
        setColor(Color(1, 1, 1));
    }

    private Vector2i drawText(Canvas canvas, Vector2i pos, int w, char[] text) {
        int orgx = pos.x;
        foreach (dchar c; text) {
            auto glyph = mCache.getGlyph(c);
            auto npos = pos.x + glyph.size.x;
            if (npos - orgx > w)
                break;
            drawGlyph(canvas, glyph, pos);
            pos.x = npos;
        }
        return pos;
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
        if (gSDLDriver.mOpenGL) {
            //normalize to a standard color
            //because of issues with the border, keep alpha component
            gc_props.fore = Color(1, 1, 1, gc_props.fore.a);   //white
            gc_props.border_color = Color(1, 1, 1, gc_props.border_color.a);
        }
        //background is rendered separately, exclude from AA key
        gc_props.back = Color.init;

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
    if (procName.length > 3 && procName[0..4] == "FTC_")
        return true;
    return false;
}
