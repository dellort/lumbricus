module framework.sdl.framework;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import derelict.sdl.image;
import framework.framework;
import framework.event;
import framework.sdl.rwops;
import framework.sdl.fwgl;
import framework.sdl.sdl;
import framework.sdl.keys;
import utils.vector2;
import utils.time;
import utils.perf;
import utils.drawing;
import utils.misc;
import utils.configfile;

import math = tango.math.Math;
import ieee = tango.math.IEEE;
import stdx.stream;
import tango.stdc.stringz;
import tango.sys.Environment;

import str = utils.string;

version = MarkAlpha;

package uint simpleColorToSDLColor(SDL_Surface* s, Color color) {
    auto c = color.toRGBA32();
    return SDL_MapRGBA(s.format, c.r, c.g, c.b, c.a);
}

package SDL_Color ColorToSDLColor(Color color) {
    auto c = color.toRGBA32();
    SDL_Color col;
    col.r = c.r;
    col.g = c.g;
    col.b = c.b;
    col.unused = c.a;
    return col;
}

package bool sdlIsAlpha(SDL_Surface* s) {
    return s.format.Amask != 0 && (s.flags & SDL_SRCALPHA);
}

//common base class for SDLSurface and GLSurface
class SDLDriverSurface : DriverSurface {
    SurfaceData* mData;

    this(SurfaceData* data) {
        gSDLDriver.mDriverSurfaceCount++;
        mData = data;
    }

    //must be overriden; super method must be called on end
    void kill() {
        assert(!!mData, "double kill()?");
        gSDLDriver.mDriverSurfaceCount--;
        mData = null;
    }
}

void doMirrorY(SurfaceData* data) {
    for (uint y = 0; y < data.size.y; y++) {
        Color.RGBA32* src = data.data.ptr+y*data.pitch+data.size.x;
        Color.RGBA32* dst = data.data.ptr+y*data.pitch;
        for (uint x = 0; x < data.size.x/2; x++) {
            src--;
            swap(*dst, *src);
            dst++;
        }
    }
}

void doMirrorX(SurfaceData* data) {
    Color.RGBA32[] tmp = new Color.RGBA32[data.pitch];
    for (int y = 0; y < data.size.y/2; y++) {
        int ym = data.size.y - y - 1;
        tmp[] = data.data[y*data.pitch..(y+1)*data.pitch];
        data.data[y*data.pitch..(y+1)*data.pitch] =
            data.data[ym*data.pitch..(ym+1)*data.pitch];
        data.data[ym*data.pitch..(ym+1)*data.pitch] = tmp;
    }
    delete tmp;
}

//cache for effects like mirroring; this is only used when you're using i.e.
//drawMirrored() on a SDLCanvas (when no OpenGL is used / for offscreen drawing)
/+final+/ class EffectCache {
    private {
        SDLSurface mSource;
        SDLSurface mMirroredY;
    }

    this(SDLSurface source) {
        assert(!!source);
        mSource = source;
    }

    //free all surface this class has created
    //(which means the source surface is not free'd)
    void kill() {
        if (mMirroredY) {
            mMirroredY.kill();
            mMirroredY = null;
        }
    }

    SDLSurface mirroredY() {
        if (!mMirroredY) {
            //NOTE: this is a bit unclean. sry!
            SurfaceData* ndata = new SurfaceData;
            *ndata = *mSource.mData;
            ndata.data = ndata.data.dup;
            doMirrorY(ndata);
            mMirroredY = new SDLSurface(ndata);
        }
        return mMirroredY;
    }
}

