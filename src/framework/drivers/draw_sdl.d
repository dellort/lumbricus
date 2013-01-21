module framework.drivers.draw_sdl;

import derelict.sdl.sdl;
import framework.drawing;
import framework.driver_base;
import framework.globalsettings;
import framework.main;
import framework.surface;
import framework.drivers.base_sdl;
import framework.rotozoom;
import framework.sdl.sdl;
import utils.drawing;
import utils.misc;
import utils.vector2;

import std.math;

import str = utils.string;

enum cDrvName = "draw_sdl";

private struct Options {
    bool RLE = true;
    bool enable_conversion = true;
    //more alpha blending; more rotation precission and smoothing
    bool high_quality = false;
    //debugging
    bool mark_alpha = false;
}

class SDLDrawDriver : DrawDriver {
    private {
        Options opts;
        SDLCanvas mCanvas;
        Vector2i mScreenSize;
        //the screen
        SDL_Surface* mSDLScreen;
        //cache for being able to draw alpha blended filled rects without OpenGL
        Surface[uint] mInsanityCache;
    }

    this() {
        opts = getSettingsStruct!(Options)(cDrvName);

        get_screen();

        mCanvas = new SDLCanvas(this);
    }

    private void get_screen() {
        //this obviously means this DrawDriver is bound to SDL
        SDLDriver driver = castStrict!(SDLDriver)(gFramework.driver());
        mSDLScreen = SDL_GetVideoSurface();
    }

    override DriverSurface createDriverResource(Resource surface) {
        return new SDLSurface(this, castStrict!(Surface)(surface));
    }

    override Canvas startScreenRendering() {
        mCanvas.startScreenRendering();
        return mCanvas;
    }

    override void stopScreenRendering() {
        mCanvas.stopScreenRendering();
    }

    override void initVideoMode(Vector2i screen_size) {
        mScreenSize = screen_size;
        get_screen();
    }

    override Surface screenshot() {
        //this is possibly dangerous, but I'm too lazy to write proper code
        return convertFromSDLSurface(mSDLScreen, false);
    }

    override int getFeatures() {
        return mCanvas.features();
    }

    override void destroy() {
        super.destroy();
    }

    //return a surface with unspecified size containing this color
    //(used for drawing alpha blended rectangles)
    private Surface insanityCache(Color c) {
        uint key = c.toRGBA32().uint_val;

        Surface* s = key in mInsanityCache;
        if (s)
            return *s;

        enum cTileSize = 64;

        Surface tile = new Surface(Vector2i(cTileSize));

        tile.fill(Rect2i(tile.size), c);

        tile.enableCaching = true;

        mInsanityCache[key] = tile;
        return tile;
    }

    private int releaseInsanityCache() {
        int rel;
        foreach (Surface t; mInsanityCache) {
            t.free();
            rel++;
        }
        mInsanityCache = null;
        return rel;
    }

    int releaseCaches() {
        int count;
        count += releaseInsanityCache();
        return count;
    }

    static this() {
        registerFrameworkDriver!(typeof(this))(cDrvName);
        addSettingsStruct!(Options)(cDrvName);
    }
}

final class SDLSurface : DriverSurface {
    SDLDrawDriver mDrawDriver;
    Vector2i mSize;
    Transparency mTransparency;
    Color.RGBA32 mColorKey;
    bool mEnableCache;
    SDL_Surface* mSurfaceRGBA32;        //original image data (by ref!)
    SDL_Surface* mSurfaceCCed;          //colorkey converted copy; may be null
    SDL_Surface* mSurfaceConverted;     //display converted copy; may be null

    SubCache[] mCache; //array is in sync to Surface.mSubsurfaces[]
    struct SubCache {
        //not using an AA because AAs waste memory like hell
        //entry 0 is special for "all-normal" (no rotation etc.)
        CacheEntry[] entries;
    }
    struct CacheEntry {
        //key part
        int mirror;
        int rotate;
        int zoom;
        //data part
        SDL_Surface* surface;
        //parts of the transformation matrix for offset/center vector
        //basically it caches just the sin/cos of the rotation
        //also x and y would be easily recalculateable, but why not cache it
        float a = 1, b = 0, x = 0, y = 0;
    }

