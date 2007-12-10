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
import framework.sdl.fwgl;
import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import derelict.sdl.image;
import derelict.sdl.ttf;
import framework.sdl.keys;
import math = std.math;
import utils.time;
import utils.perf;
import utils.drawing;
import utils.misc;

version = MarkAlpha;

package uint simpleColorToSDLColor(SDL_Surface* s, Color color) {
    return SDL_MapRGBA(s.format,cast(ubyte)(255*color.r),
        cast(ubyte)(255*color.g),cast(ubyte)(255*color.b),
        cast(ubyte)(255*color.a));
}

package SDL_Color ColorToSDLColor(Color color) {
    SDL_Color col;
    col.r = cast(ubyte)(255*color.r);
    col.g = cast(ubyte)(255*color.g);
    col.b = cast(ubyte)(255*color.b);
    col.unused = cast(ubyte)(255*color.a);
    return col;
}

package bool sdlIsAlpha(SDL_Surface* s) {
    return s.format.Amask != 0 && (s.flags & SDL_SRCALPHA);
}

class SDLSurface : DriverSurface {
    SDL_Surface* mSurface;
    SurfaceData* mData;
    bool mCacheEnabled;

    //create from Framework's data
    this(SurfaceData* data) {
        mData = data;
        reinit();
    }

    //release data from driver surface
    void kill() {
        releaseSurface();
    }

    void releaseSurface() {
        if (mSurface) {
            SDL_FreeSurface(mSurface);
            mSurface = null;
        }
    }

    void reinit() {
        releaseSurface();

        bool cc = mData.transparency == Transparency.Colorkey;

        //NOTE: SDL_CreateRGBSurfaceFrom doesn't copy the data... so, be sure
        //      to keep the pointer, so D won't GC it
        //fixed RGA32 format :/
        mSurface = SDL_CreateRGBSurfaceFrom(mData.data.ptr, mData.size.x,
            mData.size.y, 32, mData.pitch, 0x000000FF, 0x0000FF00, 0x00FF0000,
            /+cc ? 0 :+/ 0xFF000000);
        if (!mSurface) {
            throw new Exception(format("couldn't create SDL surface, size=%s",
                mData.size));
        }

        //lol SDL - need to clear any transparency modes first
        //but I don't understand why (maybe because there's an alpha channel)
        SDL_SetAlpha(mSurface, 0, 0);
        //SDL_SetColorKey(mSurface, 0, 0);

        switch (mData.transparency) {
            case Transparency.Alpha: {
                SDL_SetAlpha(mSurface, SDL_SRCALPHA, SDL_ALPHA_OPAQUE);
                break;
            }
            case Transparency.Colorkey: {
                uint key = simpleColorToSDLColor(mSurface, mData.colorkey);
                SDL_SetColorKey(mSurface, SDL_SRCCOLORKEY, key);
                break;
            }
            default: //rien
        }

        mCacheEnabled = convertToDisplay();
    }

    void getPixelData() {
        //nop
        //this SDLSurface never kills the SurfaceData.data pointer
        //but still:
        assert(!SDL_MUSTLOCK(mSurface));
    }

    void updatePixels(in Rect2i rc) {
        //almost nop for SDL...
        if (mCacheEnabled) {
            reinit();
        }
    }

    private bool convertToDisplay() {
        assert(!!mSurface);

        if (!(mData.enable_cache && gSDLDriver.mEnableCaching)) {
            return false;
        }

        SDL_Surface* nsurf;
        switch (mData.transparency) {
            case Transparency.Colorkey, Transparency.None: {
                if (!gSDLDriver.isDisplayFormat(mSurface, false)) {
                    nsurf = SDL_DisplayFormat(mSurface);
                }
                break;
            }
            case Transparency.Alpha: {
                if (!gSDLDriver.isDisplayFormat(mSurface, true)) {
                    nsurf = SDL_DisplayFormatAlpha(mSurface);
                }
                break;
            }
            default:
                assert(false);
        }

        if (!nsurf)
            return false;

        SDL_FreeSurface(mSurface);
        mSurface = nsurf;

        return true;
    }

