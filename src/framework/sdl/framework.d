module framework.sdl.framework;

import framework.framework;
import framework.font;
import framework.event;
import std.stream;
import std.stdio;
import std.string;
import utils.vector2;
import framework.sdl.rwops;
import framework.sdl.soundmixer;
import framework.sdl.font;
import derelict.sdl.sdl;
import derelict.sdl.image;
import derelict.sdl.ttf;
import framework.sdl.keys;
import math = std.math;
import utils.time;
import utils.perf;
import utils.drawing;
import utils.misc : min, max, sizeToHuman;
import utils.weaklist;

package {
    FrameworkSDL gFrameworkSDL;

    struct SurfaceData {
        SDL_Surface* preal, pcached;

        void doFree() {
            if (preal)
                SDL_FreeSurface(preal);
            if (preal !is pcached && pcached)
                SDL_FreeSurface(pcached);
        }
    }
    WeakList!(SDLSurface, SurfaceData) gSurfaces;
}

debug import std.stdio;

debug {
    //version = MeasureImgLoadTime;
    version = DrawStats;
    //with this hack, all alpha surfaces (for which texture cache is enabled)
    //are drawn with a black box around them
    //version = MarkAlpha;
}

version (MeasureImgLoadTime) {
    import std.perf;
    Time gSummedImageLoadingTime;
    uint gSummedImageLoadingSize;
    uint gSummedImageLoadingSizeUncompressed;
    uint gSummedImageLoadingCount;
}

//SDL_Color.unused contains the alpha value
static SDL_Color ColorToSDLColor(Color color) {
    SDL_Color col;
    col.r = cast(ubyte)(255*color.r);
    col.g = cast(ubyte)(255*color.g);
    col.b = cast(ubyte)(255*color.b);
    col.unused = cast(ubyte)(255*color.a);
    return col;
}

//NOTE: there's also GLTexture :)
package class SDLTexture : Texture {
    //mOriginalSurface is the image source, and mCached is the image converted
    //to screen format
    private SDLSurface mOriginalSurface;
    private bool mEnableCache; //see checkCaching()

    package this(SDLSurface source, bool enableCache = true) {
        mOriginalSurface = source;
        mEnableCache = enableCache;
        assert(source !is null);
    }

    private bool cachingOK() {
        return mEnableCache && gFrameworkSDL.mAllowTextureCache;
    }

    //if gFramework.mAllowTextureCache changed
    package void checkCaching() {
        //if caching is wished (user requests it and framework allows it)
        bool shouldCache = cachingOK();
        //if currently there's a cached surface
        //mCached can be null, mReal, or a surface with a converted surface
        bool doesCache = (mOriginalSurface.mCached !is mOriginalSurface.mReal);
        //if different, clear the cache -> getDrawSurface() does the right thing
        if (shouldCache != doesCache) {
            releaseCache();
        }
    }

    public void setCaching(bool state) {
        releaseCache();
        mEnableCache = state;
    }

    public Vector2i size() {
        return mOriginalSurface.size;
    }

    //return surface that's actually drawn
    package SDL_Surface* getDrawSurface() {
        if (!mOriginalSurface.mCached)
            checkIfScreenFormat();
        return mOriginalSurface.mCached;
        //return mOriginalSurface.mReal;
    }

    public Surface getSurface() {
        return mOriginalSurface;
    }

    //check if s is of format fmt
    //don't know if implementation is correct; but it worked for me
    private static bool checkFormat(SDL_Surface* s, DisplayFormat fmt) {
        PixelFormat f = gFrameworkSDL.findPixelFormat(fmt);
        PixelFormat f2 = gFrameworkSDL.sdlFormatToFramework(s.format);
        return f == f2;
    }

    //convert the image to the current screen format (this is done once)
    package void checkIfScreenFormat() {
        //xxx insert check if screen depth has changed at all!
        //xxx also check if you need to convert it at all
        //else: performance problem with main level surface
        if (!mOriginalSurface.mCached) {
            assert(mOriginalSurface !is null);
            if (!cachingOK()) {
                mOriginalSurface.mCached = mOriginalSurface.mReal;
                return;
            }
            SDL_Surface* conv_from = mOriginalSurface.mReal;
            assert(conv_from !is null);

            SDL_Surface* nsurf;
            switch (mOriginalSurface.mTransp) {
                case Transparency.Colorkey, Transparency.None: {
                    if (!checkFormat(conv_from, DisplayFormat.Screen))
                        nsurf = SDL_DisplayFormat(conv_from);
                    break;
                }
                case Transparency.Alpha: {
                    if (!checkFormat(conv_from, DisplayFormat.ScreenAlpha)) {
                        nsurf = SDL_DisplayFormatAlpha(conv_from);
                        version (MarkAlpha)
                            doMarkAlpha(nsurf);
                    }
                    break;
                }
                default:
                    assert(false);
            }
            mOriginalSurface.mCached = nsurf ? nsurf : mOriginalSurface.mReal;
        }
    }

    void releaseCache() {
        if (mOriginalSurface.mCached) {
            if (mOriginalSurface.mCached !is mOriginalSurface.mReal)
                SDL_FreeSurface(mOriginalSurface.mCached);
            mOriginalSurface.mCached = null;
        }
    }

    void clearCache() {
        releaseCache();
    }
}