/+final+/ class SDLSurface : SDLDriverSurface {
    SDL_Surface* mSurface;
    bool mCacheEnabled;

    //NOTE: the stuff associated with mCacheEnabled doesn't have anything to do
    //      with this; mEffects is always created if the Canvas needs it
    EffectCache mEffects;

    //create from Framework's data
    this(SurfaceData* data) {
        super(data);
        reinit();
    }

    //release data from driver surface
    override void kill() {
        releaseSurface();
        super.kill();
    }

    private void releaseSurface() {
        if (mEffects) {
            mEffects.kill();
            mEffects = null;
        }
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
        auto rgba32 = gSDLDriver.mRGBA32;
        mSurface = SDL_CreateRGBSurfaceFrom(mData.data.ptr, mData.size.x,
            mData.size.y, 32, mData.pitch*4, rgba32.Rmask, rgba32.Gmask,
            rgba32.Bmask, rgba32.Amask);
        if (!mSurface) {
            throw new FrameworkException(
                myformat("couldn't create SDL surface, size={}", mData.size));
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
        //assert(!SDL_MUSTLOCK(mSurface));
        //^ no, not a requirement, I think... I hope...
    }

    void updatePixels(in Rect2i rc) {
        rc.fitInsideB(Rect2i(0,0,mData.size.x,mData.size.y));

        if (mData.transparency == Transparency.Colorkey) {
            //if colorkey is enabled, one must "fix up" the updated pixels, so
            //one can be sure non-transparent pixels are actually equal to the
            //color key
            auto ckey = mData.colorkey.toRGBA32();
            ckey.a = 0;
            for (int y = rc.p1.y; y < rc.p2.y; y++) {
                int w = rc.size.x;
                Color.RGBA32* pix = mData.data.ptr + mData.pitch*y + rc.p1.x;
                for (int x = 0; x < w; x++) {
                    if (pixelIsTransparent(pix)) {
                        *pix = ckey;
                    }
                    pix++;
                }
            }
        }
        if (mCacheEnabled) {
            reinit();
        }
    }

    private bool convertToDisplay() {
        assert(!!mSurface);

        if (!(mData.enable_cache && gSDLDriver.mEnableCaching)) {
            return false;
        }

        bool rle = gSDLDriver.mRLE;

        SDL_Surface* nsurf;
        bool colorkey;
        switch (mData.transparency) {
            case Transparency.Colorkey:
                colorkey = true;
                //yay, first time in my life I want to fall through!
            case Transparency.None: {
                if (rle || !gSDLDriver.isDisplayFormat(mSurface, false)) {
                    nsurf = SDL_DisplayFormat(mSurface);
                    /+Trace.formatln("before: {}",
                        gSDLDriver.pixelFormatToString(mSurface.format));
                    Trace.formatln("after: {}",
                        gSDLDriver.pixelFormatToString(nsurf.format));+/
                    if (rle) {
                        uint key = simpleColorToSDLColor(nsurf, mData.colorkey);
                        SDL_SetColorKey(nsurf, (colorkey ? SDL_SRCCOLORKEY : 0)
                            | SDL_RLEACCEL, key);
                    }
                }
                break;
            }
            case Transparency.Alpha: {
                if (rle || !gSDLDriver.isDisplayFormat(mSurface, true)) {
                    nsurf = SDL_DisplayFormatAlpha(mSurface);
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
        desc = myformat("c={}", mCacheEnabled);
        if (mCacheEnabled) {
            extra_data = mSurface.pitch * 4 * mSurface.h;
        }
    }

    EffectCache effectCache() {
        if (!mEffects) {
            mEffects = new EffectCache(this);
        }
        return mEffects;
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
        DriverInputState mInputState;

        //convert stuff to display format if it isn't already
        //+ mark all alpha surfaces drawn on the screen
        package bool mEnableCaching, mMarkAlpha, mRLE;

        //instead of a DriverSurface list (we don't need that yet?)
        package uint mDriverSurfaceCount;

        //used only for non-OpenGL rendering
        //valid fields: BitsPerPixel, Rmask, Gmask, Bmask, Amask
        SDL_PixelFormat mRGBA32, mPFScreen, mPFAlphaScreen;

        //if OpenGL enabled (if not, use 2D SDL drawing)
        package bool mOpenGL, mOpenGL_LowQuality;

        //depending if OpenGL or plain-old-SDL-2D mode
        SDLCanvas mScreenCanvas2D;
        GLCanvas mScreenCanvasGL;

        //cache for being able to draw alpha blended filled rects without OpenGL
        Surface[uint] mInsanityCache;

        SDL_Cursor* mCursorStd, mCursorNull;

        //only used by the mouse lock code
        Vector2i mMousePos;
        Vector2i mStoredMousePos, mLockedMousePos, mMouseCorr;
        bool mLockMouse;
        int mFooLockCounter;

        Vector2i mDesktopRes;
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
        mRGBA32.Rmask = Color.cMaskR;
        mRGBA32.Gmask = Color.cMaskG;
        mRGBA32.Bmask = Color.cMaskB;
        mRGBA32.Amask = Color.cMaskAlpha;

        mEnableCaching = config.getBoolValue("enable_caching", true);
        mMarkAlpha = config.getBoolValue("mark_alpha", false);
        mRLE = config.getBoolValue("rle", true);

        mOpenGL = config.getBoolValue("open_gl", true);
        mOpenGL_LowQuality = config.getBoolValue("lowquality", false);
        glWireframeDebug = config.getBoolValue("gl_debug_wireframe", false);

        //CENTERED doesn't work - somehow resizing the window enters an endless
        //loop on IceWM... anyway, it makes me want to beat up the SDL devs
        //it also could be our or IceWM's fault
        //Environment.set("SDL_VIDEO_CENTERED", "center");
        //Environment.set("SDL_VIDEO_WINDOW_POS", "0,0");

        sdlInit();

        DerelictSDLImage.load();
        if (mOpenGL) {
            DerelictGL.load();
            DerelictGLU.load();
        }

        if (SDL_InitSubSystem(SDL_INIT_VIDEO) < 0) {
            throw new FrameworkException(myformat(
                "Could not init SDL video: {}", fromStringz(SDL_GetError())));
        }

        //when called before first SetVideoMode, this returns the desktop res
        auto vi = SDL_GetVideoInfo();
        mDesktopRes = Vector2i(vi.current_w, vi.current_h);

        /*SDL_Rect** modes;
        modes = SDL_ListModes(null, SDL_FULLSCREEN | SDL_OPENGL);
        for (int i = 0; modes[i]; ++i) {
            Trace.formatln("{}x{}", modes[i].w, modes[i].h);
        }*/

        mCursorStd = SDL_GetCursor();
        ubyte[(32*32)/8] cursor; //init with 0, which means all-transparent
        mCursorNull = SDL_CreateCursor(cursor.ptr, cursor.ptr, 32, 32, 0, 0);
        if (!mCursorNull) {
            throw new FrameworkException("couldn't create SDL cursor");
        }

        SDL_EnableUNICODE(1);
        SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY,
            SDL_DEFAULT_REPEAT_INTERVAL);

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            gSdlToKeycode[item.sdlcode] = item.code;
        }

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
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        if (mOpenGL) {
            DerelictGL.unload();
            DerelictGLU.unload();
        }
        DerelictSDLImage.unload();
        sdlQuit();

        gSDLDriver = null;
    }

    int getFeatures() {
        int features = 0;
        if (mOpenGL) {
            features = features | DriverFeatures.canvasScaling
                | DriverFeatures.transformedQuads | DriverFeatures.usingOpenGL;
        }
        return features;
    }

    DriverSurface createSurface(SurfaceData* data, SurfaceMode mode) {
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
        auto bla = cast(SDLDriverSurface)surface;
        assert(!!bla);
        bla.kill();
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

        //i.e. reload textures, get rid of stuff in too low resolution...
        mFramework.releaseCaches(false);

        Vector2i size = state.fullscreen ? state.fs_size : state.window_size;

        int vidflags = 0;
        if (mOpenGL) {
            //SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 16);
            SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

            //OpenGL flags for SDL_SetVideoMode
            vidflags |= SDL_OPENGL;
        }
        else
            //SDL only flags for SDL_SetVideoMode
            vidflags |= SDL_SWSURFACE | SDL_DOUBLEBUF;
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

        if (mScreenCanvasGL) {
            DerelictGL.loadExtensions();
            //xxx move call to GL initialization here
        }

        //xxx: oh well... but it was true for both 32 bit and 16 bit screenmodes
        mPFAlphaScreen = mRGBA32;

        mCurVideoState = state;

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
        mCurVideoState = state;
        mCurVideoState.video_active = !!mSDLScreen;
        if (mCurVideoState.video_active)
            mFramework.driver_doVideoInit();
        return mCurVideoState.video_active;
    }

    Vector2i getDesktopResolution() {
        return mDesktopRes;
    }

    DriverInputState getInputState() {
        //SDL_ShowCursor(SDL_QUERY);
        return mInputState;
    }

    void setInputState(in DriverInputState state) {
        if (state == mInputState)
            return;
        setLockMouse(state.mouse_locked);
        SDL_WM_GrabInput(state.grab_input ? SDL_GRAB_ON : SDL_GRAB_OFF);
        SDL_ShowCursor(state.mouse_visible ? SDL_ENABLE : SDL_DISABLE);
        //Derelict's SDL_QUERY is wrong, which caused me some hours of debugging
        //derelict/sdl/events.d ->
        //   enum : Uint8 {
        //      SDL_QUERY           = cast(Uint8)-1,
        //<- derelict
        //but it really should be -1, not 255
        //so this call did crap: SDL_ShowCursor(SDL_QUERY);
        // WHO THE FUCK DID COME UP WITH "enum : Uint8"??? RAGE RAGE RAGE RAGE
        //I even thought hiding the cursor didn't work at all, so I had this:
        //SDL_SetCursor(state.mouse_visible ? mCursorStd : mCursorNull);
        mInputState = state;
    }

    void setMousePos(Vector2i p) {
        SDL_WarpMouse(p.x, p.y);
    }

    bool getModifierState(Modifier mod, bool whatithink) {
        //special handling for the shift- and numlock-modifiers
        //since the user might toggle numlock or capslock while we don't have
        //the keyboard-focus, ask the SDL (which inturn asks the OS)
        SDLMod modstate = SDL_GetModState();
        //writefln("state={}", modstate);
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

    void setLockMouse(bool s) {
        if (s == mLockMouse)
            return;

        if (!mLockMouse) {
            mLockedMousePos = Vector2i(mSDLScreen.w, mSDLScreen.h)/2;
            mStoredMousePos = mMousePos;
            setMousePos(mLockedMousePos);
            //mMouseCorr = mStoredMousePos - mLockedMousePos;
            mMouseCorr = Vector2i(0);
            //discard 3 events from now
            mFooLockCounter = 3;
        } else {
            setMousePos(mStoredMousePos);
            mMousePos = mStoredMousePos; //avoid a large rel on next update
            mLockMouse = false;
            mMouseCorr = Vector2i(0);
        }

        mLockMouse = s;
    }

    void updateMousePos(Vector2i pos) {
        if (mMousePos == pos)
            return;

        auto npos = pos;
        auto nrel = pos - mMousePos;

        mMousePos = pos;

        if (mLockMouse) {
            //xxx this hack throws away the first 3 relative motions
            //when in locked mode to fix SDL stupidness
            mFooLockCounter--;
            if (mFooLockCounter > 0)
                nrel = Vector2i(0);
            else
                mFooLockCounter = 0;
            //pretend mouse to be at stored position
            npos = mStoredMousePos;
            //correct the last cursor position change made
            nrel += mMouseCorr;
            setMousePos(mLockedMousePos);
            //save position change to subtract later, as this will
            //generate an event
            mMouseCorr = (pos-mLockedMousePos);
        }

        mFramework.driver_doUpdateMousePos(npos, nrel);
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
                    updateMousePos(Vector2i(event.motion.x, event.motion.y));
                    break;
                case SDL_MOUSEBUTTONUP:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    updateMousePos(Vector2i(event.button.x, event.button.y));
                    mFramework.driver_doKeyUp(infos);
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    updateMousePos(Vector2i(event.button.x, event.button.y));
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

    //return a surface with unspecified size containing this color
    //(used for drawing alpha blended rectangles)
    private Surface insanityCache(Color c) {
        uint key = c.toRGBA32().uint_val;

        Surface* s = key in mInsanityCache;
        if (s)
            return *s;

        const cTileSize = 64;

        Surface tile = mFramework.createSurface(Vector2i(cTileSize),
            Transparency.Alpha);

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

    //this is the SDL_image dependency
    Surface loadImage(Stream source, Transparency transparency) {
        SDL_RWops* ops = rwopsFromStream(source);
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        if (!surf) {
            auto err = fromStringz(IMG_GetError());
            throw new FrameworkException("image couldn't be loaded: " ~ err);
        }

        return convertFromSDLSurface(surf, transparency, true, true);
    }

    Surface screenshot() {
        if (mOpenGL) {
            SurfaceData data;
            data.size = Vector2i(mSDLScreen.w, mSDLScreen.h);
            data.transparency = Transparency.None;
            data.pitch = mSDLScreen.w;
            data.data.length = data.pitch*data.size.y;
            //get screen contents, (0, 0) is bottom left in OpenGL, so
            //  image will be upside-down
            glReadPixels(0, 0, mSDLScreen.w, mSDLScreen.h, GL_RGBA,
                GL_UNSIGNED_BYTE, data.data.ptr);
            //checkGLError("glReadPixels");
            //mirror image on x axis
            doMirrorX(&data);
            return new Surface(data);
        } else {
            //this is possibly dangerous, but I'm too lazy to write proper code
            //  (pure SDL mode is dying anyway)
            return convertFromSDLSurface(mSDLScreen, Transparency.None, false);
        }
    }

    //convert SDL color to our Color struct; do _not_ try to check the colorkey
    //to convert it to a transparent color, and also throw away the alpha value
    //there doesn't seem to be a SDL version for this, I hate SDL!!!
    private static Color fromSDLColor(SDL_PixelFormat* fmt, uint c) {
        Color r;
        if (!fmt.palette) {
            //warning, untested (I think, maybe)
            float conv(uint mask, uint shift, uint loss) {
                return (((c & mask) >> shift) << loss)/255.0f;
            }
            r.r = conv(fmt.Rmask, fmt.Rshift, fmt.Rloss);
            r.g = conv(fmt.Gmask, fmt.Gshift, fmt.Gloss);
            r.b = conv(fmt.Bmask, fmt.Bshift, fmt.Bloss);
        } else {
            //palette... sigh!
            assert(c < fmt.palette.ncolors, "WHAT THE SHIT");
            SDL_Color s = fmt.palette.colors[c];
            r.r = s.r/255.0f;
            r.g = s.g/255.0f;
            r.b = s.b/255.0f;
            r.a = s.unused/255.0f;
            assert(ColorToSDLColor(r) == s);
        }
        return r;
    }

    //warning: modifies the source surface!
    Surface convertFromSDLSurface(SDL_Surface* surf, Transparency transparency,
        bool free_surf, bool dump = false)
    {
        if (transparency == Transparency.AutoDetect) {
            //guess by looking at the alpha channel
            if (sdlIsAlpha(surf)) {
                transparency = Transparency.Alpha;
            } else if (surf.flags & SDL_SRCCOLORKEY) {
                transparency = Transparency.Colorkey;
            } else {
                transparency = Transparency.None;
            }
        }

        SurfaceData data;
        data.size = Vector2i(surf.w, surf.h);
        data.transparency = transparency;

        bool hascc = transparency == Transparency.Colorkey;

        if (hascc) {
            //NOTE: the png loader from SDL_Image sometimes uses the colorkey
            data.colorkey = fromSDLColor(surf.format, surf.format.colorkey);
        }

        bool not_crap = !!(surf.flags & SDL_SRCALPHA);

        //possibly convert it to RGBA32 (except if it is already)
        //if there's a colorkey, always convert, hoping the alpha channel gets
        //fixed (setting the alpha according to colorkey)
        if (!(not_crap && cmpPixelFormat(surf.format, &mRGBA32))) {
            data.pitch = data.size.x;
            data.data.length = data.pitch*data.size.y;

            SDL_Surface* ns = SDL_CreateRGBSurfaceFrom(data.data.ptr,
                surf.w, surf.h, mRGBA32.BitsPerPixel, data.pitch*4,
                mRGBA32.Rmask, mRGBA32.Gmask, mRGBA32.Bmask, mRGBA32.Amask);
            if (!ns)
                throw new FrameworkException("out of memory?");
            SDL_SetAlpha(surf, 0, 0);  //lol SDL, disable all transparencies
            //not sure about this, but commenting this seems to work better with
            //paletted+transparent png files (but only in OpenGL mode lol)
            //by the way, using SDL_ConvertSurface worked even worse
            //SDL_SetColorKey(surf, 0, 0);
            SDL_BlitSurface(surf, null, ns, null);
            SDL_FreeSurface(ns);
            //xxx: need to restore for surf what was destroyed by SDL_SetAlpha
        } else {
            //just copy the data
            SDL_LockSurface(surf);
            data.pitch = surf.pitch/4;
            assert (data.pitch*4 == surf.pitch);
            data.data.length = data.pitch*data.size.y;
            data.data[] = cast(Color.RGBA32[])
                (surf.pixels[0 .. data.data.length*4]);
            SDL_UnlockSurface(surf);
        }

        if (free_surf) {
            SDL_FreeSurface(surf);
        }

        return new Surface(data);
    }

    private char[] pixelFormatToString(SDL_PixelFormat* fmt) {
        return myformat("bits={} R/G/B/A={:x8}/{:x8}/{:x8}/{:x8}",
            fmt.BitsPerPixel, fmt.Rmask, fmt.Gmask, fmt.Bmask, fmt.Amask);
    }

    char[] getDriverInfo() {
        char[] desc;

        char[] version_to_a(SDL_version v) {
            return myformat("{}.{}.{}", v.major, v.minor, v.patch);
        }

        SDL_version compiled, linked;
        SDL_VERSION(&compiled);
        linked = *SDL_Linked_Version();
        desc ~= myformat("SDLDriver, SDL compiled={} linked={}\n",
            version_to_a(compiled), version_to_a(linked));

        char[20] buf;
        char* res = SDL_VideoDriverName(buf.ptr, buf.length);
        desc ~= myformat("Driver: {}\n", res ? fromStringz(res)
            : "<unintialized>");

        SDL_VideoInfo info = *SDL_GetVideoInfo();

        //in C, info.flags doesn't exist, but instead there's a bitfield
        //here are the names of the bitfield entries (in order)
        char[][] flag_names = ["hw_available", "wm_available",
            "blit_hw", "blit_hw_CC", "blit_hw_A", "blit_sw",
            "blit_sw_CC", "blit_sw_A", "blit_fill"];

        char[] flags;
        foreach (int index, name; flag_names) {
            bool set = !!(info.flags & (1<<index));
            flags ~= myformat("  {}: {}\n", name, (set ? "1" : "0"));
        }
        desc ~= "Flags:\n" ~ flags;

        desc ~= "Screen:\n";
        desc ~= myformat("   size = {}x{}\n", info.current_w, info.current_h);
        desc ~= myformat("   video memory = {}\n",
            str.sizeToHuman(info.video_mem));
        SDL_PixelFormat* fmt = info.vfmt;
        desc ~= myformat("   pixel format = {}\n", pixelFormatToString(fmt));

        desc ~= myformat("Uses OpenGL: {}\n", mOpenGL);
        if (mOpenGL) {
            void dumpglstr(GLenum t, char[] name) {
                desc ~= myformat("  {} = {}\n", name,
                    fromStringz(glGetString(t)));
            }
            dumpglstr(GL_VENDOR, "GL_VENDOR");
            dumpglstr(GL_RENDERER, "GL_RENDERER");
            dumpglstr(GL_VERSION, "GL_VERSION");
        }

        desc ~= myformat("{} driver surfaces\n", mDriverSurfaceCount);

        return desc;
    }
}

class SDLCanvas : Canvas {
    const int MAX_STACK = 20;

    private {
        struct State {
            SDL_Rect clip;
            Vector2i translate;
            Vector2i clientsize;
        }

        Vector2i mTrans;
        State[MAX_STACK] mStack;
        uint mStackTop; //point to next free stack item (i.e. 0 on empty stack)

        Vector2i mClientSize;

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

    public int features() {
        return gSDLDriver.getFeatures();
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        gSDLDriver.mWasteTime.start();

        mStack[mStackTop].clip = mSurface.clip_rect;
        mStack[mStackTop].translate = mTrans;
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
        mClientSize = mStack[mStackTop].clientsize;

        gSDLDriver.mWasteTime.stop();
    }

    public void setWindow(Vector2i p1, Vector2i p2) {
        gSDLDriver.mWasteTime.start();

        addclip(p1, p2);
        mTrans = p1 + mTrans;
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
        rc.x = max(rc.x, p1.x);
        rc.y = max(rc.y, p1.y);
        rcx2 = min(rcx2, p2.x);
        rcy2 = min(rcy2, p2.y);

        rc.w = max(rcx2 - rc.x, 0);
        rc.h = max(rcy2 - rc.y, 0);

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
        mTrans += offset;
    }

    public void setScale(Vector2f z) {
        //not supported
    }

    public Vector2i realSize() {
        return Vector2i(mSurface.w, mSurface.h);
    }
    public Vector2i clientSize() {
        return mClientSize;
    }

    //parent window area, in client coords
    public Rect2i parentArea() {
        Rect2i ret;
        ret.p1 = -mStack[mStackTop].translate + mStack[mStackTop - 1].translate;
        ret.p2 = ret.p1 + mStack[mStackTop - 1].clientsize;
        return ret;
    }

    public Rect2i visibleArea() {
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
        Vector2i sourcePos, Vector2i sourceSize, bool mirrorY = false)
    {
        destPos += mTrans;

        assert(source !is null);
        SDLSurface sdls = cast(SDLSurface)
            (source.getDriverSurface(SurfaceMode.OFFSCREEN));
        //when this is null, maybe the user passed a GLTexture?
        assert(sdls !is null);

        //possibly need to replace the bitmap
        if (mirrorY) {
            auto ec = sdls.effectCache();
            sdls = ec.mirroredY();
            //invert the source coordinates as well!
            sourcePos.x = sdls.mData.size.x - sourcePos.x - sourceSize.x;
        }

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
                drawFilledRect(Vector2i(x1, y), Vector2i(x2, y+1), color);
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
            drawFilledRect(from, to, color);
            return;
        }
        if (from.x == to.x) {
            to.x++;
            if (from.y > to.y)
                swap(from.y, to.y);
            to.y++;
            drawFilledRect(from, to, color);
            return;
        }

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

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        p2.x -= 1; //border exclusive
        p2.y -= 1;
        drawLine(p1, Vector2i(p1.x, p2.y), color);
        drawLine(Vector2i(p1.x, p2.y), p2, color);
        drawLine(Vector2i(p2.x, p1.y), p2, color);
        drawLine(p1, Vector2i(p2.x, p1.y), color);
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        int alpha = cast(ubyte)(color.a*255);
        if (alpha == 0)
            return; //xxx: correct?
        if (alpha != 255) {
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

    public void drawVGradient(Rect2i rc, Color c1, Color c2) {
        auto dy = rc.p2.y - rc.p1.y;
        auto dc = c2 - c1;
        //xxx clip against y?
        auto a = rc.p1;
        auto b = Vector2i(rc.p2.x, a.y + 1);
        for (int y = 0; y < dy; y++) {
            //SDL's FillRect is probably quite good at drawing solid horizontal
            //lines, so there's no reason not to use it
            //drawFilledRect of course still has a lot of overhead...
            drawFilledRect(a, b, c1 + dc * (1.0f*y/dy));
            a.y++;
            b.y++;
        }
    }

    public void clear(Color color) {
        drawFilledRect(Vector2i(0, 0)-mTrans, clientSize-mTrans, color);
    }

    //unsupported
    public void drawQuad(Surface tex, Vertex2i[4] quad) {
    }
}

static this() {
    FrameworkDriverFactory.register!(SDLDriver)("sdl");
}
