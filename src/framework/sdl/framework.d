module framework.sdl.framework;

import framework.framework;
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
    SDL_Surface* sdlsurface;
    //non-null if this is an image
    SDL_Surface* mImageSource;
    Canvas mCanvas;

    public Canvas startDraw() {
        if (mCanvas is null) {
            mCanvas = new SDLCanvas(this);
        }
        return mCanvas;
    }
    public void endDraw() {
        //nop under SDL
    }

    public Vector2i size() {
        return Vector2i(sdlsurface.w,sdlsurface.h);
    }

    public bool convertToData(PixelFormat format, out uint pitch,
        out void* data)
    {
        assert(sdlsurface !is null);

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

        SDL_Surface* s = SDL_ConvertSurface(sdlsurface, &fmt, SDL_SWSURFACE);
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

        return true;
    }

    public void colorkey(Color colorkey) {
        uint key = colorToSDLColor(colorkey);
        SDL_SetColorKey(sdlsurface, SDL_SRCCOLORKEY, key);
    }

    this(SDL_Surface* surface) {
        this.sdlsurface = surface;
    }
    this() {
    }
    //create a new surface using current depth
    //xxx: find better solution for enabling alpha...
    this(Vector2i size, bool alpha = false) {
        uint flags = SDL_HWSURFACE;
        if (alpha) {
            flags |= SDL_SRCALPHA;
        }
        SDL_PixelFormat* format = gFrameworkSDL.mScreen.format;
        sdlsurface = SDL_CreateRGBSurface(flags, size.x, size.y,
            format.BitsPerPixel, format.Rmask, format.Gmask, format.Bmask,
            format.Amask);
        if (sdlsurface is null) {
            throw new Exception("couldn't create surface");
        }
    }

    void setSDLSurface(SDL_Surface* surface) {
        sdlsurface = surface;
    }

    void load(Stream st) {
        SDL_RWops* ops = rwopsFromStream(st);
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        if (surf !is null) {
            mImageSource = surf;
            surf.flags |= SDL_SRCALPHA;
            doConvert();
        } else {
            throw new Exception("image couldn't be loaded");
        }
    }

    //called when depth is changed
    void doConvert() {
        SDL_Surface* conv_from = sdlsurface;
        SDL_Surface* old = sdlsurface;
        if (mImageSource !is null) {
            conv_from = mImageSource;
        }
        //xxx or SDL_DisplayFormat???
        sdlsurface = SDL_DisplayFormatAlpha(conv_from);
        SDL_FreeSurface(old);
    }

    uint colorToSDLColor(Color color) {
        return SDL_MapRGBA(sdlsurface.format,cast(ubyte)(255*color.r),
            cast(ubyte)(255*color.g),cast(ubyte)(255*color.b),
            cast(ubyte)(255*color.a));
    }

    //to avoid memory leaks
    //xxx: either must be automatically managed (finalizer) or be in superclass
    void free() {
        SDL_FreeSurface(sdlsurface);
        sdlsurface = null;
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
        SDL_Rect rc, destrc;
        rc.x = cast(short)sourcePos.x;
        rc.y = cast(short)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        destrc.x = cast(short)destPos.x;
        destrc.y = cast(short)destPos.y; //destrc.w/h ignored by SDL_BlitSurface
        SDL_BlitSurface(sdls.sdlsurface, &rc, sdlsurface.sdlsurface, &destrc);
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
        SDL_FillRect(sdlsurface.sdlsurface, &rect,
            sdlsurface.colorToSDLColor(color));
    }

    public void drawText(char[] text) {

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
                    //the following doesntwork, no alpha channel (not always)
                    //mBackPlain = new SDLSurface(Vector2i(mWidest, size.y));
                    mBackPlain = new SDLSurface(SDL_DisplayFormatAlpha(
                        frags[c].sdlsurface));
                    Canvas tmp = mBackPlain.startDraw();
                    tmp.drawFilledRect(Vector2i(0, 0), mBackPlain.size,
                        props.back);
                    tmp.endDraw();
                    avoid_alpha(mBackPlain.sdlsurface, props.back.a);
                }
                canvas.draw(mBackPlain, pos, Vector2i(0, 0), size);
            }

            canvas.draw(surface, pos);
            pos.x += surface.size.x;
        }
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
            avoid_alpha(surface, props.fore.a);
        }
        if (surface == null) {
            throw new Exception(format("could not render char %s", c));
        }
        return new SDLSurface(surface);
    }

    //avoid alpha if unnecessary, sometimes it's slow
    private void avoid_alpha(SDL_Surface* surface, float alpha) {
        //DMD 0.163: "Internal error: ../ztc/cg87.c 1327" when no indirection
        //through e
        float e = Color.epsilon;
        if (math.fabs(alpha - 1.0f) < e) {
        //    SDL_SetAlpha(surface, 0, 0);
        }
    }
}

public class FrameworkSDL : Framework {
    private SDL_Surface* mScreen;
    private SDLSurface mScreenSurface;
    private Keycode mSdlToKeycode[int];

    this() {
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
        mScreenSurface.setSDLSurface(mScreen);
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
	} else if (mod == Modifier.Numlock) {
	    return (modstate & KMOD_NUM) != 0;
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

    public Surface loadImage(Stream st) {
        SDLSurface res = new SDLSurface();
        res.load(st);
        return res;
    }

    public Surface createImage(uint width, uint height, uint pitch,
        PixelFormat format, void* data)
    {
        SDLSurface f = new SDLSurface();
        if (!data) {
            void[] alloc;
            alloc.length = pitch*height*format.bytes;
            data = alloc.ptr;
        }
        //possibly incorrect
        f.sdlsurface = SDL_CreateRGBSurfaceFrom(data, width, height,
            format.depth, pitch, format.mask_r, format.mask_g, format.mask_b,
            format.mask_a);
        if (f.sdlsurface is null)
            throw new Exception("couldn't create surface");
        return f;
    }

    public Surface createSurface(uint width, uint height) {
        SDLSurface f = new SDLSurface();
        f.sdlsurface = SDL_CreateRGBSurface(0, width, height,
            mScreen.format.BitsPerPixel, mScreen.format.Rmask,
            mScreen.format.Gmask, mScreen.format.Bmask, mScreen.format.Amask);
        if (f.sdlsurface is null)
            throw new Exception("couldn't create surface");
        return f;
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