version (MarkAlpha) {
    private void doMarkAlpha(SDL_Surface* surface) {
        Canvas c = (new SDLSurface(surface, false)).startDraw();
        auto x1 = Vector2i(0), x2 = c.realSize()-Vector2i(1);
        c.drawRect(x1, x2, Color(0));
        c.drawLine(x1, x2, Color(0));
        c.drawLine(x2.Y, x2.X, Color(0));
        c.endDraw();
    }
}

public class SDLSurface : Surface {
    //mReal: original surface (any pixelformat)
    SDL_Surface* mReal;
    //if non-null, this contains the surface data (to prevent GCing it)
    //void* mData; incorrect, can be collected before sdl-surface is free'd
    SDLCanvas mCanvas;
    Transparency mTransp;
    Color mColorkey;

    SDLTexture mSDLTexture;
    SDL_Surface* mCached;

    bool mDidInit, mOwns;

    //own: if this Surface is allowed to free the SDL_Surface
    void setSurface(SDL_Surface* realsurface, bool own) {
        assert(mReal is null);
        mReal = realsurface;
        assert(!mDidInit); //execute gSurfaces.add() only once
        mDidInit = true;
        mOwns = own;
        gSurfaces.add(this);
    }

    void doFree(bool finalizer) {
        SurfaceData d;
        if (mOwns) {
            d.preal = mReal;
            d.pcached = mCached;
        }
        mReal = mCached = null;
        if (!finalizer) {
            //if not from finalizer, actually can call C functions
            //so free it now (and not later, by lazy freeing)
            d.doFree();
            d = SurfaceData(); //reset
        }
        gSurfaces.remove(this, finalizer, d);
    }

    ~this() {
        doFree(true);
    }

    //to avoid memory leaks
    //warning: only pushes the surface data into the kill list
    void free() {
        doFree(false);
    }

    bool valid() {
        return !!mReal;
    }

    //xxx: functionality duplicated across a few places
    bool hasCache() {
        return mCached && (mReal !is mCached);
    }

    public Surface clone() {
        assert(mReal !is null);
        auto n = SDL_ConvertSurface(mReal, mReal.format, mReal.flags);
        auto res = new SDLSurface(n, true);
        res.mTransp = mTransp;
        res.mColorkey = mColorkey;
        return res;
    }

    public Canvas startDraw() {
        if (mCanvas is null) {
            mCanvas = new SDLCanvas(this);
        }
        mCanvas.startDraw();
        return mCanvas;
    }

    public Vector2i size() {
        assert(mReal !is null);
        return Vector2i(mReal.w, mReal.h);
    }

    private void toSDLPixelFmt(PixelFormat format, out SDL_PixelFormat fmt) {
        //according to FreeNode/#SDL, SDL fills the loss/shift by itsself
        fmt.BitsPerPixel = format.depth;
        fmt.BytesPerPixel = format.bytes;
        fmt.Rmask = format.mask_r;
        fmt.Gmask = format.mask_g;
        fmt.Bmask = format.mask_b;
        fmt.Amask = format.mask_a;
        //xxx: what about fmt.colorkey and fmt.alpha? (can it be ignored here?)
        //should use of the palette be enabled?
        fmt.palette = null;
    }

    public void forcePixelFormat(PixelFormat format) {
        assert(mReal !is null);
        SDL_PixelFormat fmt;
        toSDLPixelFmt(format, fmt);
        SDL_Surface* s = SDL_ConvertSurface(mReal, &fmt, SDL_SWSURFACE);
        assert(s !is null);
        //xxx really need to track references to the SDL surface
        // i.e. using textures which reference to this will crash, omg.
        free();
        mReal = s;
    }

    public void lockPixels(out void* pixels, out uint pitch) {
        assert(mReal !is null);
        SDL_LockSurface(mReal);
        pixels = mReal.pixels;
        pitch = mReal.pitch;
    }
    public void unlockPixels() {
        SDL_UnlockSurface(mReal);
    }

    public void lockPixelsRGBA32(out void* pixels, out uint pitch) {
        assert(mReal !is null);
        //xxx: this is a fast, but dirty check for the correct format
        if (mReal.format.BytesPerPixel != 4
            || mReal.format.Rmask != 0x00ff0000
            || mReal.format.Gmask != 0x0000ff00
            || mReal.format.Bmask != 0x000000ff
            || mReal.format.Amask != 0xff000000)
        {
            forcePixelFormat(gFramework.findPixelFormat(DisplayFormat.RGBA32));
        }
        lockPixels(pixels, pitch);
    }