    //includes special handling for the alpha value: if completely transparent,
    //and if using colorkey transparency, return the colorkey
    final uint colorToSDLColor(Color color) {
        if (mData.transparency == Transparency.Colorkey
            && color.a <= Color.epsilon)
        {
            //color = mData.colorkey;
            return mSurface.format.colorkey;
        }
        return simpleColorToSDLColor(mSurface, color);
    }

    void getInfos(out char[] desc, out uint extra_data) {
        desc = format("c=%s", mCacheEnabled);
        if (mCacheEnabled) {
            extra_data = mSurface.pitch * mSurface.h;
        }
    }
}


package {
    Keycode[int] gSdlToKeycode;
    SDLDriver gSDLDriver;
}


class SDLDriver : FrameworkDriver {
    private {
        Framework mFramework;
        ConfigNode mConfig;
        VideoWindowState mCurVideoState;

        SDLFontDriver mFontDriver;

        //convert stuff to display format if it isn't already
        //+ mark all alpha surfaces drawn on the screen
        bool mEnableCaching, mMarkAlpha;

        //instead of a DriverSurface list (we don't need that yet?)
        uint mDriverSurfaceCount;

        //used only for non-OpenGL rendering
        //valid fields: BitsPerPixel, Rmask, Gmask, Bmask, Amask
        SDL_PixelFormat mRGBA32, mPFScreen, mPFAlphaScreen;

        //if OpenGL enabled (if not, use 2D SDL drawing)
        bool mOpenGL;

        //depending if OpenGL or plain-old-SDL-2D mode
        SDLCanvas mScreenCanvas2D;
        GLCanvas mScreenCanvasGL;

        //cache for being able to draw alpha blended filled rects without OpenGL
        Surface[int] mInsanityCache;

    }
    package {
        SDL_Surface* mSDLScreen;

        bool glWireframeDebug;

        //hurhurhur
        PerfTimer mDrawTime, mClearTime, mFlipTime, mInputTime, mWasteTime;
    }

    this(Framework fw, ConfigNode config) {
        if (gSDLDriver) {
            assert(false, "singleton!");
        }
        gSDLDriver = this;

        mFramework = fw;
        mConfig = config;

        mRGBA32.BitsPerPixel = 32;
        mRGBA32.Rmask = 0x00_00_00_FF;
        mRGBA32.Gmask = 0x00_00_FF_00;
        mRGBA32.Bmask = 0x00_FF_00_00;
        mRGBA32.Amask = 0xFF_00_00_00;

        mEnableCaching = config.getBoolValue("enable_caching", true);
        mMarkAlpha = config.getBoolValue("mark_alpha", false);

        mOpenGL = config.getBoolValue("open_gl", true);
        glWireframeDebug = config.getBoolValue("gl_debug_wireframe", false);

        DerelictSDL.load();
        DerelictSDLImage.load();
        if (mOpenGL) {
            DerelictGL.load();
            DerelictGLU.load();
        }

        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            throw new Exception(format("Could not init SDL: %s",
                str.toString(SDL_GetError())));
        }

