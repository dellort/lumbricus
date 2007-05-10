module framework.sdl.framework;

import framework.framework;
import framework.font;
import framework.keysyms;
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

private static FrameworkSDL gFrameworkSDL;

//SDL_Color.unused contains the alpha value
static SDL_Color ColorToSDLColor(Color color) {
    SDL_Color col;
    col.r = cast(ubyte)(255*color.r);
    col.g = cast(ubyte)(255*color.g);
    col.b = cast(ubyte)(255*color.b);
    col.unused = cast(ubyte)(255*color.a);
    return col;
}

public class SDLSurface : Surface {
    //mReal: original surface (any pixelformat)
    //mCached: surface as painted to the screen (should be screen pixelformat)
    //  mCached maybe null, mReal should always be non-null
    SDL_Surface* mReal, mCached;
    Canvas mCanvas;
    Transparency mTransp;
    bool mIsScreen;
    bool mOnScreenSurface;
    bool mNeverCache;
    Color mColorkey;

    public Surface getSubSurface(Vector2i pos, Vector2i size) {
        SDLSurface n = new SDLSurface(null);
        n.mTransp = mTransp;
        n.mOnScreenSurface = mOnScreenSurface;
        n.mNeverCache = mNeverCache;
        n.mColorkey = mColorkey;
        //xxx: shouldn't copy, but the rest of the code is too borken
        //actually, it should only select a subregion without copying...
        n.mReal = SDL_CreateRGBSurface(mReal.flags, mReal.w,
            mReal.h, mReal.format.BitsPerPixel,
            mReal.format.Rmask, mReal.format.Gmask, mReal.format.Bmask,
            mReal.format.Amask);
        assert(n.mReal);
        Canvas c = n.startDraw();
        c.draw(this, Vector2i(0, 0), pos, size);
        c.endDraw();
        return n;
    }

    public bool isScreen() {
        return mIsScreen;
    }

    public bool isOnScreen() {
        return mOnScreenSurface;
    }

    /// don't convert the surface to screen format (which is usually done if it
    /// is painted to the screen to hopefully speed up drawing)
    public void setNeverCache() {
        mNeverCache = true;
    }

    public void isOnScreen(bool onScreen) {
        if (onScreen) {
            //xxx: ? shouldn't this be done on-demand
            checkIfScreenFormat();
        } else {
            releaseCached();
            mOnScreenSurface = false;
        }
    }

    //release the cached surface, which has the screen pixelformat
    public void releaseCached() {
        if (mCached)
            SDL_FreeSurface(mCached);
        mCached = null;
    }

    //convert the image to the current screen format (this is done once)
    package void checkIfScreenFormat() {
        if (mNeverCache)
            return;

        //xxx insert check if screen depth has changed at all!
        //else: performance problem with main level surface
        if (!mCached) {
            SDL_Surface* conv_from = mReal;
            releaseCached(); //needed, if !mCached isn't the only cond. above...
            switch (mTransp) {
                case Transparency.Colorkey, Transparency.None: {
                    mCached = SDL_DisplayFormat(mReal);
                    break;
                }
                case Transparency.Alpha: {
                    //xxx: this didn't really work, the alpha channel was
                    //  removed, needs to be retested (i.e. don't set neverCache
                    //  when using spiffy alpha blended fonts)
                    mCached = SDL_DisplayFormatAlpha(mReal);
                    break;
                }
                default:
                    assert(false);
            }
            //xxx maybe it's unwanted because of slightly unfitting semantics
            mOnScreenSurface = true;
        }
    }

    public Canvas startDraw() {
        //surface will be changed, so invalidate the cached bitmap
        releaseCached();

        if (mCanvas is null) {
            mCanvas = new SDLCanvas(this);
        }
        return mCanvas;
    }
    public void endDraw() {
        //nop under SDL
    }

    public Vector2i size() {
        return Vector2i(mReal.w, mReal.h);
    }