    //create from Framework's data
    this(SDLDrawDriver driver, Surface surface) {
        mDrawDriver = driver;
        mSize = surface.size;
        mEnableCache = surface.enableCaching;

        //NOTE: SDL_CreateRGBSurfaceFrom doesn't copy the data... so, be sure
        //      to keep the pointer, so D won't GC it
        auto rgba32 = sdlpfRGBA32();
        Color.RGBA32* pixels = surface._rawPixels.ptr;
        assert(!!pixels);

        mTransparency = Transparency.None;

        mSurfaceRGBA32 = SDL_CreateRGBSurfaceFrom(pixels,
            mSize.x, mSize.y, 32, mSize.x*4, rgba32.Rmask, rgba32.Gmask,
            rgba32.Bmask, rgba32.Amask);
        if (!mSurfaceRGBA32) {
            throw new Exception(
                myformat("couldn't create SDL surface, size=%s", mSize));
        }

        SDL_SetAlpha(mSurfaceRGBA32, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);

        assert_good_surface(mSurfaceRGBA32);

        ctor(driver, surface);

        unlockData(surface.rect); //copy in pixels
        update_subsurfaces();
    }

    //release data from driver surface
    override void destroy() {
        releaseSurface();
        super.destroy();
    }

    private void releaseSurface() {
        killcache(true);
        if (mSurfaceRGBA32) {
            SDL_FreeSurface(mSurfaceRGBA32);
            mSurfaceRGBA32 = null;
        }
        if (mSurfaceCCed) {
            SDL_FreeSurface(mSurfaceCCed);
            mSurfaceCCed = null;
        }
    }

    //plain RGBA32 surface, no scanline padding, no locking
    private void assert_good_surface(SDL_Surface* s) {
        assert(s.format.BitsPerPixel == 32);
        assert(s.format.BytesPerPixel == 4);
        assert(s.pitch == s.w * 4);
        assert(!SDL_MUSTLOCK(s));
        assert(s.pixels !is null);
    }

    private void update_subsurfaces() {
        Surface s = getSurface();
        assert(!!s); //never happens?
        mCache.length = s.subsurfaceCount();
    }

    private void killcache(bool for_free) {
        foreach (ref c; mCache) {
            foreach (s; c.entries) {
                SDL_FreeSurface(s.surface);
            }
            c.entries = null;
        }
        if (for_free) {
            mCache = null;
        }
        if (mSurfaceConverted) {
            SDL_FreeSurface(mSurfaceConverted);
            mSurfaceConverted = null;
        }
    }

