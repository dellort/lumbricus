//libfreetype font driver
module framework.drivers.font_freetype;

import derelict.freetype.ft;
import derelict.util.exception;

import framework.font;
import framework.drawing;
import framework.driver_base;
import framework.globalsettings;
import framework.surface;
import framework.texturepack;

import utils.array;
import utils.misc;
import utils.vector2;
import utils.color;
import utils.configfile;

import utils.stream;

const cDrvName = "font_freetype";

private struct GlyphData {
    SubSurface tex;     //glyph texture
    SubSurface border;  //second texture for border, can be null
    SubSurface shadow;  //can also be null
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
        int mHeight;
        int mBaseline;
        int mLineSkip;
        int mUnderlineOffset, mUnderlineHeight;
        FT_Face mFace;
        //referenced across shared font instances
        FontData mFontStream;
        bool mDoBold, mDoItalic;
        FTFontDriver mDriver;
    }

    //read-only
    FontProperties props;

    int refcount = 1;

    this(FTFontDriver driver, FontProperties props) {
        mDriver = driver;
        if (!gFontManager.faceExists(props.face, props.getFaceStyle))
        {
            mDoBold = props.bold;
            mDoItalic = props.italic;
        }
        //will fall back to default style if specified was not found
        mFontStream = gFontManager.findFace(props.face, props.getFaceStyle);
        if (!mFontStream.length) {
            throwError("Failed to load font '%s': Face file not found.",
                props.face);
        }
        this.props = props;
        //NOTE: FT wants that you don't deallocate the passed font file data
        if (FT_New_Memory_Face(driver.library, mFontStream.ptr,
            mFontStream.length, 0, &mFace))
        {
            throwError("Freetype failed to load font '%s'.", props.face);
        }

        //only supports scalable fonts
        if (!FT_IS_SCALABLE(mFace))
            throwError("Invalid font: Not scalable.");
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
    }

    //if null => one surface per glyph
    TexturePack packer() {
        return mDriver.getPacker();
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
        if (!packer()) {
            foreach (GlyphData g; mFrags) {
                g.tex.surface.free();
                rel++;
            }
        }
        mFrags = null;
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
            assert(!!sptr);
        }
        return sptr;
    }

    private void loadGlyph(dchar ch) {
        if (ch in mFrags)
            return;   //glyph already loaded

        int ftres;

        //xxx: error handling doesn't free stuff allocated from FT
        //xxx 2: should probably be more forgiving about errors (e.g. display
        //  nothing or an error texture instead of crashing)
        //(also, I check allocating functions only)
        void ftcheck(string name) {
            if (ftres)
                throw new Exception(
                    myformat("fontft.d failed: err=%s in %s", ftres, name));
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

        ret.tex = ftbitmapToTex(glyph_bmp, props.fore_color);

        //surface only contains the actual glyph
        ret.offset.x = glyph_bitmap.left;
        ret.offset.y = mBaseline - glyph_bitmap.top;

        bool has_border = props.border_width > 0;
        bool has_shadow = props.shadow_offset > 0;

        //border is an additional texture
        if (has_border || has_shadow) {
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

            if (has_shadow)
                ret.shadow = ftbitmapToTex(border_bmp, props.shadow_color);

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
                    //doesn't work: when drawing the border and the glyph,
                    //  there are parts where both bitmaps have <255 alpha,
                    //  making the background shine through
                    //but it still looks better than before + mostly invisible
                    ubyte b = *pb, n = *pn;
                    *pb = b > n ? b - (n / 2) : 0;
                    pn++; pb++;
                }
                p1.y++; p2.y++;
            }

            if (has_border)
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

    private SubSurface ftbitmapToTex(FT_Bitmap* bmp, Color color) {
        //create a surface for a glyph
        Surface tmp = new Surface(Vector2i(bmp.width, bmp.rows));

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

        SubSurface ret;
        if (auto pk = packer()) {
            ret = pk.add(tmp);
            tmp.free();
        } else {
            ret = tmp.createSubSurface(Rect2i(tmp.size));
        }
        return ret;
    }
}

class FTFont : DriverFont {
    private {
        FTFontDriver mDriver;
        FTGlyphCache mCache;     //"main" cache, for font in mProps
        FontProperties mProps;
    }

    this(FTFontDriver driver, Font font) {
        mDriver = driver;
        mProps = font.properties;
        mCache = mDriver.getCache(mProps);
        ctor(driver, font);
    }

    override void destroy() {
        super.destroy();
        mDriver.unrefCache(mCache);
    }