    //only for createMirroredY()
    void doMirror(T)(SDLSurface ret) {
        assert(mReal.format.BytesPerPixel == T.sizeof);
        assert(mReal.format.BytesPerPixel == ret.mReal.format.BytesPerPixel);
        assert(mReal.w == ret.mReal.w);
        assert(mReal.h == ret.mReal.h);
        SDL_LockSurface(mReal);
        SDL_LockSurface(ret.mReal);
        for (uint y = 0; y < mReal.h; y++) {
            T* src = cast(T*)(mReal.pixels+y*mReal.pitch+mReal.w*T.sizeof);
            T* dst = cast(T*)(ret.mReal.pixels+y*ret.mReal.pitch);
            for (uint x = 0; x < mReal.w; x++) {
                src--;
                *dst = *src;
                dst++;
            }
        }
        SDL_UnlockSurface(ret.mReal);
        SDL_UnlockSurface(mReal);
    }
    public Surface createMirroredY() {
        //clone the SDL surface
        //wouldn't need to actually copy the surface, doMirror below uses this
        //surface and copies it into the dest, mirrored

        //xxx some violence
        //if (mReal.format.BytesPerPixel == 3) {
            //forcePixelFormat(gFramework.findPixelFormat(DisplayFormat.RGBA32));
        //}
        //xxx gross hack
        mReal = SDL_DisplayFormat(mReal);

        SDL_Surface* ns = SDL_ConvertSurface(mReal, mReal.format, SDL_SWSURFACE);
        auto ret = new SDLSurface(ns);
        ret.initTransp(mTransp);

        switch (mReal.format.BytesPerPixel) {
            case 1: doMirror!(ubyte)(ret); break;
            case 2: doMirror!(ushort)(ret); break;
            case 4: doMirror!(uint)(ret); break;
            default:
                std.stdio.writefln("format.BytesPerPixel = %s", mReal.format.BytesPerPixel);
                assert(false);
        }

        return ret;
    }

    //scale the alpha values of the pixels in the surface to be in the
    //range 0.0 .. scale
    void scaleAlpha(float scale) {
        assert(mReal !is null);
        ubyte nalpha = cast(ubyte)(scale * 255);
        if (nalpha == 255)
            return;
        //xxx code relies on exact surface format produced by SDL_TTF
        forcePixelFormat(gFramework.findPixelFormat(DisplayFormat.RGBA32));
        SDL_LockSurface(mReal);
        assert(mReal.format.BytesPerPixel == 4);
        for (int y = 0; y < mReal.h; y++) {
            ubyte* ptr = cast(ubyte*)mReal.pixels;
            ptr += y*mReal.pitch;
            for (int x = 0; x < mReal.w; x++) {
                uint alpha = ptr[3];
                alpha = (alpha*nalpha)/255;
                ptr[3] = cast(ubyte)(alpha);
                ptr += 4;
            }
        }
        SDL_UnlockSurface(mReal);
    }

    public void enableColorkey(Color colorkey = cStdColorkey) {
        assert(mReal);

        uint key = colorToSDLColor(colorkey);
        mColorkey = colorkey;
        SDL_SetColorKey(mReal, SDL_SRCCOLORKEY, key);
        mTransp = Transparency.Colorkey;
    }