    override void unlockData(Rect2i rc) {
        rc.fitInsideB(Rect2i(mSize));

        if (rc.size.quad_length <= 0)
            return;

        Rect2i fullrc = Rect2i(0, 0, mSize.x, mSize.y);

        assert(!!mSurfaceRGBA32.pixels);
        Color.RGBA32[] pixels = (cast(Color.RGBA32*)mSurfaceRGBA32.pixels)
            [0..mSize.x*mSize.y];

        Transparency oldt = mTransparency;
        Color.RGBA32 oldcc = mColorKey;

        checkTransparency(pixels[rc.p1.y*mSize.x + rc.p1.x .. mSize.x*mSize.y],
            mSize.x, rc.size, mTransparency, mColorKey);
        if (rc != fullrc) {
            //local changes can't make the full bitmap "better"
            mTransparency = mergeTransparency(oldt, mTransparency);
            //different colorkey wouldn't be useable
            if (mTransparency == Transparency.Colorkey && oldcc != mColorKey)
                mTransparency = Transparency.Alpha;
        }

        if (mTransparency == Transparency.Colorkey) {
            Rect2i crc = rc;

            //colorkey surfaces require that the pixel data is changed to
            //  correctly handle transparency (see updatePixels()), so allocate
            //  new memory for it
            if (!mSurfaceCCed) {
                auto rgba32 = sdlpfRGBA32();
                mSurfaceCCed = SDL_CreateRGBSurface(SDL_SWSURFACE, mSize.x,
                    mSize.y, 32, rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, 0);
                //xxx we're fucked
                if (!mSurfaceCCed)
                    throw new Exception("out of surface memory?");
                assert_good_surface(mSurfaceCCed);
                SDL_SetColorKey(mSurfaceCCed, SDL_SRCCOLORKEY,
                    mColorKey.uint_val);
                crc = fullrc; //update full surface
            }

            //if colorkey is enabled, one must "fix up" the updated pixels, so
            //one can be sure non-transparent pixels are actually equal to the
            //color key
            //reason: user code is allowed to use the alpha channel to set
            //  transparency (makes code simpler because they don't have to
            //  remember about colorkey... maybe that was a bad idea)
            auto ckey = mColorKey;
            ckey.a = 0;

            Color.RGBA32* dest_pixels = cast(Color.RGBA32*)mSurfaceCCed.pixels;
            assert(!!dest_pixels);

            size_t sz = crc.size.x;
            for (int y = crc.p1.y; y < crc.p2.y; y++) {
                size_t offset = mSize.x*y + crc.p1.x;
                auto pix_src = pixels.ptr + offset;
                auto pix_dest = dest_pixels + offset;
                blitWithColorkey(ckey, pix_src[0..sz], pix_dest[0..sz]);
            }
        } else {
            //make sure the whole surface will be updated next time transparency
            //  switches back to colorkey => simply free it
            if (mSurfaceCCed) {
                SDL_FreeSurface(mSurfaceCCed);
                mSurfaceCCed = null;
            }
        }

        //just invalidate the cache, can be recreated on demand
        killcache(false);
    }

    //NOTE: disregards screen alpha channel if non-existant
    private bool isDisplayFormat(SDL_Surface* s, bool alpha) {
        //pfAlphaScreen = best SDL format to render alpha surfaces to screen
        //at least, SDL_DisplayFormatAlpha always uses it
        auto pfAlphaScreen = sdlpfRGBA32();
        return cmpPixelFormat(s.format,
            alpha ? &pfAlphaScreen : mDrawDriver.mSDLScreen.format, true);
    }

    private bool allow_conversion() {
        return mEnableCache && mDrawDriver.opts.enable_conversion;
    }

