module framework.framework;

//dependency hack
public import framework.enums;

public import framework.drawing;
public import framework.event;
public import framework.keybindings;
public import framework.sound;
public import utils.color;
public import utils.rect2;
public import utils.vector2;

import framework.filesystem;
import framework.font;
import framework.resources;
import config = utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.output;
import utils.path;
import utils.perf;
import utils.time;
import utils.weaklist;

import conv = std.conv;
import std.stream;
import str = std.string;

debug import std.stdio;

//**** driver stuff


///actual surface stored/managed in a driver specific way
///i.e. SDL_Surface for SDL, a texture in OpenGL...
///manually memory managment by the Framework and the Driver
abstract class DriverSurface {
    ///make sure the pixeldata is in SurfaceData.data
    ///(a driver might steal it before)
    abstract void getPixelData();
    ///update pixels again; it is unspecified if changes to the pixel data will
    ///be reflected immediately or only after this function is called
    abstract void updatePixels(in Rect2i rc);

    //useful debugging infos lol
    abstract void getInfos(out char[] desc, out uint extra_data);
}

//needed for texture versus bitmap under SDL's OpenGL
enum SurfaceMode {
    ERROR,
    //normal SDL or OpenGL textures
    NORMAL,
    //only normal SDL_Surfaces (including the screen, ironically)
    OFFSCREEN,
}

abstract class FrameworkDriver {
    ///create a driver surface from this data... the driver might modify the
    ///struct pointed to by data at any time
    abstract DriverSurface createSurface(SurfaceData* data, SurfaceMode mode);
    ///destroy the surface (leaves this instance back unuseable) and possibly
    ///write back surface data (also set surface to null)
    abstract void killSurface(inout DriverSurface surface);

    ///start/stop rendering on screen
    abstract Canvas startScreenRendering();
    abstract void stopScreenRendering();

    ///start rendering on a Surface
    abstract Canvas startOffscreenRendering(Surface surface);

    abstract Surface loadImage(Stream source, Transparency transparency);

    ///release internal caches - does not include DriverSurfaces
    abstract int releaseCaches();

    abstract void processInput();

    abstract DriverInputState getInputState();
    abstract void setInputState(in DriverInputState state);
    abstract void setMousePos(Vector2i p);

    ///give the driver more control about this
    ///don't ask... was carefully translated from old code
    abstract bool getModifierState(Modifier mod, bool whatithink);

    abstract VideoWindowState getVideoWindowState();
    ///returns success (for switching the video mode, only)
    abstract bool setVideoWindowState(in VideoWindowState state);

    ///sleep for a specific time (grr, Phobos doesn't provide this)
    abstract void sleepTime(Time relative);

    abstract FontDriver fontDriver();

    ///for debugging
    abstract char[] getDriverInfo();

    ///deinit driver
    abstract void destroy();
}

struct DriverInputState {
    bool mouse_visible = true;
    bool grab_input;
}

struct VideoWindowState {
    bool video_active;
    ///sizes for windowed mode/fullscreen
    Vector2i window_size, fs_size;
    int bitdepth;
    bool fullscreen;
    char[] window_caption;
}

//all surface data - shared between Surface and DriverSurface
struct SurfaceData {
    //convert Surface to display format
    bool enable_cache = true;
    //if this is true, the driver won't steal the pixeldata
    //if it's false, DriverSurface could "steal" the pixel data (and free it)
    //    and pixel data can be also given back (i.e. when killing the surface)
    //can also be set by the DriverSurface (but only to true)
    bool keep_pixeldata;
    Vector2i size;
    Transparency transparency = Transparency.None;
    Color colorkey = cStdColorkey;
    //at least currently, the data always is in the format RGBA32
    //(mask: 0xAABBGGRR)
    ubyte[] data;
    //pitch for data
    uint pitch;
}

abstract class DriverFont {
    //w == int.max for unlimited text
    abstract Vector2i draw(Canvas canvas, Vector2i pos, int w, char[] text);
    abstract Vector2i textSize(char[] text, bool forceHeight);