    public void enableAlpha() {
        assert(mReal !is null);

        SDL_SetAlpha(mReal, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
        mTransp = Transparency.Alpha;
    }

    public Color colorkey() {
        switch (mTransp) {
            case Transparency.Alpha:
                return Color(0, 0, 0, 0);
            default:
                return mColorkey;
        }
    }

    public Transparency transparency() {
        return mTransp;
    }

    //following: all constructors
    this(SDL_Surface* surface, bool owns = false) {
        setSurface(surface, owns);
    }
    //create a new surface using current depth
    //xxx: find better solution for enabling alpha...
    this(Vector2i size, DisplayFormat fmt, Transparency transp) {
        PixelFormat format = gFrameworkSDL.findPixelFormat(fmt);
        auto ns = SDL_CreateRGBSurface(SDL_HWSURFACE, size.x, size.y,
            format.depth, format.mask_r, format.mask_g, format.mask_b,
            format.mask_a);
        if (!ns) {
            writefln("%d %d %d", size.x, size.y, format.depth);
            throw new Exception("couldn't create surface (1)");
        }
        setSurface(ns, true);
        initTransp(transp);
    }
    //create from stream (using SDL_Image)
    this(Stream st, Transparency transp) {
        SDL_RWops* ops = rwopsFromStream(st);
        version (MeasureImgLoadTime) {
            auto counter = new PerformanceCounter();
            counter.start();
        }
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        version (MeasureImgLoadTime) {
            counter.stop();
            gSummedImageLoadingTime += timeMusecs(counter.microseconds);
            gSummedImageLoadingCount++;
            gSummedImageLoadingSize += st.size;
            if (surf) {
                //estimated
                gSummedImageLoadingSizeUncompressed +=
                    surf.w*surf.h*surf.format.BytesPerPixel;
            }
            writefln("summed image loading time: %s, count: %s, size: %s, "
                "uncompressed size: %s", gSummedImageLoadingTime,
                gSummedImageLoadingCount, gSummedImageLoadingSize,
                gSummedImageLoadingSizeUncompressed);
        }
        if (surf) {
            setSurface(surf, true);
        } else {
            char* err = IMG_GetError();
            throw new Exception("image couldn't be loaded: "~std.string.toString(err));
        }
        initTransp(transp);
    }
    /+
    //create from bitmap data, see Framework.createImage
    this(uint w, uint h, uint pitch, PixelFormat format, Transparency transp,
        void* data)
    {
        if (!data) {
            void[] alloc;
            alloc.length = pitch*h*format.bytes;
            data = alloc.ptr;
        }
        mData = data;
        //possibly incorrect
        //xxx: cf. SDLSurface(Vector2i) constructor!
        auto ns = SDL_CreateRGBSurfaceFrom(data, w, h, format.depth, pitch,
            format.mask_r, format.mask_g, format.mask_b, format.mask_a);
        if (!ns)
            throw new Exception("couldn't create surface (2)");
        setSurface(ns, true);
        initTransp(transp);
    }
    +/

    private void initTransp(Transparency transp) {
        if (transp == Transparency.AutoDetect) {
            //try to auto-detect transparency
            //if no alpha is used, maybe it uses a colorkey
            assert(mReal !is null);
            transp = mReal.format.Amask != 0 ? Transparency.Alpha
                : Transparency.Colorkey;
        }
        switch (transp) {
            case Transparency.Alpha: {
                enableAlpha();
                break;
            }
            case Transparency.Colorkey: {
                //use the default colorkey!
                enableColorkey();
                break;
            }
            default: //rien
        }
    }

    //includes special handling for the alpha value: if completely transparent,
    //and if using colorkey transparency, return the colorkey
    uint colorToSDLColor(Color color) {
        ubyte alpha = cast(ubyte)(255*color.a);
        if (mTransp == Transparency.Colorkey && alpha == 255) {
            color = mColorkey;
            alpha = cast(ubyte)(255*color.a);
        }
        return SDL_MapRGBA(mReal.format,cast(ubyte)(255*color.r),
            cast(ubyte)(255*color.g),cast(ubyte)(255*color.b), alpha);
    }

    //create a SDLTexture in SDL mode, and a GLTexture in OpenGL mode
    Texture createTexture() {
        if (gFrameworkSDL.useGL) {
            //return new GLTexture(this);
            assert(false);
        } else {
            if (!mSDLTexture) {
                mSDLTexture = new SDLTexture(this);
            }
            return mSDLTexture;
        }
    }

    Texture createBitmapTexture() {
        return new SDLTexture(this, false);
    }
}

public class SDLCanvas : Canvas {
    const int MAX_STACK = 20;

    private {
        struct State {
            SDL_Rect clip;
            Vector2i translate;
            Vector2i clientstart, clientsize;
        }

        Vector2i mTrans;
        State[MAX_STACK] mStack;
        uint mStackTop; //point to next free stack item (i.e. 0 on empty stack)

        Vector2i mClientSize;
        Vector2i mClientStart;  //origin of window
        SDLSurface sdlsurface;
    }

    package void startDraw() {
        assert(mStackTop == 0);
        SDL_SetClipRect(sdlsurface.mReal, null);
        mTrans = Vector2i(0, 0);
        pushState();
    }
    void endDraw() {
        popState();
        assert(mStackTop == 0);
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        gFrameworkSDL.mWasteTime.start();

        mStack[mStackTop].clip = sdlsurface.mReal.clip_rect;
        mStack[mStackTop].translate = mTrans;
        mStack[mStackTop].clientstart = mClientStart;
        mStack[mStackTop].clientsize = mClientSize;
        mStackTop++;

        gFrameworkSDL.mWasteTime.stop();
    }

    public void popState() {
        assert(mStackTop > 0);

        gFrameworkSDL.mWasteTime.start();

        mStackTop--;
        SDL_Rect* rc = &mStack[mStackTop].clip;
        SDL_SetClipRect(sdlsurface.mReal, rc);
        mTrans = mStack[mStackTop].translate;
        mClientStart = mStack[mStackTop].clientstart;
        mClientSize = mStack[mStackTop].clientsize;

        gFrameworkSDL.mWasteTime.stop();
    }

    public void setWindow(Vector2i p1, Vector2i p2) {
        gFrameworkSDL.mWasteTime.start();

        addclip(p1, p2);
        mTrans = p1 + mTrans;
        mClientStart = p1 + mTrans;
        mClientSize = p2 - p1;

        gFrameworkSDL.mWasteTime.stop();
    }

    //xxx: unify with clip(), or whatever, ..., etc.
    //oh, and this is actually needed in only a _very_ few places (scrolling)
    private void addclip(Vector2i p1, Vector2i p2) {
        p1 += mTrans; p2 += mTrans;
        SDL_Rect rc = sdlsurface.mReal.clip_rect;

        int rcx2 = rc.w + rc.x;
        int rcy2 = rc.h + rc.y;

        //common rect of old cliprect and (p1,p2)
        rc.x = max!(int)(rc.x, p1.x);
        rc.y = max!(int)(rc.y, p1.y);
        rcx2 = min!(int)(rcx2, p2.x);
        rcy2 = min!(int)(rcy2, p2.y);

        rc.w = max!(int)(rcx2 - rc.x, 0);
        rc.h = max!(int)(rcy2 - rc.y, 0);

        SDL_SetClipRect(sdlsurface.mReal, &rc);
    }

