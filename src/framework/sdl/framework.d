module framework.sdl.framework;

import framework.framework;
import framework.font;
import framework.event;
import std.stream;
import std.stdio;
import std.string;
import utils.vector2;
import framework.sdl.rwops;
import derelict.sdl.sdl;
import derelict.sdl.image;
import derelict.sdl.ttf;
import framework.sdl.keys;
import math = std.math;
import utils.time;
import utils.drawing;

private static FrameworkSDL gFrameworkSDL;

debug import std.stdio;

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
    private SDL_Surface* mCached;

    package this(SDLSurface source, bool enableCache = true) {
        mOriginalSurface = source;
        assert(source !is null);
        if (!enableCache) {
            mCached = mOriginalSurface.mReal;
        }
    }

    public void setCaching(bool state) {
        releaseCache();
        if (state) {
            mCached = null;
        } else {
            mCached = mOriginalSurface.mReal;
        }
    }

    public Vector2i size() {
        return mOriginalSurface.size;
    }

    //return surface that's actually drawn
    package SDL_Surface* getDrawSurface() {
        if (!mCached)
            checkIfScreenFormat();
        return mCached;
        //return mOriginalSurface.mReal;
    }

    public Surface getSurface() {
        return mOriginalSurface;
    }

    //convert the image to the current screen format (this is done once)
    package void checkIfScreenFormat() {
        //xxx insert check if screen depth has changed at all!
        //xxx also check if you need to convert it at all
        //else: performance problem with main level surface
        if (!mCached) {
            assert(mOriginalSurface !is null);
            SDL_Surface* conv_from = mOriginalSurface.mReal;
            assert(conv_from !is null);

            releaseCache();
            switch (mOriginalSurface.mTransp) {
                case Transparency.Colorkey, Transparency.None: {
                    mCached = SDL_DisplayFormat(conv_from);
                    break;
                }
                case Transparency.Alpha: {
                    //xxx: this didn't really work, the alpha channel was
                    //  removed, needs to be retested (i.e. don't set neverCache
                    //  when using spiffy alpha blended fonts)
                    mCached = SDL_DisplayFormatAlpha(conv_from);
                    break;
                }
                default:
                    assert(false);
            }
        }
    }

    void releaseCache() {
        if (mCached) {
            if (mCached !is mOriginalSurface.mReal)
                SDL_FreeSurface(mCached);
            mCached = null;
        }
    }

    void clearCache() {
        releaseCache();
    }
}

public class SDLSurface : Surface {
    //mReal: original surface (any pixelformat)
    SDL_Surface* mReal;
    //if non-null, this contains the surface data (to prevent GCing it)
    void* mData;
    SDLCanvas mCanvas;
    Transparency mTransp;
    Color mColorkey;

    SDLTexture mSDLTexture;