    private FontProperties props() {
        //ok, the reason for not using the cache's props is because the cache
        //  resets FontProperties member that don't change the generated glyphs
        //return mCache.props;
        return mProps;
    }

    private void drawGlyph(Canvas c, GlyphData* glyph, Vector2i pos) {
        if (props.back_color.a > 0)
            c.drawFilledRect(Rect2i.Span(pos, glyph.size), props.back_color);

        if (glyph.shadow) {
            c.drawSprite(glyph.shadow, pos + glyph.border_offset
                + Vector2i(props.shadow_offset));
        }

        if (glyph.border) {
            c.drawSprite(glyph.border, pos+glyph.border_offset);
        }

        c.drawSprite(glyph.tex, pos+glyph.offset);
    }

    Vector2i draw(Canvas canvas, Vector2i pos, string text) {
        int orgx = pos.x;
        foreach (dchar c; text) {
            auto glyph = mCache.getGlyph(c);
            auto npos = pos.x + glyph.size.x;
            drawGlyph(canvas, glyph, pos);
            pos.x = npos;
        }

        //it seems we really must draw this ourselves
        if (props.underline) {
            int lh = mCache.mUnderlineHeight;
            int u_y = pos.y + mCache.mBaseline - mCache.mUnderlineOffset;
            //border for underline
            //xxx: not correctly composited with foreground line (but who cares)
            int b = props.border_width;
            if (b > 0) {
                canvas.drawLine(Vector2i(orgx - b/2, u_y),
                    Vector2i(pos.x + b/2, u_y), props.border_color, lh + b);
            }
            //normal underline
            canvas.drawLine(Vector2i(orgx, u_y), Vector2i(pos.x, u_y),
                props.fore_color, lh);
        }

        return pos;
    }

    Vector2i textSize(string text, bool forceHeight) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            auto glyph = mCache.getGlyph(c);
            res.x += glyph.size.x;
        }
        if (text.length > 0 || forceHeight)
            res.y = mCache.height;
        return res;
    }
}

class FTFontDriver : FontDriver {
    private {
        FT_Library library;
        FTGlyphCache[FontProperties] mGlyphCaches;
        TexturePack mPacker;
    }
    bool useFontPacker;

    this() {
        useFontPacker = getSetting!(bool)(cDrvName ~ ".font_packer");
        Derelict_SetMissingProcCallback(&missingProcCb);
        DerelictFT.load();
        Derelict_SetMissingProcCallback(null);
        if (FT_Init_FreeType(&library))
            throwError("FT_Init_FreeType failed");
    }

    override void destroy() {
        super.destroy();
        assert(mGlyphCaches.length == 0); //our error
        FT_Done_FreeType(library);
        DerelictFT.unload();
    }

    override DriverResource createDriverResource(Resource res) {
        return createFont(castStrict!(Font)(res));
    }

    DriverFont createFont(Font props) {
        return new FTFont(this, props);
    }

    private FTGlyphCache getCache(FontProperties props) {
        FontProperties gc_props = props;
        gc_props.underline = false; //rendered by us, is not in glyph bitmaps
        //background is rendered separately, exclude from AA key
        gc_props.back_color = Color.init;

        FTGlyphCache gc = aaIfIn(mGlyphCaches, gc_props);

        if (!gc) {
            gc = new FTGlyphCache(this, gc_props);
            mGlyphCaches[gc_props] = gc;
        } else {
            gc.refcount++;
        }
        return gc;
    }

    private void unrefCache(FTGlyphCache cache) {
        assert(cache.refcount > 0);
        cache.refcount--;
        if (cache.refcount < 1) {
            cache.releaseCache();
            cache.free();
            mGlyphCaches.remove(cache.props);
        }
    }

    override int releaseCaches(CacheRelease r) {
        int count;
        foreach (FTGlyphCache gc; mGlyphCaches) {
            count += gc.releaseCache();
            count++;
        }
        delete mPacker;
        return count;
    }

    package TexturePack getPacker() {
        if (!useFontPacker)
            return null;
        if (!mPacker)
            mPacker = new TexturePack();
        return mPacker;
    }

    static this() {
        registerFrameworkDriver!(typeof(this))(cDrvName);
        addSetting!(bool)(cDrvName ~ ".font_packer", true);
    }
}

private bool missingProcCb(string libName, string procName)
{
    if (procName == "FT_Library_SetLcdFilter")
        return true;
    if (procName.length > 3 && procName[0..4] == "FTC_")
        return true;
    return false;
}