    public void clip(Vector2i p1, Vector2i p2) {
        p1 += mTrans; p2 += mTrans;
        SDL_Rect rc;
        rc.x = p1.x;
        rc.y = p1.y;
        rc.w = p2.x-p1.x;
        rc.h = p2.y-p1.y;
        SDL_SetClipRect(sdlsurface.mReal, &rc);
    }

    public void translate(Vector2i offset) {
        mTrans -= offset;
    }

    //definition: return client coords for screen coord (0, 0)
    public Vector2i clientOffset() {
        return -mTrans;
    }

    public Vector2i realSize() {
        return sdlsurface.size();
    }
    public Vector2i clientSize() {
        return mClientSize;
    }

    public Rect2i getVisible() {
        Rect2i res;
        SDL_Rect rc = sdlsurface.mReal.clip_rect;
        res.p1.x = rc.x;
        res.p1.y = rc.y;
        res.p2.x = rc.x + rc.w;
        res.p2.y = rc.y + rc.h;
        res.p1 -= mTrans;
        res.p2 -= mTrans;
        return res;
    }

    this(SDLSurface surf) {
        mTrans = Vector2i(0, 0);
        mStackTop = 0;
        sdlsurface = surf;
        //pushState();
    }

    package Surface surface() {
        return sdlsurface;
    }

    public void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        assert(source !is null);
        destPos += mTrans;
        SDLTexture sdls = cast(SDLTexture)source;
        //when this is null, maybe the user passed a GLTexture?
        assert(sdls !is null);

        SDL_Rect rc, destrc;
        rc.x = cast(short)sourcePos.x;
        rc.y = cast(short)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        destrc.x = cast(short)destPos.x;
        destrc.y = cast(short)destPos.y; //destrc.w/h ignored by SDL_BlitSurface
        SDL_Surface* src = sdls.getDrawSurface();
        //if (!src)
        //    src = sdls.mReal;
        assert(src !is null);
        version(DrawStats) gFrameworkSDL.mDrawTime.start();
        int res = SDL_BlitSurface(src, &rc, sdlsurface.mReal, &destrc);
        version(DrawStats) gFrameworkSDL.mDrawTime.stop();
        assert(res == 0);
    }

    //inefficient, wanted this for debugging
    public void drawCircle(Vector2i center, int radius, Color color) {
        circle(center.x, center.y, radius,
            (int x1, int x2, int y) {
                setPixel(Vector2i(x1, y), color);
                setPixel(Vector2i(x2, y), color);
            }
        );
    }

    //xxx: replace by a more serious implementation
    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        circle(center.x, center.y, radius,
            (int x1, int x2, int y) {
                drawFilledRect(Vector2i(x1, y), Vector2i(x2, y+1), color, false);
            }
        );
    }

    public void drawLine(Vector2i from, Vector2i to, Color color) {
        Vector2f d = Vector2f((to-from).x,(to-from).y);
        Vector2f old = Vector2f(from.x, from.y);
        int n = cast(int)(math.fmax(math.fabs(d.x), math.fabs(d.y)));
        d = d / cast(float)n;
        for (int i = 0; i < n; i++) {
            int px = cast(int)(old.x+0.5f);
            int py = cast(int)(old.y+0.5f);
            setPixel(Vector2i(px, py), color);
            old = old + d;
        }
    }

    public void setPixel(Vector2i p1, Color color) {
        //xxx: ultra LAME!
        drawFilledRect(p1, p1+Vector2i(1,1), color);
    }

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
        drawLine(p1, Vector2i(p1.x, p2.y), color);
        drawLine(Vector2i(p1.x, p2.y), p2, color);
        drawLine(p2, Vector2i(p2.x, p1.y), color);
        drawLine(Vector2i(p2.x, p1.y), p1, color);
    }

    override public void drawFilledRect(Vector2i p1, Vector2i p2, Color color,
        bool properalpha = true)
    {
        int alpha = cast(ubyte)(color.a*255);
        if (alpha == 0 && properalpha)
            return; //xxx: correct?
        if (true && alpha != 255 && properalpha) {
            //quite insane insanity here!!!
            Texture s = gFrameworkSDL.insanityCache(color);
            assert(s !is null);
            drawTiled(s, p1, p2-p1);
        } else {
            SDL_Rect rect;
            p1 += mTrans;
            p2 += mTrans;
            rect.x = p1.x;
            rect.y = p1.y;
            rect.w = p2.x-p1.x;
            rect.h = p2.y-p1.y;
            version(DrawStats) gFrameworkSDL.mDrawTime.start();
            int res = SDL_FillRect(sdlsurface.mReal, &rect,
                sdlsurface.colorToSDLColor(color));
            version(DrawStats) gFrameworkSDL.mDrawTime.stop();
            assert(res == 0);
        }
    }

    public void clear(Color color) {
        drawFilledRect(Vector2i(0, 0)-mTrans, clientSize-mTrans, color, false);
    }

    public void drawText(char[] text) {
        assert(false);
    }
}

