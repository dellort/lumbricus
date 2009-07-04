module framework.framework;

//dependency hack
public import framework.enums;

public import framework.drawing;
public import framework.event;
public import framework.keybindings;
public import framework.sound;
public import framework.font;
public import framework.filesystem;
public import utils.color;
public import utils.rect2;
public import utils.vector2;

import utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.output;
import utils.path;
import utils.perf;
import utils.time;
import utils.weaklist;
import utils.gzip;

import utils.stream;

import str = utils.string;

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

enum DriverFeatures {
    canvasScaling = 1,
    //basically, if a 3D engine is available
    transformedQuads = 2,
    //if the OpenGL API is used / OpenGL calls can be done by the user
    usingOpenGL = 4,
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

    abstract Surface loadImage(Stream source, Transparency transparency);

    abstract Surface screenshot();

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
    ///returns desktop video resolution at program start
    abstract Vector2i getDesktopResolution();

    ///sleep for a specific time (grr, Phobos doesn't provide this)
    abstract void sleepTime(Time relative);

    ///for debugging
    abstract char[] getDriverInfo();

    ///return an or'ed combination of optional DriverFeatures
    ///this driver supports
    abstract int getFeatures();

    ///deinit driver
    abstract void destroy();
}

struct DriverInputState {
    bool mouse_visible = true;
    bool grab_input;
    bool mouse_locked;
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
    //bool keep_pixeldata; unused
    Vector2i size;
    //NOTE: the transparency is merely a hint to the backend (if the hint is
    //      wrong, the backend might output a corrupted image); also see below
    Transparency transparency = Transparency.Alpha;
    //NOTE: the colorkey might not be used at all anymore
    //      for now, it is only a hint for backends (rendering and image
    //      saving), that this color is unused by the actual image and can be
    //      used as actual colorkey to implement transparency
    //Warning: the actual transparency of a pixel in the pixel data is
    //      determined by the function pixelIsTransparent()
    //the colorkey is only valid
    Color colorkey = Color(1,0,1,0);
    //at least currently, the data always is in the format Color.RGBA32
    //if the transparency is colorkey, not-transparent pixels may be changed by
    //the backend (xxx: this is horrible)
    Color.RGBA32[] data;
    //pitch for data
    uint pitch;
}

//this function by definition returns if a pixel is considered transparent
//dear compiler, you should always inline this
bool pixelIsTransparent(Color.RGBA32* p) {
    return p.a == 0;
}

//**** the Framework

Framework gFramework;

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

//base class for framework errors
class FrameworkException : Exception {
    this(char[] msg) {
        super(msg);
    }
}

//enum ImageFormat {
//    tga,    //lol, no more supported
//    png,
//}