    //useful debugging infos lol
    abstract char[] getInfos();
}

abstract class FontDriver {
    abstract DriverFont createFont(FontProperties props);
    abstract void destroyFont(inout DriverFont handle);
    //invalidates all fonts
    abstract int releaseCaches();
}

//**** the Framework

Framework gFramework;

const Color cStdColorkey = {r:1.0f, g:0.0f, b:1.0f, a:0.0f};

package {
    struct SurfaceKillData {
        //ok, this is a GC'ed pointer, but I assume it's OK, because this
        //pointer is guaranteed to be live by other references
        DriverSurface surface;

        void doFree() {
            if (surface) {
                gFramework.killDriverSurface(surface);
            }
        }
    }
    WeakList!(Surface, SurfaceKillData) gSurfaces;
}

/// a Surface
/// This is used by the user and this also can survive framework driver
/// reinitialization
/// NOTE: this class is used for garbage collection of surfaces (bad idea, but
///       we need it), so be careful with pointers to it
class Surface {
    private {
        DriverSurface mDriverSurface;
        SurfaceData* mData;
        SurfaceMode mMode;
    }

    //must be called by any constructor
    private void init(SurfaceData data, bool copy_data) {
        assert(!mDriverSurface);
        mData = new SurfaceData;
        *mData = data;
        if (copy_data) {
            mData.data = mData.data.dup;
        }
        mData.colorkey = mData.transparency == Transparency.Colorkey
            ? mData.colorkey : Color(0,0,0,0);
        gSurfaces.add(this);
    }

    this(SurfaceData data, bool copy_data = false) {
        init(data, copy_data);
    }

    ///kill driver's surface, probably copy data back
    final bool passivate() {
        if (mDriverSurface) {
            gFramework.killDriverSurface(mDriverSurface);
            mMode = SurfaceMode.ERROR;
            return true;
        }
        return false;
    }

    ///return and possibly create the driver's surface
    final DriverSurface getDriverSurface(SurfaceMode mode, bool create = true) {
        if (mode != mMode) {
            // :(
            passivate();
        }
        if (!mDriverSurface && create) {
            mMode = mode;
            mDriverSurface = gFramework.createDriverSurface(mData, mMode);
        }
        return mDriverSurface;
    }

    final Vector2i size() {
        return mData.size;
    }
    final Rect2i rect() {
        Rect2i rc;
        rc.p2 = mData.size;
        return rc;
    }

    private void doFree(bool finalizer) {
        SurfaceKillData k;
        k.surface = mDriverSurface;
        mDriverSurface = null;
        if (!finalizer) {
            //if not from finalizer, actually can call C functions
            //so free it now (and not later, by lazy freeing)
            k.doFree();
            k = k.init; //reset
        }
        gSurfaces.remove(this, finalizer, k);
    }

    ~this() {
        doFree(true);
    }

    /// to avoid memory leaks
    final void free() {
        doFree(false);
    }

    bool enableCaching() {
        return mData.enable_cache;
    }

    void enableCaching(bool s) {
        passivate();
        mData.enable_cache = s;
    }

    /// direct access to pixels (in RGBA32 format)
    /// must not call any other surface functions (except size(), colorkey() and
    /// transparency()) between this and unlockPixels()
    void lockPixelsRGBA32(out void* pixels, out uint pitch) {
        if (mDriverSurface) {
            mDriverSurface.getPixelData();
        }
        pixels = mData.data.ptr;
        pitch = mData.pitch;
    }
    /// must be called after done with lockPixelsRGBA32()
    /// "rc" is for the offset and size of the region to update
    void unlockPixels(in Rect2i rc) {
        assert(rc.isNormal());
        if (mDriverSurface  && rc.size.quad_length > 0) {
            mDriverSurface.updatePixels(rc);
        }
    }

    /// return colorkey or a 0-alpha black, depending from transparency mode
    final Color colorkey() {
        return mData.colorkey;
    }