    //create a sub-surface; mostly needed because rotozoom and
    //  convert_to_display work on full surfaces
    //note that the data isn't copied!
    private SDL_Surface* create_subsurface(Rect2i rc) {
        auto rgba32 = sdlpfRGBA32();
        auto nsurf = SDL_CreateRGBSurfaceFrom(mSurfaceRGBA32.pixels
            + mSurfaceRGBA32.pitch * rc.p1.y
            + rc.p1.x * mSurfaceRGBA32.format.BytesPerPixel,
            rc.size.x, rc.size.y, 32, mSurfaceRGBA32.pitch,
            rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, rgba32.Amask);
        //subsurfaces often get rotated and so on; always enabling alpha is
        //  simplest here
        SDL_SetAlpha(nsurf, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
        return nsurf;
    }

    private SDL_Surface* copy_surface(SDL_Surface* src) {
        assert(!!src);
        //stupid SDL... what's this flag mess?
        return SDL_ConvertSurface(src, src.format,
            src.flags & (SDL_RLEACCEL|SDL_SRCALPHA|SDL_SRCCOLORKEY));
    }

    //convert the surface to display format and RLE compress it
    //return new surface, or null on failure or format already ok
    private SDL_Surface* convert_to_display(SDL_Surface* surf) {
        assert(!!surf);

        if (!allow_conversion())
            return null;

        bool rle = mDrawDriver.opts.RLE;

        //xxx ok this really sucks now *shrug*
        if (surf is mSurfaceCCed) {
            auto nsurf = SDL_DisplayFormat(surf);
            if (nsurf && rle) {
                uint key = SDL_MapRGBA(nsurf.format, mColorKey.r, mColorKey.g,
                    mColorKey.b, mColorKey.a);
                SDL_SetColorKey(nsurf, SDL_SRCCOLORKEY | SDL_RLEACCEL, key);
            }
            return nsurf;
        }

        if (surf is mSurfaceRGBA32 && mTransparency == Transparency.None) {
            if (!rle && isDisplayFormat(surf, false))
                return null;
            auto nsurf = SDL_DisplayFormat(surf);
            assert(!!nsurf);
            //does this do anything at all?
            if (rle)
                SDL_SetColorKey(nsurf, SDL_RLEACCEL, 0);
            return nsurf;
        }

        //code path mostly for SubSurfaces or full alpha surfaces
        //don't really know if alpha is required (would need to loop over image
        //  data or add more complicated crap for guessing)
        if (rle || !isDisplayFormat(surf, true)) {
            auto nsurf = SDL_DisplayFormatAlpha(surf);
            assert(!!nsurf);
            //does RLE with alpha make any sense?
            if (rle)
                SDL_SetAlpha(nsurf, SDL_SRCALPHA | SDL_RLEACCEL,
                    SDL_ALPHA_OPAQUE);
            return nsurf;
        }

        return null;
    }

    //src must be in the RGBA32 format
    private Pixels pixels_from_sdl(SDL_Surface* src) {
        Pixels r;
        r.w = src.w;
        r.h = src.h;
        r.pixels = src.pixels;
        r.pitch = src.pitch;
        assert(src.format.BitsPerPixel == 32 && src.format.BytesPerPixel == 4);
        return r;
    }

    //possibly convert this surface to display format first
    package SDL_Surface* get_normal() {
        SDL_Surface* base = mSurfaceRGBA32;
        if (mSurfaceCCed && mTransparency == Transparency.Colorkey)
            base = mSurfaceCCed;

        if (!mSurfaceConverted && allow_conversion()) {
            //assumption: if someone draws this surface "normally" (=> no sub-
            //  surface stuff), he wants to use the full surface anyway
            //so, convert the full surface
            mSurfaceConverted = convert_to_display(base);
        }

        return mSurfaceConverted ? mSurfaceConverted : base;
    }

    package void get_from_effect_cache(SubSurface sub, BitmapEffect* effect,
        ref SDL_Surface* out_surface, ref Vector2i offset)
    {
        SubCache* cache = &mCache[sub.index];

        void get(ref CacheEntry e) {
            out_surface = e.surface;
            //if no effect, the center vector is 0/0 anyway
            if (effect) {
                float x1 = effect.center.x, x2 = effect.center.y;
                offset.x += cast(int)(-e.a * x1 + e.b * x2 + e.x);
                offset.y += cast(int)(-e.b * x1 - e.a * x2 + e.y);

                //code above is equivalent to the following
                /+
                //find out where the upper left corner in the surface returned
                //  by rotozoom is - this crap requires us to calculate this
                //  ourselves
                //the middle is (0,0) here
                auto upleft = (toVector2f(sub.size)/2.0f
                    - toVector2f(effect.center) * effect.scale;
                auto mid = Vector2f(e.surface.w, e.surface.h)/2.0f;
                upleft = mid - upleft.rotated(effect.rotate);
                offset -= toVector2i(upleft);
                +/
            }
        }

/+
        if (!effect) {
            //some sort of early-out-optimization
            get(cache.entries[0]);
            return;
        }
+/
        //sigh... the full-subsurface-thing wrecks up a lot
        BitmapEffect dummy;
        if (!effect)
            effect = &dummy;

        //number of rotation subdivisions for quantization
        //should be divisible by 8 (to have good 45° steps)
        int cRotUnits = 16;
        int cZoomUnitsHalf = 16; //scale subdivisions
        enum float cZoomMax = 4; //scale is clamped to [0, cZoomMax]
        if (mDrawDriver.opts.high_quality) {
            cRotUnits *= 4;
            cZoomUnitsHalf *= 4;
        }

        //search the cache
        //make sure the values are quantized (=> don't spam the cache)
        int k_mirror = (effect.mirrorX ? 1 : 0) | (effect.mirrorY ? 2 : 0);
        int k_rotate = realmod(cast(int)(
            effect.rotate/(PI*2.0)*cRotUnits + 0.5), cRotUnits);
        //zoom=1.0f must map to k_zoom=0 (else you have a useless cache entry)
        float ef_sc = min(effect.scale.x, effect.scale.y);  //xxx
        int k_zoom = cast(int)((clampRangeC(ef_sc, 0.0f, cZoomMax)-1.0f)
            /cZoomMax*cZoomUnitsHalf+0.5);

        if (ef_sc == 1.0f)
            assert(k_zoom == 0);

        foreach (ref e; cache.entries) {
            if (e.mirror == k_mirror
                && e.rotate == k_rotate
                && e.zoom == k_zoom)
            {
                get(e);
                return;
            }
        }

        CacheEntry entry;
        entry.mirror = k_mirror;
        entry.rotate = k_rotate;
        entry.zoom = k_zoom;

        SDL_Surface* surf = create_subsurface(sub.rect);
        assert(!!surf);

        if (k_mirror) {
            //copy because surface data isn't copied by create_subsurface
            auto nsurf = copy_surface(surf);
            assert(!!nsurf, "out of memory?");
            SDL_FreeSurface(surf);
            surf = nsurf;
            //mirror along X and/or Y axis
            assert(surf.pitch == sub.size.x * 4);
            if (k_mirror & 1)
                pixelsMirrorX(cast(Color.RGBA32*)surf.pixels, surf.pitch/4,
                    Vector2i(surf.w, surf.h));
            if (k_mirror & 2)
                pixelsMirrorY(cast(Color.RGBA32*)surf.pixels, surf.pitch/4,
                    Vector2i(surf.w, surf.h));
        }

        if (k_rotate || k_zoom) {
            double rot_deg = 1.0*k_rotate/cRotUnits*360.0;
            double rot_rad = rot_deg/180.0*PI;
            double zoom = 1.0*k_zoom/cZoomUnitsHalf*cZoomMax + 1.0;
            bool smooth = mDrawDriver.opts.high_quality;
            SDL_Surface* nsurf;
            rotozoomSurface(pixels_from_sdl(surf), -rot_deg, zoom, smooth,
                (out Pixels dst, int w, int h) {
                    nsurf = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, 32,
                        Color.cMaskR, Color.cMaskG, Color.cMaskB, Color.cMaskA);
                    SDL_SetAlpha(nsurf, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
                    SDL_FillRect(nsurf, null,
                        SDL_MapRGBA(nsurf.format, 0, 0, 0, 0));
                    dst = pixels_from_sdl(nsurf);
                }
            );
            assert(!!nsurf, "out of memory?");
            SDL_FreeSurface(surf);
            surf = nsurf;

            //explanation see elsewhere
            //in any case, it's better to use the real zoom/rot params, instead
            //  of the unrounded values passed by the user
            entry.a = cos(rot_rad) * zoom;
            entry.b = sin(rot_rad) * zoom;
            auto s = toVector2f(sub.size);
            entry.x = ( entry.a*s.x + -entry.b*s.y - surf.w) / 2;
            entry.y = ( entry.b*s.x +  entry.a*s.y - surf.h) / 2;
        }

        auto res = convert_to_display(surf);
        if (res) {
            SDL_FreeSurface(surf);
            surf = res;
        }

        entry.surface = surf;
        cache.entries ~= entry;

        get(entry);
    }

    override void newSubSurface(SubSurface ss) {
        update_subsurfaces();
    }
}


class SDLCanvas : Canvas {
    private {
        SDLDrawDriver mDrawDriver;

        Vector2i mTrans;
        SDL_Surface* mSurface;
    }

    this(SDLDrawDriver drv) {
        mDrawDriver = drv;
    }

    package void startScreenRendering() {
        assert(mSurface is null);

        mSurface = mDrawDriver.mSDLScreen;

        initFrame(mDrawDriver.mScreenSize);
    }

    package void stopScreenRendering() {
        assert(mSurface !is null);

        uninitFrame();

        SDL_Flip(mSurface);

        mSurface = null;
    }

    override int features() {
        return 0;
    }

    override void clear(Color color) {
        SDL_FillRect(mSurface, null, toSDLColor(color));
    }

    override void updateClip(Vector2i p1, Vector2i p2) {
        SDL_Rect rc;
        rc.x = cast(ushort)p1.x;
        rc.y = cast(ushort)p1.y;
        rc.w = cast(ushort)(p2.x-p1.x);
        rc.h = cast(ushort)(p2.y-p1.y);
        SDL_SetClipRect(mSurface, &rc);
    }

    override void updateTransform(Vector2i trans, Vector2f scale) {
        mTrans = trans;
    }

    //sourcePos and sourceSize null => draw full src surface
    private void sdl_draw(Vector2i at, SDL_Surface* src, ref SDL_Rect rc) {
        assert(src !is null);

        at += mTrans;

        SDL_Rect destrc;
        destrc.x = cast(short)at.x;
        destrc.y = cast(short)at.y; //destrc.w/h ignored by SDL_BlitSurface

        SDL_BlitSurface(src, &rc, mSurface, &destrc);

        if (mDrawDriver.opts.mark_alpha && sdlIsAlpha(src)) {
            auto c = Color(0,1,0);
            auto dp1 = at - mTrans;
            auto dp2 = dp1 + Vector2i(rc.w, rc.h);
            drawRect(Rect2i(dp1, dp2), c);
            drawLine(dp1, dp2, c);
            drawLine(dp1 + Vector2i(0, rc.h), dp1 + Vector2i(rc.w, 0), c);
        }
    }

    override void drawSprite(SubSurface source, Vector2i destPos,
        BitmapEffect* effect = null)
    {
        SDLSurface sdls =
            cast(SDLSurface)mDrawDriver.requireDriverResource(source.surface);
        SDL_Surface* src;
        sdls.get_from_effect_cache(source, effect, src, destPos);
        SDL_Rect rc;
        rc.w = cast(ushort)src.w;
        rc.h = cast(ushort)src.h;
        sdl_draw(destPos, src, rc);
    }

    override void drawPart(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        SDLSurface sdls =
            cast(SDLSurface)mDrawDriver.requireDriverResource(source);
        SDL_Rect rc;
        rc.x = cast(ushort)sourcePos.x;
        rc.y = cast(ushort)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        sdl_draw(destPos, sdls.get_normal(), rc);
    }

    private uint toSDLColor(Color color) {
        return simpleColorToSDLColor(mSurface, color);
    }

    //inefficient, wanted this for debugging
    override public void drawCircle(Vector2i center, int radius, Color color) {
        center += mTrans;
        uint c = toSDLColor(color);
        circle(center.x, center.y, radius,
            (int x1, int x2, int y) {
                doSetPixel(x1, y, c);
                doSetPixel(x2, y, c);
            }
        );
    }

    //xxx: replace by a more serious implementation
    override public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        circle(center.x, center.y, radius,
            (int x1, int x2, int y) {
                drawFilledRect(Rect2i(x1, y, x2, y+1), color);
            }
        );
    }

    //last pixel included
    //width not supported
    override public void drawLine(Vector2i from, Vector2i to, Color color, int width = 1)
    {
        //special cases for vlines/hlines
        if (from.y == to.y) {
            to.y++;
            if (from.x > to.x)
                swap(from.x, to.x);
            to.x++; //because the 2nd border is exclusive in drawFilledRect
            color.a = 1.0f;
            drawFilledRect(Rect2i(from, to), color);
            return;
        }
        if (from.x == to.x) {
            to.x++;
            if (from.y > to.y)
                swap(from.y, to.y);
            to.y++;
            color.a = 1.0f;
            drawFilledRect(Rect2i(from, to), color);
            return;
        }

        //my computer science prof said bresenham isn't it worth these days
        uint c = toSDLColor(color);
        Vector2f d = Vector2f((to-from).x,(to-from).y);
        Vector2f old = toVector2f(from + mTrans);
        int n = cast(int)(max(fabs(d.x), fabs(d.y)));
        d = d / cast(float)n;
        for (int i = 0; i < n; i++) {
            int px = cast(int)(old.x+0.5f);
            int py = cast(int)(old.y+0.5f);
            doSetPixel(px, py, c);
            old = old + d;
        }
    }

    public void setPixel(Vector2i p1, Color color) {
        //less lame now
        p1 += mTrans;
        doSetPixel(p1.x, p1.y, toSDLColor(color));
    }

    //warning: unlocked (you must call SDL_LockSurface before),
    //  unclipped (coordinate must be inside of sdlsurface.mReal.clip_rect)
    //of course doesn't obey alpha blending in any way
    static private void doSetPixelLow(SDL_Surface* s, int x, int y, uint color)
    {
        void* ptr = s.pixels + s.pitch*y + s.format.BytesPerPixel*x;
        switch (s.format.BitsPerPixel) {
            case 8:
                *cast(ubyte*)ptr = cast(ubyte)color;
                break;
            case 16:
                *cast(ushort*)ptr = cast(ushort)color;
                break;
            case 32:
                *cast(uint*)ptr = color;
                break;
            case 24:
                //this is why 32 bps is usually faster than 24 bps
                //xxx what about endian etc.
                ubyte* p = cast(ubyte*)ptr;
                p[0] = cast(ubyte)color;
                p[1] = cast(ubyte)(color >> 8);
                p[2] = cast(ubyte)(color >> 16);
                break;
            default:
                //err what?
        }
    }

    //like doSetPixel, but locks and clips (and operates on this surface)
    private void doSetPixel(int x, int y, uint color) {
        SDL_Surface* s = mSurface;
        assert(!!s);
        SDL_Rect* rc = &s.clip_rect;
        if (x < rc.x || y < rc.y || x >= rc.x + rc.w || y >= rc.y + rc.h)
            return;
        bool lock = SDL_MUSTLOCK(s);
        if (lock)
            SDL_LockSurface(s);
        doSetPixelLow(s, x, y, color);
        if (lock)
            SDL_UnlockSurface(s);
    }

    override void drawFilledRect(Rect2i rc, Color color) {
        if (rc.p1.x >= rc.p2.x || rc.p1.y >= rc.p2.y)
            return;
        int alpha = Color.toByte(color.a);
        if (!mDrawDriver.opts.high_quality) {
            //avoid alpha blending in low-quality
            //instead, this equals to an alpha-test
            alpha = alpha < cAlphaTestRef ? 0 : 255;
        }
        if (alpha == 0)
            return;
        if (alpha != 255) {
            //SDL doesn't do alpha blending with SDL_FillRect
            //=> we create a solid colored surface with alpha, and blend this
            Surface s = mDrawDriver.insanityCache(color);
            assert(s !is null);
            drawTiled(s, rc.p1, rc.size);
        } else {
            SDL_Rect rect;
            rc += mTrans;
            rect.x = cast(ushort)rc.p1.x;
            rect.y = cast(ushort)rc.p1.y;
            rect.w = cast(ushort)(rc.p2.x-rc.p1.x);
            rect.h = cast(ushort)(rc.p2.y-rc.p1.y);
            int res = SDL_FillRect(mSurface, &rect, toSDLColor(color));
            assert(res == 0);
        }
    }

    override public void drawVGradient(Rect2i rc, Color c1, Color c2) {
        auto dy = rc.p2.y - rc.p1.y;
        auto dc = c2 - c1;
        auto a = rc.p1;
        auto b = Vector2i(rc.p2.x, a.y + 1);
        auto y = max(rc.p1.y, visibleArea.p1.y) - rc.p1.y;
        auto end_y = min(rc.p2.y, visibleArea.p2.y) - rc.p1.y;
        a.y += y;
        b.y += y;
        while (y < end_y) {
            //SDL's FillRect is probably quite good at drawing solid horizontal
            //lines, so there's no reason not to use it
            //drawFilledRect of course still has a lot of overhead...
            drawFilledRect(Rect2i(a, b), c1 + dc * (1.0f*y/dy));
            a.y++;
            b.y++;
            y++;
        }
    }

    //unsupported
    override public void drawQuad(Surface tex, ref Vertex2f[4] quad) {
    }
}