//NOTE: stream must be seekable (used to back-patch the length), but the
//      functions still start writing at the preset seek position, and ends
//      writing at the end of the written image
alias void delegate(Surface img, Stream dst) ImageLoadDelegate;
ImageLoadDelegate[char[]] gImageFormats;

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

    ///"best" size for a large texture
    const cStdSize = Vector2i(512, 512);

    this(SurfaceData data, bool copy_data = false) {
        mData = new SurfaceData;
        *mData = data;
        if (copy_data) {
            mData.data = mData.data.dup;
        }
        gSurfaces.add(this);
        readSurfaceProperties();
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

    //call everytime the format in mData is changed
    private void readSurfaceProperties() {
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
    /// free_data = free even the surface struct and the pixel array
    ///     (use with care)
    final void free(bool free_data = false) {
        doFree(false);
        if (free_data) {
            delete mData.data;
            delete mData;
        }
        mData = null;
    }

    /// this has no effect in OpenGL mode; in SDL mode, enabled caching might
    /// speed up blitting, but uses more memory, and updating pixels is S.L.O.W.
    bool enableCaching() {
        return mData.enable_cache;
    }
    void enableCaching(bool s) {
        if (mData.enable_cache == s)
            return;
        passivate();
        mData.enable_cache = s;
    }

    /// direct access to pixels (in Color.RGBA32 format)
    /// must not call any other surface functions (except size() and
    /// transparency()) between this and unlockPixels()
    /// pitch is now number of Color.RGBA32 units to advance by 1 line vetically
    void lockPixelsRGBA32(out Color.RGBA32* pixels, out uint pitch) {
        if (mDriverSurface) {
            mDriverSurface.getPixelData();
        }
        pixels = mData.data.ptr;
        pitch = mData.pitch;
    }
    /// must be called after done with lockPixelsRGBA32()
    /// "rc" is for the offset and size of the region to update
    void unlockPixels(in Rect2i rc) {
        if (!rc.isNormal()) //now means it is empty
            return;
        if (mDriverSurface  && rc.size.quad_length > 0) {
            mDriverSurface.updatePixels(rc);
        }
    }

    /// return colorkey or a 0-alpha black, depending from transparency mode
    final Color getColorkey() {
        return mData.colorkey;
    }

    final Transparency transparency() {
        return mData.transparency;
    }

    static bool isTransparent(void* raw) {
        return pixelIsTransparent(cast(Color.RGBA32*)raw);
    }

    final Surface clone() {
        return subrect(rect());
        /*
        passivate();
        return new Surface(*mData, true);
        */
    }

    //return a Surface with a copy of a subrectangle of this
    final Surface subrect(Rect2i rc) {
        rc.fitInsideB(rect());
        if (!rc.isNormal()) {
            //completely outside, simply create a 0-sized surface
            //xxx don't know if SDL or OpenGL are ok with this
            rc = Rect2i.init;
        }
        auto sz = rc.size();
        auto s = gFramework.createSurface(sz, transparency, getColorkey());
        s.copyFrom(this, Vector2i(0), rc.p1, sz);
        return s;
    }

    //special thingy needed for SDLFont
    void scaleAlpha(float scale) {
        mapColorChannels((Color c) {
            c.a *= scale;
            return c;
        });
    }

    //see Color.applyBCG()
    void applyBCG(float brightness, float contrast, float gamma) {
        mapColorChannels((Color c) {
            return c.applyBCG(brightness, contrast, gamma);
        });
    }

    ///for each pixel (and color channel) change the color to fn(original_color)
    ///because really doing that for each Color would be too slow, this is only
    ///done per channel (fn() is used to contruct the lookup table)
    void mapColorChannels(Color delegate(Color c) fn) {
        ubyte[256][4] map;
        for (int n = 0; n < 256; n++) {
            Color c;
            c.r = c.g = c.b = c.a = Color.fromByte(n);
            c = fn(c);
            c.clamp();
            Color.RGBA32 c32 = c.toRGBA32();
            map[0][n] = c32.r;
            map[1][n] = c32.g;
            map[2][n] = c32.b;
            map[3][n] = c32.a;
        }
        mapColorChannels(map);
    }

    //change each colorchannel according to colormap
    //channels are r=0, g=1, b=2, a=3
    //xxx is awfully slow and handling of transparency is fundamentally broken
    void mapColorChannels(ubyte[256][4] colormap) {
        Color.RGBA32* data; uint pitch;
        lockPixelsRGBA32(data, pitch);
        for (int y = 0; y < mData.size.y; y++) {
            Color.RGBA32* ptr = data + y*pitch;
            auto w = mData.size.x;
            for (int x = 0; x < w; x++) {
                //if (!isTransparent(*cast(int*)ptr)) {
                    //avoiding bounds checking: array[index] => *(array.ptr + index)
                    ptr.r = *(colormap[0].ptr + ptr.r); //colormap[0][ptr.r];
                    ptr.g = *(colormap[1].ptr + ptr.g); //colormap[1][ptr.g];
                    ptr.b = *(colormap[2].ptr + ptr.b); //colormap[2][ptr.b];
                    ptr.a = *(colormap[3].ptr + ptr.a); //colormap[3][ptr.a];
                //}
                ptr++;
            }
        }
        unlockPixels(rect());
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
        if (!dest.isNormal() || !src.isNormal())
            return; //no overlap
        //check memory overlap
        debug if (source is this && dest.intersects(src))
            assert(false, "copyFrom(): overlapping memory");
        auto sz = dest.size.min(src.size);
        assert(sz.x >= 0 && sz.y >= 0);
        Color.RGBA32* pdest; uint destpitch;
        Color.RGBA32* psrc; uint srcpitch;
        lockPixelsRGBA32(pdest, destpitch);
        source.lockPixelsRGBA32(psrc, srcpitch);
        pdest += destpitch*dest.p1.y + dest.p1.x;
        psrc += srcpitch*src.p1.y + src.p1.x;
        int adv = sz.x;
        for (int y = 0; y < sz.y; y++) {
            pdest[0 .. adv] = psrc[0 .. adv];
            pdest += destpitch;
            psrc += srcpitch;
        }
        source.unlockPixels(Rect2i.init);
        unlockPixels(Rect2i(dest.p1, dest.p1 + sz));
    }

    ///yay finally
    ///blit a solid color, non-blending and copying
    void fill(Rect2i rc, Color color) {
        rc.fitInsideB(Rect2i(size));
        if (!rc.isNormal())
            return;
        auto c = color.toRGBA32();
        Color.RGBA32* px; uint pitch;
        lockPixelsRGBA32(px, pitch);
        for (int y = rc.p1.y; y < rc.p2.y; y++) {
            auto dest = px + pitch*y;
            dest[rc.p1.x .. rc.p2.x] = c;
        }
        unlockPixels(rc);
    }

    //fmt is one of the formats registered in gImageFormats
    //import imgwrite.d to register "png", "tga" and "raw"
    void saveImage(Stream stream, char[] fmt = "png") {
        if (auto pfmt = fmt in gImageFormats) {
            (*pfmt)(this, stream);
        } else {
            assert(false, "Not implemented: "~fmt);
        }
    }
}

//for "compatibility"
alias Surface Texture;

private const Time cFPSTimeSpan = timeSecs(1); //how often to recalc FPS

public alias int delegate() CacheReleaseDelegate;

///what mouse cursor to display
struct MouseCursor {
    bool visible = true;
    //custom mouse cursor graphic
    //if this is null, the standard cursor is displayed
    Surface graphic;
    //offset to "click point" for custom cursor
    Vector2i graphic_spot;

    const None = MouseCursor(false);
    const Standard = MouseCursor();
}

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
        Sound mSound;
        Log mLog;

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
        MouseCursor mMouseCursor;

        //worthless statistics!
        PerfTimer[char[]] mTimers;

        CacheReleaseDelegate[] mCacheReleasers;

        FontDriver mFontDriver;
    }

    this(ConfigNode fwconfig) {
        mLog = registerLog("Fw");

        if (gFramework !is null) {
            throw new FrameworkException("Framework is a singleton");
        }
        gFramework = this;

        gSurfaces = new typeof(gSurfaces);
        gFonts = new typeof(gFonts);
        gSounds = new typeof(gSounds);

        mKeyStateMap.length = Keycode.max - Keycode.min + 1;

        mFontManager = new FontManager();
        mSound = new Sound();

        replaceDriver(fwconfig);
    }

    private void replaceDriver(ConfigNode config) {
        ConfigNode drivers = config.getSubNode("drivers");
        if (!FrameworkDriverFactory.exists(drivers["base"])) {
            throw new FrameworkException("Base driver doesn't exist: "
                ~ drivers["base"]);
        }
        if (!FontDriverFactory.exists(drivers["font"])) {
            throw new FrameworkException("Font driver doesn't exist: "
                ~ drivers["font"]);
        }
        if (!SoundDriverFactory.exists(drivers["sound"])) {
            throw new FrameworkException("Sound driver doesn't exist: "
                ~ drivers["sound"]);
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
        mDriver = FrameworkDriverFactory.instantiate(drivers["base"], this,
            config.getSubNode(drivers["base"]));
        //init font driver
        mFontDriver = FontDriverFactory.instantiate(drivers["font"], mFontManager,
            config.getSubNode(drivers["font"]));
        //init sound
        mSound.reinit(SoundDriverFactory.instantiate(drivers["sound"], mSound,
            config.getSubNode(drivers["sound"])));

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
        //xxx: does this do anything that could not be done
        //     during cache release?
        mSound.beforeKill();
        releaseCaches(true);
        assert(mDriverSurfaces.length == 0);

        mSound.close();

        mFontDriver.destroy();
        mFontDriver = null;

        mDriver.destroy();
        mDriver = null;
    }

    void deinitialize() {
        killDriver();
        // .free() all Surfaces and then do defered_free()?
    }

    public FrameworkDriver driver() {
        return mDriver;
    }

    package FontDriver fontDriver() {
        return mFontDriver;
    }

    int driverFeatures() {
        return mDriver.getFeatures();
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
        Color colorkey = Color(0))
    {
        SurfaceData data;
        data.size = size;
        data.pitch = size.x;
        data.data.length = data.size.y*data.pitch;
        data.transparency = transparency;
        data.colorkey = colorkey;
        return new Surface(data);
    }

    Surface loadImage(Stream st, Transparency t = Transparency.AutoDetect) {
        return mDriver.loadImage(st, t);
    }

    Surface loadImage(char[] path, Transparency t = Transparency.AutoDetect) {
        mLog("load image: {}", path);
        scope stream = gFS.open(path, File.ReadExisting);
        scope(exit) stream.close();
        auto image = loadImage(stream, t);
        return image;
    }

    ///create a copy of the screen contents
    Surface screenshot() {
        return mDriver.screenshot();
    }

    //--- key stuff

    private void updateKeyState(in KeyInfo infos, bool state) {
        assert(infos.code >= Keycode.min && infos.code <= Keycode.max);
        mKeyStateMap[infos.code - Keycode.min] = state;
    }

    /// Query if key is currently pressed down (true) or not (false)
    final bool getKeyState(Keycode code) {
        assert(code >= Keycode.min && code <= Keycode.max);
        return mKeyStateMap[code - Keycode.min];
    }

    /// query if any of the checked set of keys is currently down
    ///     keyboard = check normal keyboard keys
    ///     mouse = check mouse buttons
    bool anyButtonPressed(bool keyboard = true, bool mouse = true) {
        for (auto n = Keycode.min; n <= Keycode.max; n++) {
            auto ismouse = keycodeIsMouseButton(n);
            if (!(ismouse ? mouse : keyboard))
                continue;
            if (getKeyState(n))
                return true;
        }
        return false;
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
    ///Events and mousePos() will show the mouse cursor standing at its locked
    ///position and only show relative motion
    void mouseLocked(bool set) {
        auto state = mDriver.getInputState();
        state.mouse_locked = set;
        mDriver.setInputState(state);
    }
    bool mouseLocked() {
        return mDriver.getInputState().mouse_locked;
    }

    ///appaerance of the mouse pointer when it is inside the video window
    void mouseCursor(MouseCursor cursor) {
        mMouseCursor = cursor;

        //hide/show hardware mouse cursor (the one managed by SDL)
        auto state = mDriver.getInputState();
        bool vis = mMouseCursor.visible && !mMouseCursor.graphic;
        if (state.mouse_visible != vis) {
            state.mouse_visible = vis;
            mDriver.setInputState(state);
        }
    }
    MouseCursor mouseCursor() {
        return mMouseCursor;
    }

    private void drawSoftCursor(Canvas c) {
        if (!mMouseCursor.visible || !mMouseCursor.graphic)
            return;
        c.draw(mMouseCursor.graphic, mousePos() - mMouseCursor.graphic_spot);
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

        if (!onInput)
            return;

        InputEvent event;
        event.keyEvent = infos;
        event.isKeyEvent = true;
        event.mousePos = mousePos();

        if (!was_down) {
            onInput(event);
        }
        event.keyEvent.type = KeyEventType.Press;
        onInput(event);
    }

    void driver_doKeyUp(in KeyInfo infos) {
        infos.type = KeyEventType.Up;

        updateKeyState(infos, false);

        //xxx: huh? shouldn't that be done by the OS' window manager?
        if (infos.code == Keycode.F4 && getModifierState(Modifier.Alt)) {
            doTerminate();
        }

        if (!onInput)
            return;

        InputEvent event;
        event.keyEvent = infos;
        event.isKeyEvent = true;
        event.mousePos = mousePos();

        onInput(event);
    }

    //rel is the relative movement; needed for locked mouse mode
    void driver_doUpdateMousePos(Vector2i pos, Vector2i rel) {
        if (mMousePos == pos && rel == Vector2i(0))
            return;

        mMousePos = pos;

        if (onInput) {
            InputEvent event;
            event.isMouseEvent = true;
            event.mousePos = event.mouseEvent.pos = mMousePos;
            event.mouseEvent.rel = rel;
            onInput(event);
        }
    }

    //--- font stuff, sound

    /// load a font using the font manager
    Font getFont(char[] id) {
        return fontManager.loadFont(id);
    }

    FontManager fontManager() {
        return mFontManager;
    }

    Sound sound() {
        return mSound;
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

/*
    void fullScreen(bool s) {
        VideoWindowState state = mDriver.getVideoWindowState();
        state.fullscreen = s;
        mDriver.setVideoWindowState(state);
    }
*/

    Vector2i screenSize() {
        VideoWindowState state = mDriver.getVideoWindowState();
        return state.fullscreen ? state.fs_size : state.window_size;
    }

    ///desktop screen resolution at program start
    Vector2i desktopResolution() {
        return mDriver.getDesktopResolution();
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
            mTimePerFrame = Time.Null;
        } else {
            mTimePerFrame = timeMusecs(1000000/fps);
        }
    }

    //--- main loop

    /// Main-Loop
    void run() {
        Time waitTime;
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

            //and where should this be???
            mSound.tick();

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
            drawSoftCursor(c);
            mDriver.stopScreenRendering();
            c = null;

            // defered free (GC related, sucky Phobos forces this to us)
            defered_free();

            //wait for fixed framerate?
            Time time = timeCurrentTime();
            //target waiting time
            waitTime += mTimePerFrame - (time - curtime);
            //even if you don't wait, yield the rest of the timeslice
            waitTime = waitTime > Time.Null ? waitTime : Time.Null;
            mDriver.sleepTime(waitTime);

            //real frame time
            Time cur = timeCurrentTime();
            //subtract the time that was really waited, to cover the
            //inaccuracy of Driver.sleepTime()
            waitTime -= (cur - time);
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

    private int releaseDriverSounds(bool force) {
        int count;
        foreach (SoundBase s; gSounds.list) {
            if (s.release(force))
                count++;
        }
        return count;
    }

    //force: for sounds; if true, sounds are released too, but this leads to
    //a hearable interruption
    int releaseCaches(bool force) {
        int count;
        foreach (r; mCacheReleasers) {
            count += r();
        }
        count += mDriver.releaseCaches();
        count += mFontDriver.releaseCaches();
        count += releaseDriverFonts();
        count += releaseDriverSurfaces();
        count += releaseDriverSounds(force);
        return count;
    }

    void registerCacheReleaser(CacheReleaseDelegate callback) {
        mCacheReleasers ~= callback;
    }

    void defered_free() {
        gFonts.cleanup((FontKillData d) { d.doFree(); });
        gSurfaces.cleanup((SurfaceKillData d) { d.doFree(); });
        gSounds.cleanup((SoundKillData d) { d.doFree(); });
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
                    res ~= myformat("  {} [{}]\n", s.size, dr_desc);
                    cnt++;
                }
                res ~= myformat("{} surfaces, size={}, driver_extra={}\n",
                    cnt, str.sizeToHuman(bytes), str.sizeToHuman(bytes_extra));
                cnt = 0;
                res ~= "Fonts:\n";
                foreach (f; gFonts.list) {
                    auto d = f.mFont;
                    res ~= myformat("  {}/{} [{}]\n", f.properties.face,
                        f.properties.size, d ? d.getInfos() : "");
                    cnt++;
                }
                res ~= myformat("{} fonts\n", cnt);
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
    /// Input events, see InputEvent
    public void delegate(InputEvent input) onInput;
    /// Event raised on initialization (before first onFrame) and when the
    /// screen size or format changes.
    public void delegate(bool depth_only) onVideoInit;

    /// Called after all work for a frame is done
    public void delegate() onFrameEnd;
}

alias StaticFactory!("Drivers", FrameworkDriver, Framework,
    ConfigNode) FrameworkDriverFactory;