    final Transparency transparency() {
        return mData.transparency;
    }

    final Surface clone() {
        passivate();
        return new Surface(*mData, true);
    }

    //special thingy needed for SDLFont
    void scaleAlpha(float scale) {
        passivate();
        ubyte nalpha = cast(ubyte)(scale * 255);
        if (nalpha == 255)
            return;
        for (int y = 0; y < mData.size.y; y++) {
            ubyte* ptr = mData.data.ptr;
            ptr += y*mData.pitch;
            for (int x = 0; x < mData.size.x; x++) {
                uint alpha = ptr[3];
                alpha = (alpha*nalpha)/255;
                ptr[3] = cast(ubyte)(alpha);
                ptr += 4;
            }
        }
    }

    ///works like Canvas.draw, but doesn't do any blending
    ///surfaces must have same transparency settings (=> same pixel format)
    ///xxx bitmap memory must not overlap
    void copyFrom(Surface source, Vector2i destPos, Vector2i sourcePos,
        Vector2i sourceSize)
    {
        //xxx and to avoid blending, I do it manually (Canvas would blend)
        //  some day, this will be a complete SDL clone (that was sarcasm)
        //also, renderer.d has sth. similar
        //SORRY for this implementation
        Rect2i dest = Rect2i(destPos, destPos + sourceSize);
        Rect2i src = Rect2i(sourcePos, sourcePos + sourceSize);
        dest.fitInsideB(rect());
        src.fitInsideB(source.rect());
        auto sz = dest.size.min(src.size);
        assert(sz.x >= 0 && sz.y >= 0);
        void* pdest; uint destpitch;
        void* psrc; uint srcpitch;
        lockPixelsRGBA32(pdest, destpitch);
        source.lockPixelsRGBA32(psrc, srcpitch);
        pdest += destpitch*dest.p1.y + dest.p1.x*uint.sizeof;
        psrc += srcpitch*src.p1.y + src.p1.x*uint.sizeof;
        for (int y = 0; y < sz.y; y++) {
            int adv = sz.x*uint.sizeof;
            pdest[0 .. adv] = psrc[0 .. adv];
            pdest += destpitch;
            psrc += srcpitch;
        }
        source.unlockPixels(Rect2i.init);
        unlockPixels(Rect2i(dest.p1, dest.p1 + sz));
    }

    //these were in Texture, and are useless now
    void clearCache() {
    }
    Surface getSurface() {
        return this;
    }
    Texture createTexture() {
        return this;
    }
}

//for "compatibility"
alias Surface Texture;

private const Time cFPSTimeSpan = timeSecs(1); //how often to recalc FPS

public alias int delegate() CacheReleaseDelegate;

/// For Framework.getInfoString()
/// Entries from Framework.getInfoStringNames() correspond to this
/// Each entry describes a piece of information which can be queried by calling
/// Framework.getInfoString().
enum InfoString {
    Driver,
    ResourceList,
}

class Framework {
    private {
        FrameworkDriver mDriver;
        DriverReload* mDriverReload;
        ConfigNode mLastWorkingDriver;

        bool mShouldTerminate;

        //holds the DriverSurfaces to prevent them being GC'ed
        //cf. i.e. createDriverSurface()
        bool[DriverSurface] mDriverSurfaces;

        //misc singletons, lol
        FontManager mFontManager;
        FileSystem mFilesystem;
        Log mLog;
        Log mLogConf;

        Time mFPSLastTime;
        uint mFPSFrameCount;
        float mFPSLastValue;
        //least time per frame; for fixed framerate (0 to disable)
        Time mTimePerFrame;
        Time mLastFrameTime;

        //contains keystate (key down/up) for each key; indexed by Keycode
        bool[] mKeyStateMap;

        //for mouse handling
        Vector2i mMousePos;
        Vector2i mStoredMousePos, mLockedMousePos, mMouseCorr;
        bool mLockMouse;
        int mFooLockCounter;

        //worthless statistics!
        PerfTimer[char[]] mTimers;

        CacheReleaseDelegate[] mCacheReleasers;
    }