        SDL_EnableUNICODE(1);
        SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY,
            SDL_DEFAULT_REPEAT_INTERVAL);

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            gSdlToKeycode[item.sdlcode] = item.code;
        }

        mFontDriver = new SDLFontDriver();

        if (!mOpenGL) {
            mScreenCanvas2D = new SDLCanvas();
        } else {
            mScreenCanvasGL = new GLCanvas();
        }

        //for some worthless statistics...
        void timer(out PerfTimer tmr, char[] name) {
            tmr = new PerfTimer;
            //mTimers[name] = tmr;
        }
        timer(mDrawTime, "fw_draw");
        timer(mClearTime, "fw_clear");
        timer(mFlipTime, "fw_flip");
        timer(mInputTime, "fw_input");
        timer(mWasteTime, "fw_waste");
    }

    void destroy() {
        //the framework should have destroyed all DriverSurfaces
        //check that!
        assert(mDriverSurfaceCount == 0);

        //deinit and unload all SDL dlls (in reverse order)
        mFontDriver.destroy();
        mFontDriver = null;
        SDL_Quit();
        if (mOpenGL) {
            DerelictGL.unload();
            DerelictGLU.unload();
        }
        DerelictSDLImage.unload();
        DerelictSDL.unload();

        gSDLDriver = null;
    }

    FontDriver fontDriver() {
        return mFontDriver;
    }

    DriverSurface createSurface(SurfaceData* data, SurfaceMode mode) {
        mDriverSurfaceCount++;
        switch (mode) {
            case SurfaceMode.NORMAL:
                if (mOpenGL) {
                    return new GLSurface(data);
                }
                //fall through
            case SurfaceMode.OFFSCREEN:
                return new SDLSurface(data);
            default:
                assert(false, "unknown SurfaceMode?");
        }
    }

    void killSurface(inout DriverSurface surface) {
        assert(!!surface);
        mDriverSurfaceCount--;
        surface = null;
    }

    //ignore_a_alpha_bla = ignore alpha, if there's no alpha channel for a
    package static bool cmpPixelFormat(SDL_PixelFormat* a, SDL_PixelFormat* b,
        bool ignore_a_alpha_bla = false)
    {
        return (a.BitsPerPixel == b.BitsPerPixel
            && a.Rmask == b.Rmask
            && a.Gmask == b.Gmask
            && a.Bmask == b.Bmask
            && (ignore_a_alpha_bla && a.Amask == 0
                ? true : a.Amask == b.Amask));
    }

    //NOTE: disregards screen alpha channel if non-existant
    package bool isDisplayFormat(SDL_Surface* s, bool alpha) {
        return cmpPixelFormat(s.format, alpha ? &mPFAlphaScreen : &mPFScreen,
            true);
    }

    private bool switchVideoTo(VideoWindowState state) {
        if (state.bitdepth < 0)
            state.bitdepth = 0;

        Vector2i size = state.fullscreen ? state.fs_size : state.window_size;

        int vidflags = 0;
        if (mOpenGL) {
            SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
            SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

            //OpenGL flags for SDL_SetVideoMode
            vidflags |= SDL_OPENGL;
        }
        else
            //SDL only flags for SDL_SetVideoMode
            vidflags |= SDL_HWSURFACE | SDL_DOUBLEBUF;
        if (state.fullscreen)
            vidflags |= SDL_FULLSCREEN;
        else
            vidflags |= SDL_RESIZABLE;

        SDL_Surface* newscreen = SDL_SetVideoMode(size.x, size.y,
            state.bitdepth, vidflags);

        if(!newscreen) {
            return false;
        }
        mSDLScreen = newscreen;
        mPFScreen = *(mSDLScreen.format);

        //xxx: oh well... but it was true for both 32 bit and 16 bit screenmodes
        mPFAlphaScreen = mRGBA32;

        mCurVideoState = state;

        //i.e. reload textures, get rid of stuff in too low resolution...
        releaseCaches();

        return true;
    }

    VideoWindowState getVideoWindowState() {
        return mCurVideoState;
    }

    bool setVideoWindowState(in VideoWindowState state) {
        auto tmp1 = state, tmp2 = mCurVideoState;
        tmp1.window_caption = tmp2.window_caption = null;
        bool res = true;
        if (tmp1 != tmp2 && tmp1.video_active) {
            res = switchVideoTo(state);
        }
        SDL_WM_SetCaption(toStringz(state.window_caption), null);
        //xxx: what when switching fails?
        mCurVideoState = state;
        if (mCurVideoState.video_active)
            mFramework.driver_doVideoInit();
        return res;
    }

    DriverInputState getInputState() {
        DriverInputState state;
        state.grab_input = SDL_WM_GrabInput(SDL_GRAB_QUERY) == SDL_GRAB_ON;
        state.mouse_visible = SDL_ShowCursor(SDL_QUERY) == SDL_ENABLE;
        return state;
    }

    void setInputState(in DriverInputState state) {
        SDL_WM_GrabInput(state.grab_input ? SDL_GRAB_ON : SDL_GRAB_OFF);
        SDL_ShowCursor(state.mouse_visible ? SDL_ENABLE : SDL_DISABLE);
    }

    void setMousePos(Vector2i p) {
        SDL_WarpMouse(p.x, p.y);
    }

    bool getModifierState(Modifier mod, bool whatithink) {
        //special handling for the shift- and numlock-modifiers
        //since the user might toggle numlock or capslock while we don't have
        //the keyboard-focus, ask the SDL (which inturn asks the OS)
        SDLMod modstate = SDL_GetModState();
        //writefln("state=%s", modstate);
        if (mod == Modifier.Shift) {
            //xxx behaviour when caps and shift are both on is maybe OS
            //dependend; on X11, both states are usually XORed
            return ((modstate & KMOD_CAPS) != 0) ^ whatithink;
        //} else if (mod == Modifier.Numlock) {
        //    return (modstate & KMOD_NUM) != 0;
        } else {
            //generic handling for non-toggle modifiers
            return whatithink;
        }
    }

    private Keycode sdlToKeycode(int sdl_sym) {
        if (sdl_sym in gSdlToKeycode) {
            return gSdlToKeycode[sdl_sym];
        } else {
            return Keycode.INVALID; //sorry
        }
    }

    private KeyInfo keyInfosFromSDL(in SDL_KeyboardEvent sdl) {
        KeyInfo infos;
        infos.code = sdlToKeycode(sdl.keysym.sym);
        infos.unicode = sdl.keysym.unicode;
        infos.mods = mFramework.getModifierSet();
        return infos;
    }

    private KeyInfo mouseInfosFromSDL(in SDL_MouseButtonEvent mouse) {
        KeyInfo infos;
        infos.code = sdlToKeycode(g_sdl_mouse_button1 + (mouse.button - 1));
        return infos;
    }

    Canvas startScreenRendering() {
        assert(!!mSDLScreen);
        if (!mOpenGL) {
            mScreenCanvas2D.startScreenRendering();
            return mScreenCanvas2D;
        } else {
            mScreenCanvasGL.startScreenRendering();
            return mScreenCanvasGL;
        }
    }

    void stopScreenRendering() {
        if (!mOpenGL) {
            mScreenCanvas2D.stopScreenRendering();
        } else {
            mScreenCanvasGL.stopScreenRendering();
        }
    }

    void processInput() {
        SDL_Event event;
        while(SDL_PollEvent(&event)) {
            switch(event.type) {
                case SDL_KEYDOWN:
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    mFramework.driver_doKeyDown(infos);
                    break;
                case SDL_KEYUP:
                    //xxx TODO: SDL provides no unicode translation for KEYUP
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    mFramework.driver_doKeyUp(infos);
                    break;
                case SDL_MOUSEMOTION:
                    //update mouse pos after button state
                    mFramework.driver_doUpdateMousePos(Vector2i(event.motion.x,
                        event.motion.y));
                    break;
                case SDL_MOUSEBUTTONUP:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    mFramework.driver_doUpdateMousePos(Vector2i(event.button.x,
                        event.button.y));
                    mFramework.driver_doKeyUp(infos);
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    mFramework.driver_doUpdateMousePos(Vector2i(event.button.x,
                        event.button.y));
                    mFramework.driver_doKeyDown(infos);
                    break;
                case SDL_VIDEORESIZE:
                    mFramework.setVideoMode(Vector2i(event.resize.w,
                        event.resize.h));
                    break;
                // exit if SDLK or the window close button are pressed
                case SDL_QUIT:
                    mFramework.driver_doTerminate();
                    break;
                default:
            }
        }
    }

    void sleepTime(Time t) {
        SDL_Delay(t.msecs);
    }

    Canvas startOffscreenRendering(Surface s) {
        assert(!!s);
        auto c = new SDLCanvas(s);
        c.startDraw();
        return c;
    }

    //return a surface with unspecified size containing this color
    //(used for drawing alpha blended rectangles)
    private Surface insanityCache(Color c) {
        int key = c.toRGBA32();

        Surface* s = key in mInsanityCache;
        if (s)
            return *s;

        const cTileSize = 64;

        Surface tile = mFramework.createSurface(Vector2i(cTileSize),
            Transparency.Alpha);

        //xxx: be less wasteful (the Canvas instance)
        Canvas canvas = mFramework.startOffscreenRendering(tile);
        //if param. isn't false => infinite recursion :)
        canvas.drawFilledRect(Vector2i(0), tile.size, c, false);
        canvas.endDraw();
        delete canvas;

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
        count += fontDriver.releaseCaches();
        return count;
    }

    //this is the SDL_image dependency
    Surface loadImage(Stream source, Transparency transparency) {
        SDL_RWops* ops = rwopsFromStream(source);
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        if (!surf) {
            auto err = str.toString(IMG_GetError());
            throw new Exception("image couldn't be loaded: " ~ err);
        }

        return convertFromSDLSurface(surf, transparency, true, true);
    }

    Surface convertFromSDLSurface(SDL_Surface* surf, Transparency transparency,
        bool free_surf, bool dump = false)
    {
        if (transparency == Transparency.AutoDetect) {
            //guess by looking at the alpha channel
            transparency = sdlIsAlpha(surf) ? Transparency.Alpha
                : Transparency.Colorkey;
            //xxx: could check if colorkey color appears and set it to non-
            //     transparent if not
        }

        SurfaceData data;
        data.size = Vector2i(surf.w, surf.h);
        data.transparency = transparency;

        //possibly convert it to RGBA32 (except if it is already)
        if (!cmpPixelFormat(surf.format, &mRGBA32)) {
            data.pitch = data.size.x*4;
            data.data.length = data.pitch*data.size.y;

            //xxx code duplication
            SDL_Surface* ns = SDL_CreateRGBSurfaceFrom(data.data.ptr,
                surf.w, surf.h, mRGBA32.BitsPerPixel, data.pitch,
                mRGBA32.Rmask, mRGBA32.Gmask, mRGBA32.Bmask, mRGBA32.Amask);
            if (!ns) {
                SDL_FreeSurface(surf);
                throw new Exception("out of memory?");
            }
            SDL_SetAlpha(surf, 0, 0);  //lol SDL
            SDL_BlitSurface(surf, null, ns, null);
            SDL_FreeSurface(ns);
        } else {
            //just copy the data
            SDL_LockSurface(surf);
            data.pitch = surf.pitch;
            data.data.length = surf.pitch*data.size.y;
            data.data[] = cast(ubyte[])(surf.pixels[0 .. data.data.length]);
            SDL_UnlockSurface(surf);
        }

        if (free_surf) {
            SDL_FreeSurface(surf);
        }

        return new Surface(data);
    }

    char[] getDriverInfo() {
        char[] desc;

        char[] version_to_a(SDL_version v) {
            return format("%s.%s.%s", v.major, v.minor, v.patch);
        }

        SDL_version compiled, linked;
        SDL_VERSION(&compiled);
        linked = *SDL_Linked_Version();
        desc ~= format("SDLDriver, SDL compiled=%s linked=%s\n",
            version_to_a(compiled), version_to_a(linked));

        char[20] buf;
        char* res = SDL_VideoDriverName(buf.ptr, buf.length);
        desc ~= format("Driver: %s\n", res ? .toString(res) : "<unintialized>");

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
        desc ~= "Flags:\n" ~ flags;

        desc ~= "Screen:\n";
        desc ~= format("   size = %sx%s\n", info.current_w, info.current_h);
        desc ~= format("   video memory = %s\n", sizeToHuman(info.video_mem));
        SDL_PixelFormat* fmt = info.vfmt;
        desc ~= format("   pixel format = bits=%s"
            " R/G/B/A=%#08x/%#08x/%#08x/%#08x\n", fmt.BitsPerPixel, fmt.Rmask,
            fmt.Gmask, fmt.Bmask, fmt.Amask);

        desc ~= format("Uses OpenGL: %s\n", mOpenGL);
        if (mOpenGL) {
            void dumpglstr(GLenum t, char[] name) {
                desc ~= format("  %s = %s\n", name, .toString(glGetString(t)));
            }
            dumpglstr(GL_VENDOR, "GL_VENDOR");
            dumpglstr(GL_RENDERER, "GL_RENDERER");
            dumpglstr(GL_VERSION, "GL_VERSION");
        }

        desc ~= format("%d driver surfaces\n", mDriverSurfaceCount);

        return desc;
    }
}