    public bool convertToData(PixelFormat format, out uint pitch,
        out void* data)
    {
        assert(mReal);

        //xxx: as an optimization, avoid double-copying (that is, calling the
        //  SDL_ConvertSurface() function, if the format is already equal to
        //  the requested one)
        SDL_PixelFormat fmt;
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

    public void enableColorkey(Color colorkey = cStdColorkey) {
        assert(mReal);
        releaseCached();

        uint key = colorToSDLColor(colorkey);
        mColorkey = colorkey;
        SDL_SetColorKey(mReal, SDL_SRCCOLORKEY, key);
        mTransp = Transparency.Colorkey;
    }

    public void enableAlpha() {
        assert(mReal);
        releaseCached();

        SDL_SetAlpha(mReal, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
        mTransp = Transparency.Alpha;
    }

    public Color colorkey() {
        return mColorkey;
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
            throw new Exception("image couldn't be loaded");
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
        releaseCached();
        SDL_FreeSurface(mReal);
        mReal = null;
    }
}

public class SDLCanvas : Canvas {
    SDLSurface sdlsurface;

    public Vector2i size() {
        return sdlsurface.size();
    }

    public void endDraw() {
        //nop
        sdlsurface.endDraw();
    }

    this(SDLSurface surf) {
        sdlsurface = surf;
    }

    public Surface surface() {
        return sdlsurface;
    }

    public void draw(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        SDLSurface sdls = cast(SDLSurface)source;
        if (sdlsurface.mIsScreen) {
            sdls.checkIfScreenFormat();
        }
        SDL_Rect rc, destrc;
        rc.x = cast(short)sourcePos.x;
        rc.y = cast(short)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        destrc.x = cast(short)destPos.x;
        destrc.y = cast(short)destPos.y; //destrc.w/h ignored by SDL_BlitSurface
        SDL_Surface* src = sdls.mCached;
        if (!src)
            src = sdls.mReal;
        SDL_BlitSurface(src, &rc, sdlsurface.mReal, &destrc);
    }

    //TODO: add code
    public void drawCircle(Vector2i center, int radius, Color color) {
    }

    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
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
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
        SDL_Rect rect;
        rect.x = p1.x;
        rect.y = p1.y;
        rect.w = p2.x-p1.x;
        rect.h = p2.y-p1.y;
        SDL_FillRect(sdlsurface.mReal, &rect,
            sdlsurface.colorToSDLColor(color));
    }

    public void clear(Color color) {
        drawFilledRect(Vector2i(0, 0), sdlsurface.size, color);
    }

    public void drawText(char[] text) {
        assert(false);
    }
}

public class SDLFont : Font {
    private SDLSurface frags[dchar];
    private bool mNeedBackPlain;   //false if background is completely transp.
    private SDLSurface mBackPlain; //used for fuzzy alpha text background
    private uint mWidest;
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
        //just a guess, should be larger than any width of a char in the font
        //(show me a font for which this isn't true, but still I catch that
        // special case)
        mWidest = TTF_FontHeight(font)*2;

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
            SDLSurface surface = getGlyph(c);
            if (mNeedBackPlain) {
                canvas.draw(mBackPlain, pos, Vector2i(0, 0), surface.size);
            }
            canvas.draw(surface, pos);
            pos.x += surface.size.x;
        }
    }
    //xxx code duplication... created already one bug sigh
    public void drawText(Canvas canvas, Vector2i pos, dchar[] text) {
        foreach (dchar c; text) {
            SDLSurface surface = getGlyph(c);
            if (mNeedBackPlain) {
                canvas.draw(mBackPlain, pos, Vector2i(0, 0), surface.size);
            }
            canvas.draw(surface, pos);
            pos.x += surface.size.x;
        }
    }

    public Vector2i textSize(char[] text) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            SDLSurface surface = getGlyph(c);
            res.x += surface.size.x;
        }
        //xxx
        res.y = renderChar(' ').size.y;
        return res;
    }
    //xxx code duplication
    public Vector2i textSize(dchar[] text) {
        Vector2i res = Vector2i(0, 0);
        foreach (dchar c; text) {
            SDLSurface surface = getGlyph(c);
            res.x += surface.size.x;
        }
        //xxx
        res.y = renderChar(' ').size.y;
        return res;
    }

    private SDLSurface getGlyph(dchar c) {
        SDLSurface* sptr = c in frags;
        if (!sptr) {
            frags[c] = renderChar(c);
            sptr = c in frags;
        }
        SDLSurface surface = *sptr;
        Vector2i size = surface.size;

        if (mNeedBackPlain) {
            //recreate "backplain" if necessary
            if (mBackPlain is null
                //|| frags[c].size.x > mWidest
                || frags[c].size.x > mBackPlain.size.x)
            {
                mWidest = frags[c].size.x;
                if (mBackPlain !is null) {
                    mBackPlain.free();
                    mBackPlain = null;
                }
                //xxx: disable the "screen format cache" of SDLSurface,
                //  and instead clear the glyph cache on bit depth change
                //but for now, don't use the screen format anyway, because
                //  then these spiffy alpha fonts won't work in 16bit depth!
                mBackPlain = new SDLSurface(Vector2i(mWidest, size.y),
                    DisplayFormat.Best, Transparency.Alpha);
                mBackPlain.setNeverCache();
                Canvas tmp = mBackPlain.startDraw();
                tmp.drawFilledRect(Vector2i(0, 0), mBackPlain.size,
                    props.back);
                tmp.endDraw();
            }
        }

        return surface;
    }

    private SDLSurface renderChar(dchar c) {
        dchar s[2];
        s[0] = c;
        s[1] = '\0';
        SDL_Color col = ColorToSDLColor(props.fore);
        ubyte col_a = col.unused;
        SDL_Surface* surface = TTF_RenderUNICODE_Blended(font,
            cast(ushort*)s.ptr, col);
        if (surface != null) {
            SDL_LockSurface(surface);
            //scale the alpha values of the pixels in the surface to be in the
            //range 0.0 .. props.fore.a
            //xxx code relies on exact surface format produced by SDL_TTF
            for (int y = 0; y < surface.h; y++) {
                ubyte* ptr = cast(ubyte*)surface.pixels;
                ptr += y*surface.pitch;
                for (int x = 0; x < surface.w; x++) {
                    uint alpha = ptr[3];
                    alpha = (alpha*col_a)/255;
                    ptr[3] = cast(ubyte)(alpha);
                    ptr += 4;
                }
            }
            SDL_UnlockSurface(surface);
        }
        if (surface == null) {
            throw new Exception(format("could not render char %s", c));
        }
        auto tmp = new SDLSurface(surface);
        tmp.enableAlpha();
        return tmp;
    }
}

