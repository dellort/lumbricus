module framework.drivers.draw_sdl;

import derelict.sdl.sdl;
import framework.framework;
import framework.globalsettings;
import framework.drivers.base_sdl;
import framework.rotozoom;
import framework.sdl.sdl;
import utils.vector2;
import utils.drawing;
import utils.misc;

import math = tango.math.Math;
import ieee = tango.math.IEEE;

import str = utils.string;

const cDrvName = "draw_sdl";

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

    override DriverSurface createSurface(SurfaceData data) {
        return new SDLSurface(this, data);
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
        return convertFromSDLSurface(mSDLScreen, Transparency.None, false);
    }

    override int getFeatures() {
        return mCanvas.features();
    }

    override void destroy() {
    }

    //return a surface with unspecified size containing this color
    //(used for drawing alpha blended rectangles)
    private Surface insanityCache(Color c) {
        uint key = c.toRGBA32().uint_val;

        Surface* s = key in mInsanityCache;
        if (s)
            return *s;

        const cTileSize = 64;

        Surface tile = new Surface(Vector2i(cTileSize), Transparency.Alpha);

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
    SurfaceData mData;
    SDL_Surface* mSurfaceRGBA32;
    SDL_Surface* mSurfaceConverted;

    SubCache[] mCache; //array is in sync to SurfaceData.subsurfaces[]
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
    this(SDLDrawDriver driver, SurfaceData data) {
        mData = data;
        mDrawDriver = driver;
        reinit();
    }

    //release data from driver surface
    override void destroy() {
        assert(!!mData, "double kill()?");
        releaseSurface();
        mData = null;
    }

    private void releaseSurface() {
        killcache();
        if (mSurfaceRGBA32) {
            SDL_FreeSurface(mSurfaceRGBA32);
            mSurfaceRGBA32 = null;
        }
    }

    private void killcache() {
        foreach (c; mCache) {
            foreach (s; c.entries) {
                SDL_FreeSurface(s.surface);
            }
        }
        mCache = null;
        if (mSurfaceConverted) {
            SDL_FreeSurface(mSurfaceConverted);
            mSurfaceConverted = null;
        }
    }

    void reinit() {
        releaseSurface();

        bool cc = mData.transparency == Transparency.Colorkey;

        //NOTE: SDL_CreateRGBSurfaceFrom doesn't copy the data... so, be sure
        //      to keep the pointer, so D won't GC it
        auto rgba32 = sdlpfRGBA32();
        if (!cc) {
            mSurfaceRGBA32 = SDL_CreateRGBSurfaceFrom(mData.data.ptr,
                mData.size.x, mData.size.y, 32, mData.pitch*4,
                rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, rgba32.Amask);
        } else {
            //colorkey surfaces require that the pixel data is changed to
            //  correctly handle transparency (see updatePixels()), so allocate
            //  new memory for it
            mSurfaceRGBA32 = SDL_CreateRGBSurface(SDL_SWSURFACE, mData.size.x,
                mData.size.y, 32, rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, 0);
        }
        if (!mSurfaceRGBA32) {
            throw new FrameworkException(
                myformat("couldn't create SDL surface, size={}", mData.size));
        }

        adjust_transparency_mode(mSurfaceRGBA32);

        updatePixels(Rect2i(mData.size));
        update_subsurfaces(mData.subsurfaces);
    }

    private void adjust_transparency_mode(SDL_Surface* src,
        bool force_alpha = false)
    {
        if (!src)
            return;

        //lol SDL - need to clear any transparency modes first
        //but I don't understand why (maybe because there's an alpha channel)
        SDL_SetAlpha(src, 0, 0);
        //SDL_SetColorKey(src, 0, 0);

        if (force_alpha || mData.transparency == Transparency.Alpha) {
            SDL_SetAlpha(src, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
        } else if (mData.transparency == Transparency.Colorkey) {
            uint key = simpleColorToSDLColor(src, mData.colorkey);
            SDL_SetColorKey(src, SDL_SRCCOLORKEY, key);
        }
    }

    void getPixelData() {
        assert(!SDL_MUSTLOCK(mSurfaceRGBA32));
    }

    void updatePixels(in Rect2i rc) {
        rc.fitInsideB(Rect2i(mData.size));

        if (rc.size.quad_length <= 0)
            return;

        if (mData.transparency == Transparency.Colorkey) {
            //if colorkey is enabled, one must "fix up" the updated pixels, so
            //one can be sure non-transparent pixels are actually equal to the
            //color key
            //reason: user code is allowed to use the alpha channel to set
            //  transparency (makes code simpler because they don't have to
            //  remember about colorkey... maybe that was a bad idea)
            auto ckey = mData.colorkey.toRGBA32();
            ckey.a = 0;

            assert(!(mSurfaceRGBA32.flags & SDL_RLEACCEL));
            assert(mSurfaceRGBA32.format.BytesPerPixel == 4);

            for (int y = rc.p1.y; y < rc.p2.y; y++) {
                Color.RGBA32* pix = mData.data.ptr + mData.pitch*y + rc.p1.x;
                auto pix_dest = cast(Color.RGBA32*)(mSurfaceRGBA32.pixels +
                    mSurfaceRGBA32.pitch*y) + rc.p1.x;
                SurfaceData.do_raw_copy_cc(ckey, rc.size.x, pix, pix_dest);
            }
        }

        //just invalidate the cache, can be recreated on demand
        killcache();

        //required minimal cache regeneration (this is a bit stupid)
        update_subsurfaces(mData.subsurfaces);
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
        return mData.enable_cache && mDrawDriver.opts.enable_conversion;
    }

    //create a sub-surface; mostly needed because rotozoom and
    //  convert_to_display work on full surfaces
    //note that the data isn't copied
    private SDL_Surface* create_subsurface(Rect2i rc) {
        auto rgba32 = sdlpfRGBA32();
        auto nsurf = SDL_CreateRGBSurfaceFrom(mSurfaceRGBA32.pixels
            + mSurfaceRGBA32.pitch * rc.p1.y
            + rc.p1.x * mSurfaceRGBA32.format.BytesPerPixel,
            rc.size.x, rc.size.y, 32, mSurfaceRGBA32.pitch,
            rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, rgba32.Amask);
        adjust_transparency_mode(nsurf);
        return nsurf;
    }

    private SDL_Surface* copy_surface(SDL_Surface* src) {
        assert(!!src);
        //stupid SDL... what's this flag mess?
        return SDL_ConvertSurface(src, src.format,
            src.flags & (SDL_RLEACCEL|SDL_SRCALPHA|SDL_SRCCOLORKEY));
    }

    //convert the surface to display format and RLE compress it
    //return new surface, or null on failure
    private SDL_Surface* convert_to_display(SDL_Surface* surf) {
        assert(!!surf);

        if (!allow_conversion())
            return null;

        bool rle = mDrawDriver.opts.RLE;

        SDL_Surface* nsurf;
        bool colorkey;
        switch (mData.transparency) {
            case Transparency.Colorkey:
                colorkey = true;
                //yay, first time in my life I want to fall through!
            case Transparency.None: {
                if (rle || !isDisplayFormat(surf, false)) {
                    nsurf = SDL_DisplayFormat(surf);
                    assert(!!nsurf);
                    if (rle) {
                        uint key = simpleColorToSDLColor(nsurf, mData.colorkey);
                        SDL_SetColorKey(nsurf, (colorkey ? SDL_SRCCOLORKEY : 0)
                            | SDL_RLEACCEL, key);
                    }
                }
                break;
            }
            case Transparency.Alpha: {
                if (rle || !isDisplayFormat(surf, true)) {
                    nsurf = SDL_DisplayFormatAlpha(surf);
                    assert(!!nsurf);
                    //does RLE with alpha make any sense?
                    if (rle) {
                        SDL_SetAlpha(nsurf, SDL_SRCALPHA | SDL_RLEACCEL,
                            SDL_ALPHA_OPAQUE);
                    }
                }
                break;
            }
            default:
                assert(false);
        }

        return nsurf;
    }

    private SDL_Surface* convert_free(SDL_Surface* src) {
        auto res = convert_to_display(src);
        if (res) {
            SDL_FreeSurface(src);
            return res;
        } else {
            return src;
        }
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

    //includes special handling for the alpha value: if completely transparent,
    //and if using colorkey transparency, return the colorkey
    final uint colorToSDLColor(Color color) {
        if (mData.transparency == Transparency.Colorkey
            && color.a <= Color.epsilon)
        {
            //color = mData.colorkey;
            return mSurfaceRGBA32.format.colorkey;
        }
        return simpleColorToSDLColor(mSurfaceRGBA32, color);
    }

    //possibly convert this surface to display format first
    package SDL_Surface* get_normal() {
        if (!mSurfaceConverted && allow_conversion()) {
            //assumption: if someone draws this surface "normally" (=> no sub-
            //  surface stuff), he wants to use the full surface anyway
            //so, convert the full surface
            mSurfaceConverted = convert_to_display(mSurfaceRGBA32);
        }
        return mSurfaceConverted ? mSurfaceConverted : mSurfaceRGBA32;
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

        if (!effect) {
            //some sort of early-out-optimization
            get(cache.entries[0]);
            return;
        }

        //number of rotation subdivisions for quantization
        //should be divisible by 8 (to have good 45° steps)
        int cRotUnits = 16;
        int cZoomUnitsHalf = 16; //scale subdivisions
        const float cZoomMax = 4; //scale is clamped to [0, cZoomMax]
        if (mDrawDriver.opts.high_quality) {
            cRotUnits *= 4;
            cZoomUnitsHalf *= 4;
        }

        //search the cache
        //make sure the values are quantized (=> don't spam the cache)
        int k_mirror = effect.mirrorY ? 1 : 0;
        int k_rotate = realmod(cast(int)(
            effect.rotate/(math.PI*2.0)*cRotUnits + 0.5), cRotUnits);
        //zoom=1.0f must map to k_zoom=0 (else you have a useless cache entry)
        float ef_sc = effect.scale.length;  //xxx
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

        if (k_mirror == 1) {
            //copy
            auto nsurf = copy_surface(surf);
            assert(!!nsurf, "out of memory?");
            SDL_FreeSurface(surf);
            surf = nsurf;
            //mirror along Y axis
            SurfaceData.doMirrorY_raw(cast(Color.RGBA32*)surf.pixels,
                surf.pitch, Vector2i(surf.w, surf.h));
        }

        if (k_rotate || k_zoom) {
            double rot_deg = 1.0*k_rotate/cRotUnits*360.0;
            double rot_rad = rot_deg/180.0*math.PI;
            double zoom = 1.0*k_zoom/cZoomUnitsHalf*cZoomMax + 1.0;
            bool smooth = mDrawDriver.opts.high_quality;
            SDL_Surface* nsurf;
            rotozoomSurface(pixels_from_sdl(surf), -rot_deg, zoom, smooth,
                (out Pixels dst, int w, int h) {
                    nsurf = SDL_CreateRGBSurface(SDL_SWSURFACE, w, h, 32,
                        Color.cMaskR, Color.cMaskG, Color.cMaskB, Color.cMaskA);
                    adjust_transparency_mode(nsurf, smooth);
                    SDL_FillRect(nsurf, null, colorToSDLColor(Color.Transparent));
                    dst = pixels_from_sdl(nsurf);
                }
            );
            assert(!!nsurf, "out of memory?");
            SDL_FreeSurface(surf);
            surf = nsurf;

            //explanation see elsewhere
            //in any case, it's better to use the real zoom/rot params, instead
            //  of the unrounded values passed by the user
            entry.a = math.cos(rot_rad) * zoom;
            entry.b = math.sin(rot_rad) * zoom;
            auto s = toVector2f(sub.size);
            entry.x = ( entry.a*s.x + -entry.b*s.y - surf.w) / 2;
            entry.y = ( entry.b*s.x +  entry.a*s.y - surf.h) / 2;
        }

        entry.surface = convert_free(surf);
        cache.entries ~= entry;

        get(entry);
    }

    override void newSubSurface(SubSurface ss) {
        update_subsurfaces(mData.subsurfaces[ss.index..ss.index+1]);
    }

    private void update_subsurfaces(SubSurface[] ss) {
        foreach (s; ss) {
            if (s.index >= mCache.length) {
                mCache.length = s.index+1;
            }

            //create entry 0 for the cache (it's an "optimization")
            SubCache* cache = &mCache[s.index];
            if (cache.entries.length > 0)
                continue;

            cache.entries.length = 1;
            CacheEntry* entry = &cache.entries[0];

            //alternatively, could just use get_normal() (=> old behaviour)
            SDL_Surface* sub = create_subsurface(s.rect);
            assert(!!sub, "out of memory?"); //could handle this better
            entry.surface = convert_free(sub);
        }
    }

    void getInfos(out char[] desc, out uint extra_data) {
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

    int features() {
        return 0;
    }

    void clear(Color color) {
        SDL_FillRect(mSurface, null, toSDLColor(color));
    }

    override void updateClip(Vector2i p1, Vector2i p2) {
        SDL_Rect rc;
        rc.x = p1.x;
        rc.y = p1.y;
        rc.w = p2.x-p1.x;
        rc.h = p2.y-p1.y;
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
        SDLSurface sdls = cast(SDLSurface)source.surface.getDriverSurface();
        SDL_Surface* src;
        sdls.get_from_effect_cache(source, effect, src, destPos);
        SDL_Rect rc;
        rc.w = src.w;
        rc.h = src.h;
        sdl_draw(destPos, src, rc);
    }

    void drawPart(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        SDLSurface sdls = cast(SDLSurface)source.getDriverSurface();
        SDL_Rect rc;
        rc.x = sourcePos.x;
        rc.y = sourcePos.y;
        rc.w = sourceSize.x;
        rc.h = sourceSize.y;
        sdl_draw(destPos, sdls.get_normal(), rc);
    }

    private uint toSDLColor(Color color) {
        return simpleColorToSDLColor(mSurface, color);
    }

    //inefficient, wanted this for debugging
    public void drawCircle(Vector2i center, int radius, Color color) {
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
    public void drawFilledCircle(Vector2i center, int radius,
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
    public void drawLine(Vector2i from, Vector2i to, Color color, int width = 1)
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
        int n = cast(int)(max(ieee.fabs(d.x), ieee.fabs(d.y)));
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
                *cast(ubyte*)ptr = color;
                break;
            case 16:
                *cast(ushort*)ptr = color;
                break;
            case 32:
                *cast(uint*)ptr = color;
                break;
            case 24:
                //this is why 32 bps is usually faster than 24 bps
                //xxx what about endian etc.
                ubyte* p = cast(ubyte*)ptr;
                p[0] = color;
                p[1] = color >> 8;
                p[2] = color >> 16;
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
            Texture s = mDrawDriver.insanityCache(color);
            assert(s !is null);
            drawTiled(s, rc.p1, rc.size);
        } else {
            SDL_Rect rect;
            rc += mTrans;
            rect.x = rc.p1.x;
            rect.y = rc.p1.y;
            rect.w = rc.p2.x-rc.p1.x;
            rect.h = rc.p2.y-rc.p1.y;
            int res = SDL_FillRect(mSurface, &rect, toSDLColor(color));
            assert(res == 0);
        }
    }

    public void drawVGradient(Rect2i rc, Color c1, Color c2) {
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
    public void drawQuad(Surface tex, Vertex2f[4] quad) {
    }
}