class SDLCanvas : Canvas {
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

        SDL_Surface* mSurface;
        SDLSurface mSDLSurface;
    }

    void startScreenRendering() {
        assert(mStackTop == 0);
        assert(!mSDLSurface);
        assert(mSurface is null);

        mTrans = Vector2i(0, 0);
        mSurface = gSDLDriver.mSDLScreen;

        gSDLDriver.mClearTime.start();
        auto clearColor = Color(0,0,0);
        SDL_FillRect(mSurface, null, toSDLColor(clearColor));
        gSDLDriver.mClearTime.stop();

        startDraw();
    }

    void stopScreenRendering() {
        assert(mSurface !is null);

        endDraw();

        //TODO: Software backbuffer (or not... not needed with X11/windib)
        gSDLDriver.mFlipTime.start();
        SDL_Flip(mSurface);
        gSDLDriver.mFlipTime.stop();

        mSurface = null;
    }

    //offscreen rendering (on Surface)
    this(Surface s) {
        s.enableCaching = false;
        SDLSurface sdls = cast(SDLSurface)
            (s.getDriverSurface(SurfaceMode.OFFSCREEN));
        assert(!!sdls);
        //sdls.lock++;
        mSDLSurface = sdls;
        mSurface = sdls.mSurface;
    }

    this() {
    }

    package void startDraw() {
        assert(mStackTop == 0);
        SDL_SetClipRect(mSurface, null);
        mTrans = Vector2i(0, 0);
        pushState();
    }
    void endDraw() {
        popState();
        assert(mStackTop == 0);
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        gSDLDriver.mWasteTime.start();

        mStack[mStackTop].clip = mSurface.clip_rect;
        mStack[mStackTop].translate = mTrans;
        mStack[mStackTop].clientstart = mClientStart;
        mStack[mStackTop].clientsize = mClientSize;
        mStackTop++;

        gSDLDriver.mWasteTime.stop();
    }

    public void popState() {
        assert(mStackTop > 0);

        gSDLDriver.mWasteTime.start();

        mStackTop--;
        SDL_Rect* rc = &mStack[mStackTop].clip;
        SDL_SetClipRect(mSurface, rc);
        mTrans = mStack[mStackTop].translate;
        mClientStart = mStack[mStackTop].clientstart;
        mClientSize = mStack[mStackTop].clientsize;

        gSDLDriver.mWasteTime.stop();
    }

    public void setWindow(Vector2i p1, Vector2i p2) {
        gSDLDriver.mWasteTime.start();

        addclip(p1, p2);
        mTrans = p1 + mTrans;
        mClientStart = p1 + mTrans;
        mClientSize = p2 - p1;

        gSDLDriver.mWasteTime.stop();
    }

    //xxx: unify with clip(), or whatever, ..., etc.
    //oh, and this is actually needed in only a _very_ few places (scrolling)
    private void addclip(Vector2i p1, Vector2i p2) {
        p1 += mTrans; p2 += mTrans;
        SDL_Rect rc = mSurface.clip_rect;

        int rcx2 = rc.w + rc.x;
        int rcy2 = rc.h + rc.y;

        //common rect of old cliprect and (p1,p2)
        rc.x = max!(int)(rc.x, p1.x);
        rc.y = max!(int)(rc.y, p1.y);
        rcx2 = min!(int)(rcx2, p2.x);
        rcy2 = min!(int)(rcy2, p2.y);

        rc.w = max!(int)(rcx2 - rc.x, 0);
        rc.h = max!(int)(rcy2 - rc.y, 0);

        SDL_SetClipRect(mSurface, &rc);
    }

    public void clip(Vector2i p1, Vector2i p2) {
        p1 += mTrans; p2 += mTrans;
        SDL_Rect rc;
        rc.x = p1.x;
        rc.y = p1.y;
        rc.w = p2.x-p1.x;
        rc.h = p2.y-p1.y;
        SDL_SetClipRect(mSurface, &rc);
    }

    public void translate(Vector2i offset) {
        mTrans -= offset;
    }

    //definition: return client coords for screen coord (0, 0)
    public Vector2i clientOffset() {
        return -mTrans;
    }

    public Vector2i realSize() {
        return Vector2i(mSurface.w, mSurface.h);
    }
    public Vector2i clientSize() {
        return mClientSize;
    }

    public Rect2i getVisible() {
        Rect2i res;
        SDL_Rect rc = mSurface.clip_rect;
        res.p1.x = rc.x;
        res.p1.y = rc.y;
        res.p2.x = rc.x + rc.w;
        res.p2.y = rc.y + rc.h;
        res.p1 -= mTrans;
        res.p2 -= mTrans;
        return res;
    }

    public void draw(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        destPos += mTrans;

        assert(source !is null);
        SDLSurface sdls = cast(SDLSurface)
            (source.getDriverSurface(SurfaceMode.OFFSCREEN));
        //when this is null, maybe the user passed a GLTexture?
        assert(sdls !is null);

        SDL_Surface* src = sdls.mSurface;
        assert(src !is null);

        SDL_Rect rc, destrc;
        rc.x = cast(short)sourcePos.x;
        rc.y = cast(short)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        destrc.x = cast(short)destPos.x;
        destrc.y = cast(short)destPos.y; //destrc.w/h ignored by SDL_BlitSurface

        version(DrawStats) gSDLDriver.mDrawTime.start();
        int res = SDL_BlitSurface(src, &rc, mSurface, &destrc);
        assert(res == 0);
        version(DrawStats) gSDLDriver.mDrawTime.stop();

        version (MarkAlpha) {
            if (!gSDLDriver.mMarkAlpha)
                return;
            //only when drawn on screen
            bool isscreen = mSurface is gSDLDriver.mSDLScreen;
            if (isscreen && sdlIsAlpha(src)) {
                auto c = Color(0,1,0);
                destPos -= mTrans;
                drawRect(destPos, destPos + sourceSize, c);
                drawLine(destPos, destPos + sourceSize, c);
                drawLine(destPos + sourceSize.Y, destPos + sourceSize.X, c);
            }
        }
    }

    private uint toSDLColor(Color color) {
        if (mSDLSurface) {
            return mSDLSurface.colorToSDLColor(color);
        } else {
            return simpleColorToSDLColor(mSurface, color);
        }
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
                drawFilledRect(Vector2i(x1, y), Vector2i(x2, y+1), color, false);
            }
        );
    }

    public void drawLine(Vector2i from, Vector2i to, Color color) {
        //special cases for vlines/hlines
        if (from.y == to.y) {
            to.y++;
            if (from.x > to.x)
                swap(from.x, to.x);
            drawFilledRect(from, to, color, false);
            return;
        }
        if (from.x == to.x) {
            to.x++;
            if (from.y > to.y)
                swap(from.y, to.y);
            drawFilledRect(from, to, color, false);
            return;
        }

        uint c = toSDLColor(color);
        Vector2f d = Vector2f((to-from).x,(to-from).y);
        Vector2f old = toVector2f(from + mTrans);
        int n = cast(int)(math.fmax(math.fabs(d.x), math.fabs(d.y)));
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
    //  inclipped (coordinate must be inside of sdlsurface.mReal.clip_rect)
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

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
        drawLine(p1, Vector2i(p1.x, p2.y), color);
        drawLine(Vector2i(p1.x, p2.y), p2, color);
        drawLine(Vector2i(p2.x, p1.y), p2, color);
        drawLine(p1, Vector2i(p2.x, p1.y), color);
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color,
        bool properalpha = true)
    {
        int alpha = cast(ubyte)(color.a*255);
        if (alpha == 0 && properalpha)
            return; //xxx: correct?
        if (true && alpha != 255 && properalpha) {
            //quite insane insanity here!!!
            Texture s = gSDLDriver.insanityCache(color);
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
            version(DrawStats) gSDLDriver.mDrawTime.start();
            int res = SDL_FillRect(mSurface, &rect, toSDLColor(color));
            version(DrawStats) gSDLDriver.mDrawTime.stop();
            assert(res == 0);
        }
    }

    public void clear(Color color) {
        drawFilledRect(Vector2i(0, 0)-mTrans, clientSize-mTrans, color, false);
    }
}

static this() {
    FrameworkDriverFactory.register!(SDLDriver)("sdl");
}