    //what the shit
    Resources resources;

    this(char[] arg0, char[] appId, config.ConfigNode fwconfig) {
        mLog = registerLog("Fw");

        if (gFramework !is null) {
            throw new Exception("Framework is a singleton");
        }
        gFramework = this;

        gSurfaces = new typeof(gSurfaces);
        gFonts = new typeof(gFonts);

        mFilesystem = new FileSystem(arg0, appId);
        resources = new Resources();

        mKeyStateMap.length = Keycode.max - Keycode.min + 1;

        mFontManager = new FontManager();

        auto driver_config = new config.ConfigNode();
        driver_config["driver"] = "sdl";
        driver_config["open_gl"] = "true";
        driver_config["gl_debug_wireframe"] = "false";
        driver_config.mixinNode(fwconfig.getSubNode("driver"), true);
        replaceDriver(driver_config);
    }

    private void replaceDriver(config.ConfigNode driver) {
        char[] name = driver.getStringValue("driver");
        if (!FrameworkDriverFactory.exists(name)) {
            throw new Exception("doesn't exist: " ~ name);
        }
        //deinit old driver
        VideoWindowState vstate;
        DriverInputState istate;
        if (mDriver) {
            vstate = mDriver.getVideoWindowState();
            istate = mDriver.getInputState();
            killDriver();
        }
        //new driver
        mDriver = FrameworkDriverFactory.instantiate(name, this, driver);
        mDriver.setVideoWindowState(vstate);
        mDriver.setInputState(istate);
        mLog("reloaded driver");
    }

    struct DriverReload {
        ConfigNode ndriver;
    }

    void scheduleDriverReload(DriverReload r) {
        mDriverReload = new DriverReload;
        *mDriverReload = r;
    }

    private void checkDriverReload() {
        if (mDriverReload) {
            replaceDriver(mDriverReload.ndriver);
            mDriverReload = null;
        }
    }

    private void killDriver() {
        releaseCaches();
        mDriver.destroy();
        mDriver = null;
    }

    void deinitialize() {
        killDriver();
        // .free() all Surfaces and then do defered_free()?
    }

    /+package FrameworkDriver driver() {
        return mDriver;
    }+/

    package FontDriver fontDriver() {
        return mDriver.fontDriver();
    }

    //--- DriverSurface handling

    package DriverSurface createDriverSurface(SurfaceData* data, SurfaceMode
        mode)
    {
        DriverSurface res = mDriver.createSurface(data, mode);
        //expect a new instance
        assert(!(res in mDriverSurfaces));
        mDriverSurfaces[res] = true;
        return res;
    }

    //objects free'd through this must have been created by createDriverSurface
    package void killDriverSurface(inout DriverSurface surface) {
        if (!surface)
            return;
        assert(surface in mDriverSurfaces);
        mDriverSurfaces.remove(surface);
        mDriver.killSurface(surface);
        assert(!surface);
    }

    //--- Surface handling

    Surface createSurface(Vector2i size, Transparency transparency,
        Color colorkey = cStdColorkey)
    {
        SurfaceData data;
        data.size = size;
        data.pitch = size.x*4;
        data.data.length = data.size.y*data.pitch;
        data.transparency = transparency;
        data.colorkey = colorkey;
        return new Surface(data);
    }

    Surface loadImage(Stream st, Transparency transp) {
        return mDriver.loadImage(st, transp);
    }

    Surface loadImage(char[] path, Transparency t = Transparency.AutoDetect) {
        mLog("load image: %s", path);
        scope stream = fs.open(path, FileMode.In);
        auto image = loadImage(stream, t);
        return image;
    }

    //--- key stuff

    /// translate a Keycode to a OS independent key ID string
    /// return null for Keycode.KEY_INVALID
    char[] translateKeycodeToKeyID(Keycode code) {
        foreach (KeycodeToName item; g_keycode_to_name) {
            if (item.code == code) {
                return item.name;
            }
        }
        return null;
    }

