module framework.drivers.base_sdl;

import derelict.sdl.sdl;
import derelict.sdl.image;
import framework.framework;
import framework.globalsettings;
import framework.event;
import framework.sdl.rwops;
import framework.sdl.sdl;
import framework.sdl.keys;
import utils.vector2;
import utils.time;
import utils.perf;
import utils.drawing;
import utils.misc;
import utils.strparser;

import math = tango.math.Math;
import ieee = tango.math.IEEE;
import utils.stream;
import tango.stdc.stringz;
import tango.sys.Environment;
import tunicode = tango.text.Unicode;

import str = utils.string;

const cDrvName = "base_sdl";

package {
    Keycode[int] gSdlToKeycode;
    //cached unicode translations
    //(just so that not each keystroke causes memory allocation)
    char[][dchar] gUniCache;

    char[] fromUnicode(dchar uc) {
        if (uc == '\0')
            return null;
        if (!str.isValidDchar(uc)) {
            //special "error" case
            return myformat("?[0x{:x}]", cast(uint)uc);
        }
        if (auto pres = uc in gUniCache)
            return *pres;
        //SDL is not very accurate here and returns unicode even for control
        //  keys like ESC
        if (!tunicode.isPrintable(uc))
            return null;
        char[] res;
        str.encode(res, uc);
        gUniCache[uc] = res;
        return res;
    }
}

class SDLDriver : FrameworkDriver {
    private {
        VideoWindowState mCurVideoState;
        DriverInputState mInputState;

        SDL_Cursor* mCursorStd, mCursorNull;

        //only used by the mouse lock code
        Vector2i mMousePos;
        Vector2i mStoredMousePos, mLockedMousePos, mMouseCorr;
        bool mLockMouse;
        int mFooLockCounter;

        Vector2i mDesktopRes;

        //SDL window is focused / visible
        bool mInputFocus = true, mWindowVisible = true;

        SDL_Surface* mSDLScreen;
    }

    this() {
        //default (empty) means use OS default
        char[] wndPos = getSetting!(char[])(cDrvName ~ ".window_pos");

        //those environment vars cause trouble for me under Linux/IceWM
        //maybe there's a reason these are not official features
        version(Windows) {
            if (wndPos == "center") {
                Environment.set("SDL_VIDEO_CENTERED", "center");
            } else {
                try {
                    //empty (or invalid) value will throw and not set the var
                    Vector2i pos = fromStr!(Vector2i)(wndPos);
                    Environment.set("SDL_VIDEO_WINDOW_POS", myformat("{},{}",
                        pos.x, pos.y));
                } catch (ConversionException e) {
                    //ignore
                }
            }
        }

        sdlInit();

        DerelictSDLImage.load();

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
    }

    void destroy() {
        //the framework should have destroyed all DriverSurfaces
        //check that!
        //assert(mDriverSurfaceCount == 0);

        //deinit and unload all SDL dlls (in reverse order)
        if (gOnSDLVideoInit)
            gOnSDLVideoInit(false);
        SDL_QuitSubSystem(SDL_INIT_VIDEO);
        DerelictSDLImage.unload();
        sdlQuit();
    }