public class FrameworkSDL : Framework {
    private SDL_Surface* mScreen;
    private SDLSurface mScreenSurface;
    private PixelFormat* mScreenAlpha;
    private Keycode mSdlToKeycode[int];

    private Texture[int] mInsanityCache;

    package bool mAllowTextureCache = true;

    private SoundMixer mSoundMixer;

    //hurhurhur
    private PerfTimer mDrawTime, mClearTime, mFlipTime, mInputTime, mWasteTime;
    private PerfTimer[char[]] mTimers;

    //return a surface with unspecified size containing this color
    //(used for drawing alpha blended rectangles)
    private Texture insanityCache(Color c) {
        int key = colorToRGBA32(c);

        Texture* s = key in mInsanityCache;
        if (s)
            return *s;

        SDLSurface tile = createSurface(Vector2i(64, 64), DisplayFormat.Best,
            Transparency.Alpha);
        SDL_FillRect(tile.mReal, null, tile.colorToSDLColor(c));
        auto tex = tile.createTexture();
        mInsanityCache[key] = tex;
        return tex;
    }

    private int releaseInsanityCache() {
        int rel;
        foreach (Texture t; mInsanityCache) {
            t.clearCache();
            t.getSurface().free();
            rel++;
        }
        mInsanityCache = null;
        return rel;
    }

    this(char[] arg0, char[] appId) {
        super(arg0, appId);

        gSurfaces = new typeof(gSurfaces);
        gFonts = new typeof(gFonts);

        if (gFrameworkSDL !is null) {
            throw new Exception("FrameworkSDL is a singleton, sorry.");
        }

        gFrameworkSDL = this;

        DerelictSDL.load();
        DerelictSDLImage.load();
        DerelictSDLttf.load();

        if (SDL_Init(SDL_INIT_VIDEO | SDL_INIT_AUDIO) < 0) {
            throw new Exception(format("Could not init SDL: %s",
                std.string.toString(SDL_GetError())));
        }

        SDL_EnableUNICODE(1);
        SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY,
            SDL_DEFAULT_REPEAT_INTERVAL);

        if (TTF_Init()==-1) {
            throw new Exception(format("TTF_Init: %s\n",
                std.string.toString(TTF_GetError())));
        }

        mScreenSurface = new SDLSurface(null);
        //mScreenSurface.mIsScreen = true;
        //mScreenSurface.mNeverCache = true;