public class FrameworkSDL : Framework {
    private SDL_Surface* mScreen;
    private SDLSurface mScreenSurface;
    private Keycode mSdlToKeycode[int];

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
        mScreenSurface.mIsScreen = true;
        mScreenSurface.mNeverCache = true;

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            mSdlToKeycode[item.sdlcode] = item.code;
        }

        setCaption("<no caption>");
    }

    public void setCaption(char[] caption) {
        caption = caption ~ '\0';
        //second arg is the "icon name", the docs don't tell its meaning
        SDL_WM_SetCaption(caption.ptr, null);
    }

    public void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen)
    {
        SDL_Surface* newscreen;

        newscreen = SDL_SetVideoMode(widthX, widthY, bpp,
            SDL_HWSURFACE | SDL_DOUBLEBUF);

        if(newscreen is null) {
            throw new Exception(format("Unable to set %dx%dx%d video mode: %s",
                widthX, widthY, bpp, std.string.toString(SDL_GetError())));
        }

        mScreen = newscreen;
        //TODO: Software backbuffer
        mScreenSurface.mReal = mScreen;
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

    public Surface loadImage(Stream st, Transparency transp) {
        return new SDLSurface(st, transp);
    }

    public Surface createImage(Vector2i size, uint pitch, PixelFormat format,
        Transparency transp, void* data)
    {
        return new SDLSurface(size.x, size.y, pitch, format, transp, data);
    }

    public Surface createSurface(Vector2i size, DisplayFormat fmt,
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

    private KeyInfo keyInfosFromSDL(in SDL_KeyboardEvent sdl) {
        KeyInfo infos;
        infos.code = sdlToKeycode(sdl.keysym.sym);
        infos.unicode = sdl.keysym.unicode;
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
                // exit if SDLK or the window close button are pressed
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
                case SDL_QUIT:
                    doTerminate();
                    break;
                default:
            }
        }
    }

    private void render() {
        SDL_FillRect(mScreen,null,SDL_MapRGB(mScreen.format,0,0,0));
        if (onFrame) {
                onFrame();
        }
    }

    public Time getCurrentTime() {
        int ticks = SDL_GetTicks();
        return timeMsecs(ticks);
    }
}