    public Surface clone() {
        assert(mReal !is null);
        auto n = SDL_ConvertSurface(mReal, mReal.format, mReal.flags);
        auto res = new SDLSurface(n);
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
    //public void endDraw() {
    //}

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

    public bool convertToData(PixelFormat format, out uint pitch,
        out void* data)
    {
        assert(mReal !is null);

        //xxx: as an optimization, avoid double-copying (that is, calling the
        //  SDL_ConvertSurface() function, if the format is already equal to
        //  the requested one)
        SDL_PixelFormat fmt;
        toSDLPixelFmt(format, fmt);

        SDL_Surface* s = SDL_ConvertSurface(mReal, &fmt, SDL_SWSURFACE);
        //xxx: error checking: SDL even creates surfaces, if the pixelformat
        //  doesn't make any sense (at least it looks like)
        if (s is null)
            return false;

        pitch = s.pitch;

        void[] alloc;
        alloc.length = pitch*size.y;
        SDL_LockSurface(s);
        alloc[] = s.pixels[0 .. alloc.length]; //copy
        data = alloc.ptr;
        SDL_UnlockSurface(s);

        SDL_FreeSurface(s);

        assert(data);

        return true;
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
    this(SDL_Surface* surface) {
        this.mReal = surface;
    }
    //create a new surface using current depth
    //xxx: find better solution for enabling alpha...
    this(Vector2i size, DisplayFormat fmt, Transparency transp) {
        PixelFormat format = gFrameworkSDL.findPixelFormat(fmt);
        mReal = SDL_CreateRGBSurface(SDL_HWSURFACE, size.x, size.y,
            format.depth, format.mask_r, format.mask_g, format.mask_b,
            format.mask_a);
        if (!mReal) {
            writefln("%d %d %d", size.x, size.y, format.depth);
            throw new Exception("couldn't create surface (1)");
        }
        initTransp(transp);
    }
    //create from stream (using SDL_Image)
    this(Stream st, Transparency transp) {
        SDL_RWops* ops = rwopsFromStream(st);
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        if (surf) {
            mReal = surf;
        } else {
            char* err = IMG_GetError();
            throw new Exception("image couldn't be loaded: "~std.string.toString(err));
        }
        initTransp(transp);
    }
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
        mReal = SDL_CreateRGBSurfaceFrom(data, w, h, format.depth, pitch,
            format.mask_r, format.mask_g, format.mask_b, format.mask_a);
        if (!mReal)
            throw new Exception("couldn't create surface (2)");
        initTransp(transp);
    }

    private void initTransp(Transparency transp) {
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

    //to avoid memory leaks
    //xxx: either must be automatically managed (finalizer) or be in superclass
    void free() {
        //xxx: what about the textures hooked to us?
        SDL_FreeSurface(mReal);
        mReal = null;
        mData = null;
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
    const int MAX_STACK = 10;

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
        SDL_GetClipRect(sdlsurface.mReal, &mStack[mStackTop].clip);
        mStack[mStackTop].translate = mTrans;
        mStack[mStackTop].clientstart = mClientStart;
        mStack[mStackTop].clientsize = mClientSize;
        mStackTop++;
    }

    public void popState() {
        assert(mStackTop > 0);
        mStackTop--;
        SDL_Rect* rc = &mStack[mStackTop].clip;
        SDL_SetClipRect(sdlsurface.mReal, rc);
        mTrans = mStack[mStackTop].translate;
        mClientStart = mStack[mStackTop].clientstart;
        mClientSize = mStack[mStackTop].clientsize;
    }

    public void setWindow(Vector2i p1, Vector2i p2) {
        clip(p1, p2);
        mTrans = p1 + mTrans;
        mClientStart = p1 + mTrans;
        mClientSize = p2 - p1;
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

    public Vector2i clientOffset() {
        return mClientStart - mTrans;
    }

    public Vector2i realSize() {
        return sdlsurface.size();
    }
    public Vector2i clientSize() {
        return mClientSize;
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
        int res = SDL_BlitSurface(src, &rc, sdlsurface.mReal, &destrc);
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
            int res = SDL_FillRect(sdlsurface.mReal, &rect,
                sdlsurface.colorToSDLColor(color));
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

public class SDLFont : Font {
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
        font_stream.seek(0,SeekPos.Set);
        this.props = props;
        SDL_RWops* rwops;
        rwops = rwopsFromStream(font_stream);
        font = TTF_OpenFontRW(rwops, 1, props.size);
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

    ~this() {
        TTF_CloseFont(font);
    }

    public FontProperties properties() {
        return props;
    }

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

    public Vector2i textSize(char[] text) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            Texture surface = getGlyph(c);
            res.x += surface.size.x;
        }
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

public class FrameworkSDL : Framework {
    private SDL_Surface* mScreen;
    private SDLSurface mScreenSurface;
    private Keycode mSdlToKeycode[int];

    private Texture[int] mInsanityCache;

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

    this(char[] arg0, char[] appId) {
        super(arg0, appId);

        if (gFrameworkSDL !is null) {
            throw new Exception("FrameworkSDL is a singleton, sorry.");
        }

        gFrameworkSDL = this;


        DerelictSDL.load();
        DerelictSDLImage.load();
        DerelictSDLttf.load();

        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
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

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            mSdlToKeycode[item.sdlcode] = item.code;
        }

        setCaption("<no caption>");
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
        if (fmt == DisplayFormat.Screen || fmt == DisplayFormat.ReallyScreen) {
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

    public SDLSurface createImage(Vector2i size, uint pitch, PixelFormat format,
        Transparency transp, void* data)
    {
        return new SDLSurface(size.x, size.y, pitch, format, transp, data);
    }

    public SDLSurface createSurface(Vector2i size, DisplayFormat fmt,
        Transparency transp)
    {
        return new SDLSurface(size, fmt, transp);
    }

    public Font loadFont(Stream str, FontProperties fontProps) {
        return new SDLFont(str,fontProps);
    }

    public Surface screen() {
        return mScreenSurface;
    }

    protected void run_fw() {
        // process events
        input();

        // draw to the screen
        render();

        //TODO: Software backbuffer
        SDL_Flip(mScreen);

        // yield the rest of the timeslice
        SDL_Delay(0);
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
                    doKeyUp(infos);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    doKeyDown(infos);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
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
        SDL_FillRect(mScreen,null,SDL_MapRGB(mScreen.format,0,0,0));
        Canvas c = screen.startDraw();
        if (onFrame) {
                onFrame(c);
        }
        c.endDraw();
        SDL_UpdateRect(mScreen,0,0,0,0);
    }

    public Time getCurrentTime() {
        int ticks = SDL_GetTicks();
        return timeMsecs(ticks);
    }

    public void sleepTime(Time relative) {
        SDL_Delay(relative.msecs);
    }
}