    /// reverse operation of translateKeycodeToKeyID()
    Keycode translateKeyIDToKeycode(char[] keyid) {
        foreach (KeycodeToName item; g_keycode_to_name) {
            if (item.name == keyid) {
                return item.code;
            }
        }
        return Keycode.INVALID;
    }

    char[] modifierToString(Modifier mod) {
        switch (mod) {
            case Modifier.Alt: return "mod_alt";
            case Modifier.Control: return "mod_ctrl";
            case Modifier.Shift: return "mod_shift";
        }
    }

    bool stringToModifier(char[] str, out Modifier mod) {
        switch (str) {
            case "mod_alt": mod = Modifier.Alt; return true;
            case "mod_ctrl": mod = Modifier.Control; return true;
            case "mod_shift": mod = Modifier.Shift; return true;
            default:
        }
        return false;
    }

    char[] keyinfoToString(KeyInfo infos) {
        char[] res = str.format("key=%s ('%s') unicode='%s'", cast(int)infos.code,
            translateKeycodeToKeyID(infos.code), infos.unicode);

        //append all modifiers
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            if ((1<<mod) & infos.mods) {
                res ~= str.format(" [%s]", modifierToString(mod));
            }
        }

        return res;
    }

    private void updateKeyState(in KeyInfo infos, bool state) {
        assert(infos.code >= Keycode.min && infos.code <= Keycode.max);
        mKeyStateMap[infos.code - Keycode.min] = state;
    }

    /// Query if key is currently pressed down (true) or not (false)
    bool getKeyState(Keycode code) {
        assert(code >= Keycode.min && code <= Keycode.max);
        return mKeyStateMap[code - Keycode.min];
    }

    /// return if Modifier is applied
    public bool getModifierState(Modifier mod) {
        bool get() {
            switch (mod) {
                case Modifier.Alt:
                    return getKeyState(Keycode.RALT) || getKeyState(Keycode.LALT);
                case Modifier.Control:
                    return getKeyState(Keycode.RCTRL) || getKeyState(Keycode.LCTRL);
                case Modifier.Shift:
                    return getKeyState(Keycode.RSHIFT)
                        || getKeyState(Keycode.LSHIFT);
                default:
            }
            return false;
        }
        return mDriver.getModifierState(mod, get());
    }

    /// return true if all modifiers in the set are applied
    /// empty set applies always
    bool getModifierSetState(ModifierSet mods) {
        return (getModifierSet() & mods) == mods;
    }

    bool isModifierKey(Keycode c) {
        switch (c) {
            case Keycode.RALT, Keycode.RCTRL, Keycode.RSHIFT:
            case Keycode.LALT, Keycode.LCTRL, Keycode.LSHIFT:
                return true;
            default:
                return false;
        }
    }

    ModifierSet getModifierSet() {
        ModifierSet mods;
        for (uint n = Modifier.min; n <= Modifier.max; n++) {
            if (getModifierState(cast(Modifier)n))
                mods |= 1 << n;
        }
        return mods;
    }

    ///This will move the mouse cursor to screen center and keep it there
    ///It is probably a good idea to hide the cursor first, as it will still
    ///be moveable and generate events, but "snap" back to the locked position
    ///Events will show the mouse cursor standing at its locked position
    ///and only show relative motion
    void lockMouse() {
        if (!mLockMouse) {
            mLockedMousePos = screenSize()/2;
            mStoredMousePos = mousePos;
            mLockMouse = true;
            mousePos = mLockedMousePos;
            //mMouseCorr = mStoredMousePos - mLockedMousePos;
            mMouseCorr = Vector2i(0);
            //discard 3 events from now
            mFooLockCounter = 3;
        }
    }

    ///Remove the mouse lock and move the cursor back to where it was before
    void unlockMouse() {
        if (mLockMouse) {
            mousePos = mStoredMousePos;
            mLockMouse = false;
            mMouseCorr = Vector2i(0);
        }
    }

    void cursorVisible(bool v) {
        auto state = mDriver.getInputState();
        state.mouse_visible = v;
        mDriver.setInputState(state);
    }

    bool cursorVisible() {
        return mDriver.getInputState().mouse_visible;
    }

    Vector2i mousePos() {
        return mMousePos;
    }

    //looks like this didn't trigger an event in the old code either
    void mousePos(Vector2i newPos) {
        mDriver.setMousePos(newPos);
    }

    bool grabInput() {
        return mDriver.getInputState().grab_input;
    }

    void grabInput(bool grab) {
        auto state = mDriver.getInputState();
        state.grab_input = grab;
        mDriver.setInputState(state);
    }

    //--- driver input callbacks

    //xxx should be all package or so, but that doesn't work out
    //  sub packages can't access parent package package-declarations, wtf?

    //called from framework implementation... relies on key repeat
    void driver_doKeyDown(KeyInfo infos) {
        infos.type = KeyEventType.Down;

        bool was_down = getKeyState(infos.code);

        updateKeyState(infos, true);
        if (!was_down) {
            if (onKeyDown) {
                bool handle = onKeyDown(infos);
            }
        }

        if (onKeyPress != null) {
            infos.type = KeyEventType.Press;
            onKeyPress(infos);
        }
    }

    void driver_doKeyUp(in KeyInfo infos) {
        infos.type = KeyEventType.Up;

        updateKeyState(infos, false);

        //xxx: huh? shouldn't that be done by the OS' window manager?
        if (infos.code == Keycode.F4 && getModifierState(Modifier.Alt)) {
            doTerminate();
        }

        if (onKeyUp) {
            onKeyUp(infos);
        }
    }

    void driver_doUpdateMousePos(Vector2i pos) {
        if (mMousePos != pos) {
            MouseInfo infos;
            infos.pos = pos;
            infos.rel = pos - mMousePos;
            if (mLockMouse) {
                //xxx this hack throws away the first 3 relative motions
                //when in locked mode to fix SDL stupidness
                mFooLockCounter--;
                if (mFooLockCounter > 0)
                    infos.rel = Vector2i(0);
                else
                    mFooLockCounter = 0;
                //pretend mouse to be at stored position
                infos.pos = mStoredMousePos;
                //correct the last cursor position change made
                infos.rel += mMouseCorr;
                //correction has been used, reset
                mMouseCorr = Vector2i(0);
            }
            mMousePos = pos;
            if (onMouseMove != null) {
                onMouseMove(infos);
            }
            if (mLockMouse) {
                mousePos = mLockedMousePos;
                //save position change to subtract later, as this will
                //generate an event
                mMouseCorr += (pos-mLockedMousePos);
            }
        }
    }

    //--- font stuff

    /// load a font using the font manager
    Font getFont(char[] id) {
        return fontManager.loadFont(id);
    }

    FontManager fontManager() {
        return mFontManager;
    }

    //--- video mode

    void setVideoMode(Vector2i size, int bpp, bool fullscreen) {
        VideoWindowState state = mDriver.getVideoWindowState();
        if (fullscreen) {
            state.fs_size = size;
        } else {
            state.window_size = size;
        }
        if (bpp >= 0) {
            state.bitdepth = bpp;
        }
        state.fullscreen = fullscreen;
        state.video_active = true;
        mDriver.setVideoWindowState(state);
    }

    //version for default arguments
    void setVideoMode(Vector2i size, int bpp = -1) {
        setVideoMode(size, bpp, fullScreen());
    }

    bool videoActive() {
        return mDriver.getVideoWindowState().video_active;
    }

    bool fullScreen() {
        return mDriver.getVideoWindowState().fullscreen;
    }