        mSoundMixer = new SoundMixer();

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            mSdlToKeycode[item.sdlcode] = item.code;
        }

        registerCacheReleaser(&releaseInsanityCache);
        registerCacheReleaser(&releaseResCaches);

        setCaption("<no caption>");

        //for some worthless statistics...
        void timer(out PerfTimer tmr, char[] name) {
            tmr = new PerfTimer;
            mTimers[name] = tmr;
        }
        timer(mDrawTime, "fw_draw");
        timer(mClearTime, "fw_clear");
        timer(mFlipTime, "fw_flip");
        timer(mInputTime, "fw_input");
        timer(mWasteTime, "fw_waste");
    }

    override public void deinitialize() {
        //reap everything hahahaha
        //this wouldn't catch everything if it was multithreaded
        foreach (SDLSurface s; gSurfaces.list) {
            s.free();
        }
        foreach (SDLFont f; gFonts.list) {
            f.free();
        }
        //hint: should be no need to run a gc cycle before
        //  is it race condition free???
        defered_free();

        mSoundMixer.deinitialize();

        //deinit and unload all SDL dlls (in reverse order)
        TTF_Quit();
        SDL_Quit();
        DerelictSDLImage.unload();
        DerelictSDLttf.unload();
        DerelictSDL.unload();
    }

    override public char[] getInfoString(InfoString s) {
        switch (s) {
            case InfoString.Framework: {
                char[] version_to_a(SDL_version v) {
                    return format("%s.%s.%s", v.major, v.minor, v.patch);
                }
                SDL_version compiled, linked;
                SDL_VERSION(&compiled);
                linked = *SDL_Linked_Version();
                return format("FrameworkSDL, SDL compiled=%s linked=%s\n",
                    version_to_a(compiled), version_to_a(linked));
            }
            case InfoString.Backend: {
                char[20] buf;
                char* res = SDL_VideoDriverName(buf.ptr, buf.length);
                char[] driver = res ? .toString(res) : "<unintialized>";
                SDL_VideoInfo info = *SDL_GetVideoInfo();

                //in C, info.flags doesn't exist, but instead there's a bitfield
                //here are the names of the bitfield entries (in order)
                char[][] flag_names = ["hw_available", "wm_available",
                    "blit_hw", "blit_hw_CC", "blit_hw_A", "blit_sw",
                    "blit_sw_CC", "blit_sw_A", "blit_fill"];

                char[] flags;
                foreach (int index, name; flag_names) {
                    bool set = !!(info.flags & (1<<index));
                    flags ~= format("  %s: %s\n", name, (set ? "1" : "0"));
                }

                //.alpha and .colorkey fields ignored
                char[] pxfmt = sdlFormatToFramework(info.vfmt).toString();

                //Framework's pixel formats
                char[] pxfmts = "Pixel formats:\n";
                for (int n = DisplayFormat.min; n <= DisplayFormat.max; n++) {
                    pxfmts ~= format("   %s: %s\n", n,
                        findPixelFormat(cast(DisplayFormat)n));
                }

                return format("driver: %s\nflags: \n%svideo_mem = %s\n"
                    "pixel_fmt = %s\ncurrent WxH = %sx%s\n%s", driver, flags,
                    sizeToHuman(info.video_mem), pxfmt, info.current_w,
                    info.current_h, pxfmts);
            }
            case InfoString.ResourceList: return resourceString();
            case InfoString.Custom0: return .toString(weaklist_count());
            default:
                return super.getInfoString(s);
        }
    }

    char[] resourceString() {
        char[] res;

        res ~= "Surfaces:\n";
        int pixelCount, byteCount, cachedBytes;
        int sCount;
        foreach (SDLSurface s; gSurfaces.list) {
            if (!s.valid) //xxx: don't know if or why it should be not valid
                continue;
            sCount++;
            auto pixels = s.size.x*s.size.y;
            pixelCount += pixels;
            byteCount += pixels*s.mReal.format.BytesPerPixel;
            if (s.hasCache())
                cachedBytes += pixels*s.mCached.format.BytesPerPixel;
            res ~= format("   [%s] %sx%s\n", s.hasCache() ? "C" : " ", s.size.x,
                s.size.y);
        }
        res ~= format("%s surfaces, %s pixels => %s, cached: %s\n", sCount,
            pixelCount, sizeToHuman(byteCount), sizeToHuman(cachedBytes));

        res ~= "Fonts:\n";
        int fCount, cachedGlyphs;
        foreach (SDLFont f; gFonts.list) {
            if (!f.valid)
                continue;
            fCount++;
            cachedGlyphs += f.cachedGlyphs();
        }
        res ~= format("%s fonts, %s cached glyphs\n", fCount, cachedGlyphs);

        return res;
    }

    override public PerfTimer[char[]] timers() {
        return mTimers;
    }

    package bool useGL() {
        return false;
    }

    public void setCaption(char[] caption) {
        caption = caption ~ '\0';
        //second arg is the "icon name", the docs don't tell its meaning
        SDL_WM_SetCaption(caption.ptr, null);
    }

    public uint bitDepth() {
        return mScreenSurface.mReal.format.BitsPerPixel;
    }

    public void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen)
    {
        SDL_Surface* newscreen;

        newscreen = SDL_SetVideoMode(widthX, widthY, bpp,
            SDL_HWSURFACE | SDL_DOUBLEBUF | (fullscreen ? SDL_FULLSCREEN : 0));

        if(newscreen is null) {
            throw new Exception(format("Unable to set %dx%dx%d video mode: %s",
                widthX, widthY, bpp, std.string.toString(SDL_GetError())));
        }

        mScreen = newscreen;
        mScreenSurface.mReal = mScreen;

        //find out what SDL thinks is best for using alpha blending on screen
        //(is there a better way than this hack??)
        mScreenAlpha = new PixelFormat;
        auto temp = createSurface(Vector2i(1,1), DisplayFormat.Screen,
            Transparency.None);
        auto temp2 = SDL_DisplayFormatAlpha(temp.mReal);
        *mScreenAlpha = sdlFormatToFramework(temp2.format);
        SDL_FreeSurface(temp2);
        temp.free();

        //i.e. reload textures, get rid of stuff in too low resolution...
        releaseCaches();

        if (onVideoInit)
            onVideoInit(false);
    }

    package PixelFormat sdlFormatToFramework(SDL_PixelFormat* fmt) {
        PixelFormat ret;

        ret.depth = fmt.BitsPerPixel;
        ret.bytes = fmt.BytesPerPixel; //xxx: really? reliable?
        ret.mask_r = fmt.Rmask;
        ret.mask_g = fmt.Gmask;
        ret.mask_b = fmt.Bmask;
        ret.mask_a = fmt.Amask;

        return ret;
    }

    public PixelFormat findPixelFormat(DisplayFormat fmt) {
        if (fmt == DisplayFormat.ScreenAlpha) {
            if (mScreenAlpha)
                return *mScreenAlpha;
            //fallback
            fmt = DisplayFormat.RGBA32;
        }
        if (fmt == DisplayFormat.Screen) {
            return sdlFormatToFramework(mScreen.format);
        } else {
            return super.findPixelFormat(fmt);
        }
    }

    public bool getModifierState(Modifier mod) {
        //special handling for the shift- and numlock-modifiers
        //since the user might toggle numlock or capslock while we don't have
        //the keyboard-focus, ask the SDL (which inturn asks the OS)
        SDLMod modstate = SDL_GetModState();
        //writefln("state=%s", modstate);
        if (mod == Modifier.Shift) {
            //xxx behaviour when caps and shift are both on is maybe OS
            //dependend; on X11, both states are usually XORed
            return ((modstate & KMOD_CAPS) != 0) ^ super.getModifierState(mod);
        //} else if (mod == Modifier.Numlock) {
        //    return (modstate & KMOD_NUM) != 0;
        } else {
            //generic handling for non-toggle modifiers
            return super.getModifierState(mod);
        }
    }

    private Keycode sdlToKeycode(int sdl_sym) {
        if (sdl_sym in mSdlToKeycode) {
            return mSdlToKeycode[sdl_sym];
        } else {
            return Keycode.INVALID; //sorry
        }
    }

    public SDLSurface loadImage(Stream st, Transparency transp) {
        return new SDLSurface(st, transp);
    }

    /+
    public SDLSurface createImage(Vector2i size, uint pitch, PixelFormat format,
        Transparency transp, void* data)
    {
        return new SDLSurface(size.x, size.y, pitch, format, transp, data);
    }
    +/

    public SDLSurface createSurface(Vector2i size, DisplayFormat fmt,
        Transparency transp)
    {
        return new SDLSurface(size, fmt, transp);
    }

    public Font loadFont(Stream str, FontProperties fontProps) {
        auto ret = new SDLFont(str,fontProps);
        return ret;
    }

    public Surface screen() {
        return mScreenSurface;
    }

    public Sound sound() {
        return mSoundMixer;
    }

    protected void run_fw() {
        // process events
        mInputTime.start();
        input();
        mInputTime.stop();

        // draw to the screen
        render();

        //TODO: Software backbuffer
        mFlipTime.start();
        SDL_Flip(mScreen);
        mFlipTime.stop();

        // defered free (GC related, sucky Phobos forces this to us)
        defered_free();

        // yield the rest of the timeslice
        SDL_Delay(0);
    }

    void defered_free() {
        gFonts.cleanup((FontData d) { d.doFree(); });
        gSurfaces.cleanup((SurfaceData d) { d.doFree(); });
    }

    int weaklist_count() {
        return gFonts.countRefs() + gSurfaces.countRefs();
    }

    int releaseResCaches() {
        int res;

        foreach (f; gFonts.list) {
            res += f.releaseCache();
        }

        foreach (s; gSurfaces.list) {
            //oh noes, this is awfully stupid!
            if (s.hasCache()) {
                s.createTexture().clearCache();
                res++;
            }
        }

        return res;
    }

    override void setAllowCaching(bool set) {
        mAllowTextureCache = set;
        foreach (s; gSurfaces.list) {
            if (auto t = s.mSDLTexture) {
                t.checkCaching();
            }
        }
    }

    public void cursorVisible(bool v) {
        if (v)
            SDL_ShowCursor(SDL_ENABLE);
        else
            SDL_ShowCursor(SDL_DISABLE);
    }
    public bool cursorVisible() {
        int v = SDL_ShowCursor(SDL_QUERY);
        if (v == SDL_ENABLE)
            return true;
        else
            return false;
    }

    public void mousePos(Vector2i newPos) {
        SDL_WarpMouse(newPos.x, newPos.y);
    }

    public bool grabInput() {
        int g = SDL_WM_GrabInput(SDL_GRAB_QUERY);
        return g == SDL_GRAB_ON;
    }

    public void grabInput(bool grab) {
        if (grab)
            SDL_WM_GrabInput(SDL_GRAB_ON);
        else
            SDL_WM_GrabInput(SDL_GRAB_OFF);
    }

    private KeyInfo keyInfosFromSDL(in SDL_KeyboardEvent sdl) {
        KeyInfo infos;
        infos.code = sdlToKeycode(sdl.keysym.sym);
        infos.unicode = sdl.keysym.unicode;
        infos.mods = getModifierSet();
        return infos;
    }

    private KeyInfo mouseInfosFromSDL(in SDL_MouseButtonEvent mouse) {
        KeyInfo infos;
        infos.code = sdlToKeycode(g_sdl_mouse_button1 + (mouse.button - 1));
        return infos;
    }

    private void input() {
        SDL_Event event;
        while(SDL_PollEvent(&event)) {
            switch(event.type) {
                case SDL_KEYDOWN:
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    doKeyDown(infos);
                    break;
                case SDL_KEYUP:
                    //xxx TODO: SDL provides no unicode translation for KEYUP
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    doKeyUp(infos);
                    break;
                case SDL_MOUSEMOTION:
                    //update mouse pos after button state
                    doUpdateMousePos(Vector2i(event.motion.x, event.motion.y));
                    break;
                case SDL_MOUSEBUTTONUP:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
                    doKeyUp(infos);
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
                    doKeyDown(infos);
                    break;
                // exit if SDLK or the window close button are pressed
                case SDL_QUIT:
                    doTerminate();
                    break;
                default:
            }
        }
    }

    private void render() {
        mClearTime.start();
        SDL_FillRect(mScreen, null, mScreenSurface.colorToSDLColor(clearColor));
        mClearTime.stop();
        Canvas c = screen.startDraw();
        if (onFrame) {
                onFrame(c);
        }
        c.endDraw();
        //SDL_UpdateRect(mScreen,0,0,0,0);
    }

    public Time getCurrentTime() {
        int ticks = SDL_GetTicks();
        return timeMsecs(ticks);
    }

    public void sleepTime(Time relative) {
        SDL_Delay(relative.msecs);
    }
}