    private bool switchVideoTo(VideoWindowState state) {
        if (state.bitdepth < 0)
            state.bitdepth = 0;

        //i.e. reload textures, get rid of stuff in too low resolution...
        gFramework.releaseCaches(false);

        Vector2i size = state.actualSize();

        int vidflags = 0;
        if (gFramework.drawDriver.getFeatures() & DriverFeatures.usingOpenGL) {
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

        //reinit clipboard because we need the Xlib Window
        //SDL makes this a pain
        if (gOnSDLVideoInit)
            gOnSDLVideoInit(false);
        if (gOnSDLVideoInit)
            gOnSDLVideoInit(true);

        return true;
    }

    override void flipScreen() {
        if (gFramework.drawDriver.getFeatures() & DriverFeatures.usingOpenGL)
            SDL_GL_SwapBuffers();
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
        version(Windows) {
            //get window handle (some draw drivers need this)
            if (mSDLScreen) {
                //only if a window was opened
                SDL_SysWMinfo wminfo;
                SDL_VERSION(&wminfo.ver);
                int r = SDL_GetWMInfo(&wminfo);
                assert(r == 1);
                state.window_handle = wminfo.window;
            }
        }
        SDL_WM_SetCaption(toStringz(state.window_caption), null);
        mCurVideoState = state;
        mCurVideoState.video_active = !!mSDLScreen;
        if (mCurVideoState.video_active)
            gFramework.driver_doVideoInit();
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
        mInputState = state;
        update_sdl_mouse_state();
    }

    private void update_sdl_mouse_state() {
        bool cursor_visible = mInputState.mouse_visible;
        //never hide cursor when not focused
        if (!mInputFocus)
            cursor_visible = true;
        //NOTE: ShowCursor is buggy, don't use (Windows, fullscreen)
        //SetCursor is used instead
        //SDL_ShowCursor(state.mouse_visible ? SDL_ENABLE : SDL_DISABLE);
        //Derelict's SDL_QUERY is wrong, which caused me some hours of debugging
        //derelict/sdl/events.d ->
        //   enum : Uint8 {
        //      SDL_QUERY           = cast(Uint8)-1,
        //<- derelict
        //but it really should be -1, not 255
        //so this call did crap: SDL_ShowCursor(SDL_QUERY);
        // WHO THE FUCK DID COME UP WITH "enum : Uint8"??? RAGE RAGE RAGE RAGE
        SDL_SetCursor(cursor_visible ? mCursorStd : mCursorNull);
    }

    void setMousePos(Vector2i p) {
        if (mInputFocus)
            SDL_WarpMouse(p.x, p.y);
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
        infos.unicode = fromUnicode(sdl.keysym.unicode);
        infos.mods = gFramework.getModifierSet();
        return infos;
    }

    private KeyInfo mouseInfosFromSDL(in SDL_MouseButtonEvent mouse) {
        KeyInfo infos;
        infos.code = sdlToKeycode(g_sdl_mouse_button1 + (mouse.button - 1));
        return infos;
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

    void updateMousePos(int x, int y) {
        auto pos = Vector2i(x, y);

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

        gFramework.driver_doUpdateMousePos(npos, nrel);
    }

    void processInput() {
        bool queuedVideoResize;
        Vector2i newVideoSize;
        SDL_Event event;
        while(SDL_PollEvent(&event)) {
            if (gSDLEventFilter) {
                if (gSDLEventFilter(&event))
                    continue;
            }
            switch(event.type) {
                case SDL_KEYDOWN:
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    infos.isDown = true;
                    //SDL repeats SDL_KEYDOWN on key repeat
                    //that's exactly how the framework does it
                    //SDL doesn't provide an isRepeated, though
                    infos.isRepeated = gFramework.getKeyState(infos.code);
                    gFramework.driver_doKeyEvent(infos);
                    break;
                case SDL_KEYUP:
                    //xxx TODO: SDL provides no unicode translation for KEYUP
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    infos.isDown = false;
                    gFramework.driver_doKeyEvent(infos);
                    break;
                case SDL_MOUSEMOTION:
                    //update mouse pos after button state
                    if (mInputFocus)
                        updateMousePos(event.motion.x, event.motion.y);
                    break;
                case SDL_MOUSEBUTTONUP:
                    if (mInputFocus) {
                        KeyInfo infos = mouseInfosFromSDL(event.button);
                        infos.isDown = false;
                        updateMousePos(event.button.x, event.button.y);
                        gFramework.driver_doKeyEvent(infos);
                    }
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    if (mInputFocus) {
                        KeyInfo infos = mouseInfosFromSDL(event.button);
                        infos.isDown = true;
                        updateMousePos(event.button.x, event.button.y);
                        gFramework.driver_doKeyEvent(infos);
                    }
                    break;
                case SDL_VIDEORESIZE:
                    //SDL_VIDEORESIZE and SDL_ACTIVEEVENT fire at the same time,
                    //but we want to process SDL_ACTIVEEVENT first, to prevent
                    //reinitializing video on a minimized window
                    queuedVideoResize = true;
                    newVideoSize = Vector2i(event.resize.w, event.resize.h);
                    break;
                case SDL_ACTIVEEVENT:
                    bool gain = !!event.active.gain;
                    auto state = event.active.state;
                    if (state & SDL_APPINPUTFOCUS) {
                        if (gain != mInputFocus) {
                            mInputFocus = gain;
                            gFramework.driver_doFocusChange(mInputFocus);
                            update_sdl_mouse_state();
                        }
                    }
                    if (state & SDL_APPACTIVE) {
                        //gain tells if the window is visible (even if fully
                        //  obscured by other windows) or iconified; on Linux,
                        //  it also seems to tell if the window on a visible
                        //  desktop
                        //=> should pause the game and stop redrawing
                        //uh, but how (at least event loop will still eat CPU)
                        if (gain != mWindowVisible) {
                            mWindowVisible = gain;
                            gFramework.driver_doVisibilityChange(gain);
                        }
                    }
                    break;
                // exit if SDLK or the window close button are pressed
                case SDL_QUIT:
                    gFramework.driver_doTerminate();
                    break;
                default:
            }
        }
        if (queuedVideoResize) {
            queuedVideoResize = false;
            //xxx this works for graphics, but totally messes up mouse
            //    input (atleast on Windows)
            //if (mWindowVisible)
            gFramework.setVideoMode(newVideoSize);
        }
    }

    void sleepTime(Time t) {
        SDL_Delay(t.msecs);
    }

    int releaseCaches() {
        return 0;
    }

    //this is the SDL_image dependency
    Surface loadImage(Stream source, Transparency transparency) {
        SDL_RWops* ops = rwopsFromStream(source);
        SDL_Surface* surf = IMG_Load_RW(ops, 0);
        if (!surf) {
            auto err = fromStringz(IMG_GetError());
            throw new FrameworkException("image couldn't be loaded: " ~ err);
        }

        return convertFromSDLSurface(surf, transparency, true);
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

        /+
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
        +/

        return desc;
    }
}

static this() {
    registerFrameworkDriver!(SDLDriver)(cDrvName);
    addSetting!(char[])(cDrvName ~ ".window_pos", "center");
}