/+
    void fullScreen(bool s) {
        VideoWindowState state = mDriver.getVideoWindowState();
        state.fullscreen = s;
        mDriver.setVideoWindowState(state);
    }
+/

    Vector2i screenSize() {
        VideoWindowState state = mDriver.getVideoWindowState();
        return state.fullscreen ? state.fs_size : state.window_size;
    }

    //--- time stuff

    Time lastFrameTime() {
        return mLastFrameTime;
    }

    /// return number of invocations of onFrame pro second
    float FPS() {
        return mFPSLastValue;
    }

    /// set a fixed framerate / a maximum framerate
    /// fps = framerate, or 0 to disable fixed framerate
    void fixedFramerate(int fps) {
        if (fps == 0) {
            mTimePerFrame = timeMsecs(0);
        } else {
            mTimePerFrame = timeMsecs(1000/fps);
        }
    }

    //--- main loop

    /// Main-Loop
    void run() {
        while(!mShouldTerminate) {
            // recalc FPS value
            Time curtime = timeCurrentTime();
            if (curtime >= mFPSLastTime + cFPSTimeSpan) {
                mFPSLastValue = (cast(float)mFPSFrameCount
                    / (curtime - mFPSLastTime).msecs) * 1000.0f;
                mFPSLastTime = curtime;
                mFPSFrameCount = 0;
            }

            //xxx: whereever this should be?
            checkDriverReload();

            //mInputTime.start();
            mDriver.processInput();
            //mInputTime.stop();

            if (onUpdate) {
                onUpdate();
            }

            Canvas c = mDriver.startScreenRendering();
            if (onFrame) {
                onFrame(c);
            }
            mDriver.stopScreenRendering();
            c = null;

            // defered free (GC related, sucky Phobos forces this to us)
            defered_free();

            //wait for fixed framerate?
            Time time = timeCurrentTime();
            Time diff = mTimePerFrame - (time - curtime);
            //even if you don't wait, yield the rest of the timeslice
            diff = diff > timeSecs(0) ? diff : timeSecs(0);
            mDriver.sleepTime(diff);

            //real frame time
            Time cur = timeCurrentTime();
            mLastFrameTime = cur - curtime;

            //it's a hack!
            //used by toplevel.d
            if (onFrameEnd)
                onFrameEnd();

            mFPSFrameCount++;
        }

        //make sure to release the grab
        //at least stupid X11 keeps the grab when the program ends
        grabInput = false;
    }

    private bool doTerminate() {
        bool term = true;
        if (onTerminate != null) {
            term = onTerminate();
        }
        if (term) {
            terminate();
        }
        return term;
    }

    /// requests main loop to terminate
    void terminate() {
        mShouldTerminate = true;
    }

    //--- misc

    void setCaption(char[] caption) {
        VideoWindowState state = mDriver.getVideoWindowState();
        state.window_caption = caption;
        mDriver.setVideoWindowState(state);
    }

    final FileSystem fs() {
        return mFilesystem;
    }

    /+final Resources resources() {
        return mResources;
    }+/

    config.ConfigNode loadConfig(char[] section, bool asfilename = false,
        bool allowFail = false)
    {
        VFSPath file = VFSPath(section ~ (asfilename ? "" : ".conf"));
        mLog("load config: %s", file);
        //try {
            scope s = fs.open(file);
            auto f = new config.ConfigFile(s, file.get(), &logconf);
            if (!f.rootnode)
                throw new Exception("?");
            return f.rootnode;
        //} catch (Exception e) {
        //    if (!allowFail)
        //        throw e;
       // }
        mLog("config file %s failed to load (allowFail = true)", file);
        return null;
    }

    private void logconf(char[] log) {
        if (!mLogConf) {
            mLogConf = registerLog("configfile");
            assert(mLogConf !is null);
        }
        mLogConf("%s", log);
    }

    PerfTimer[char[]] timers() {
        return mTimers;
    }

    //kill all driver surfaces
    private int releaseDriverSurfaces() {
        int count;
        foreach (Surface s; gSurfaces.list) {
            if (s.passivate())
                count++;
        }
        return count;
    }

    private int releaseDriverFonts() {
        int count;
        foreach (Font f; gFonts.list) {
            if (f.unload())
                count++;
        }
        return count;
    }

    int releaseCaches() {
        int count;
        foreach (r; mCacheReleasers) {
            count += r();
        }
        count += mDriver.releaseCaches();
        count += releaseDriverFonts();
        count += releaseDriverSurfaces();
        return count;
    }

    void registerCacheReleaser(CacheReleaseDelegate callback) {
        mCacheReleasers ~= callback;
    }

    void defered_free() {
        gFonts.cleanup((FontKillData d) { d.doFree(); });
        gSurfaces.cleanup((SurfaceKillData d) { d.doFree(); });
    }

    void driver_doVideoInit() {
        if (onVideoInit) {
            onVideoInit(false); //xxx: argument
        }
    }

    void driver_doTerminate() {
        bool term = true;
        if (onTerminate != null) {
            term = onTerminate();
        }
        if (term) {
            terminate();
        }
    }

    Canvas startOffscreenRendering(Surface surface) {
        return mDriver.startOffscreenRendering(surface);
    }

    /// Get a string for a specific entry (see InfoString).
    /// Overridden by the framework implementation.
    /// Since it can have more than one line, it's always terminated with \n
    char[] getInfoString(InfoString inf) {
        char[] res;
        switch (inf) {
            case InfoString.Driver: {
                res = mDriver.getDriverInfo();
                break;
            }
            case InfoString.ResourceList: {
                int cnt, bytes, bytes_extra;
                res ~= "Surfaces:\n";
                foreach (s; gSurfaces.list) {
                    auto d = s.mDriverSurface;
                    char[] dr_desc;
                    if (d) {
                        uint extra;
                        d.getInfos(dr_desc, extra);
                        bytes_extra += extra;
                    }
                    bytes += s.mData.data.length;
                    res ~= format("  %s [%s]\n", s.size, dr_desc);
                    cnt++;
                }
                res ~= format("%d surfaces, size=%s, driver_extra=%s\n", cnt,
                    sizeToHuman(bytes), sizeToHuman(bytes_extra));
                cnt = 0;
                res ~= "Fonts:\n";
                foreach (f; gFonts.list) {
                    auto d = f.mFont;
                    res ~= format("  %s/%s [%s]\n", f.properties.face,
                        f.properties.size, d ? d.getInfos() : "");
                    cnt++;
                }
                res ~= format("%d fonts\n", cnt);
                break;
            }
            default:
                res = "?\n";
        }
        return res;
    }

    /// Return valid InfoString entry numbers and their name (see InfoString).
    InfoString[char[]] getInfoStringNames() {
        return [cast(char[])"driver": InfoString.Driver,
                "resource_list": InfoString.ResourceList];
    }

    int weakObjectsCount() {
        return gSurfaces.countRefs() + gFonts.countRefs();
    }

    //--- events

    /// executed when receiving quit event from framework
    /// return false to abort quit
    public bool delegate() onTerminate;
    /// Event raised every frame before drawing starts#
    /// Input processing and time advance should happen here
    public void delegate() onUpdate;
    /// Event raised when the screen is repainted
    public void delegate(Canvas canvas) onFrame;
    /// Event raised on key-down/up events; these events are not auto repeated
    //return false if keys were handled (for onKeyDown: onKeyPress handling)
    public bool delegate(KeyInfo key) onKeyDown;
    public bool delegate(KeyInfo key) onKeyUp;
    /// Event raised on key-down; this event is auto repeated
    public void delegate(KeyInfo key) onKeyPress;
    /// Event raised when the mouse pointer is changed
    /// Note that mouse button are managed by the onKey* events
    public void delegate(MouseInfo mouse) onMouseMove;
    /// Event raised on initialization (before first onFrame) and when the
    /// screen size or format changes.
    public void delegate(bool depth_only) onVideoInit;

    /// Called after all work for a frame is done
    public void delegate() onFrameEnd;
}

class FrameworkDriverFactory : StaticFactory!(FrameworkDriver, Framework,
    ConfigNode)
{
}

