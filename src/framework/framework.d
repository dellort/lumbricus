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

import cstdlib = tango.stdc.stdlib;

//**** driver stuff


abstract class DrawDriver {
    abstract DriverSurface createSurface(SurfaceData data);

    abstract Canvas startScreenRendering();
    abstract void stopScreenRendering();

    abstract void initVideoMode(Vector2i screen_size);

    abstract Surface screenshot();

    abstract int getFeatures();

    abstract void destroy();

    int releaseCaches() {
        return 0;
    }
}

///actual surface stored/managed in a driver specific way
///i.e. SDL_Surface for SDL, a texture in OpenGL...
///manually memory managment by the Framework and the Driver
abstract class DriverSurface {
    ///make sure the pixeldata is in SurfaceData.data
    ///(a driver might steal it before)
    ///the OpenGL driver actually does this with version = StealSurfaceData;
    abstract void getPixelData();
    ///update pixels again; it is unspecified if changes to the pixel data will
    ///be reflected immediately or only after this function is called
    abstract void updatePixels(in Rect2i rc);
    ///notify about new SubSurface instance attached to this Surface
    ///if the driver doesn't care about SubSurface, this can be a no-op
    void newSubSurface(SubSurface ss) {
    }

    ///deallocate
    abstract void kill();

    //useful debugging infos lol
    abstract void getInfos(out char[] desc, out uint extra_data);
}


enum DriverFeatures {
    canvasScaling = 1,
    //basically, if a 3D engine is available
    transformedQuads = 2,
    //if the OpenGL API is used / OpenGL calls can be done by the user
    usingOpenGL = 4,
}

abstract class FrameworkDriver {
    ///flip screen after drawing
    abstract void flipScreen();

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
    ///returns desktop video resolution at program start
    abstract Vector2i getDesktopResolution();

    ///sleep for a specific time (grr, Phobos doesn't provide this)
    abstract void sleepTime(Time relative);

    ///for debugging
    abstract char[] getDriverInfo();

    ///deinit driver
    abstract void destroy();
}

struct DriverInputState {
    bool mouse_visible = true;
    bool mouse_locked;
}

version(Windows) {
    alias void* SysWinHandle;
} else {
    alias uint SysWinHandle;
}

struct VideoWindowState {
    bool video_active;
    ///sizes for windowed mode/fullscreen
    Vector2i window_size, fs_size;
    int bitdepth;
    bool fullscreen;
    char[] window_caption;
    SysWinHandle window_handle;

    Vector2i actualSize() {
        return fullscreen ? fs_size : window_size;
    }
}

//use C's malloc() for pixel data (D GC can't handle big sizes very well)
version = UseCMalloc;

//all surface data - shared between Surface and DriverSurface
//the point of this being an extra object is:
//1. driver surface don't always exist (because we want to support the useless
//   feature of being able to switch graphics drivers while the program is
//   running; e.g. switch from OpenGL mode to pure SDL mode)
//2. class Surface is garbage collected, and surfaces are automatically free'd
//   when a Surface is collected; but we still need the pointer to the surface
//   memory => we must move parts to an extra class, SurfaceData
//3. copying around a struct won't do it, because both Surface and driver
//   surfaces change the data
//this object is instantiated with a Surface, and free'd with a Surface
// -- looks like some stuff in SDL framework fucks with with too, oh damn!
//I guess this is package (+ sub packages) (so it has to be public)
final class SurfaceData {
    //convert Surface to display format and/or possibly allow stealing
    bool enable_cache = true;
    //meh
    bool data_locked;
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
    //if allocated, this is always !is null, even if size is (0,0)
    //it is null if uninitialized or if surface data has been stolen
    Color.RGBA32[] data;
    size_t pitch; //stale, don't use

    //I don't really know why this is here, but having it in Surface is annoying
    DriverSurface driver_surface;

    //indexed by SubSurface.index()
    SubSurface[] subsurfaces;

    //alloc/set data
    //size must be set before calling this
    void pixels_alloc() {
        assert(!data_locked);
        assert(data is null);
        assert(size.x >= 0 && size.y >= 0);

        size_t len = size.y*size.x;

        //make sure this special case doesn't piss off anybody
        //e.g. malloc(0) can return NULL or some unique pointer (it's undefined)
        if (len == 0) {
            len = 1;
        }

        version (UseCMalloc) {
            size_t csz = len*Color.RGBA32.sizeof;
            void* cptr = cstdlib.malloc(csz);
            //void* cptr = cstdlib.calloc(len, Color.RGBA32.sizeof);
            //xxx: what error to throw?
            if (!cptr)
                throw new Exception("can't allocate pixel memory");
            data = cast(Color.RGBA32[])cptr[0..csz];
        } else {
            data.length = len;
        }
        pitch = size.x;

        assert(data !is null);
    }

    //free data, but leave everything else intact
    void pixels_free() {
        assert(!data_locked);

        if (data is null)
            return;

        version (UseCMalloc) {
            cstdlib.free(data.ptr);
        } else {
            //would be safe, but "the GC will collect it anyway"
            //delete data;
        }

        data = null;
    }

    void lock() {
        assert(!data_locked);
        data_locked = true;
    }
    void unlock() {
        assert(data_locked);
        data_locked = false;
    }

    //for the graphics driver
    //return if pixel data can be "stolen", which means the surface data will
    //  be free'd and be stored in the backend instead (like an OpenGL texture)
    bool canSteal() {
        //data_locked=true is actually a user error?
        return !data_locked && enable_cache;
    }

    void kill_driver_surface() {
        if (driver_surface)
            gFramework.killDriverSurface(driver_surface);
        assert(data !is null);
    }

    ///return and possibly create the driver's surface
    DriverSurface get_driver_surface(bool create = true) {
        if (!driver_surface && create) {
            assert(data !is null);
            driver_surface = gFramework.createDriverSurface(this);
            assert(!!driver_surface);
        }
        return driver_surface;
    }

    void doMirrorY() {
        for (uint y = 0; y < size.y; y++) {
            Color.RGBA32* src = data.ptr+y*pitch+size.x;
            Color.RGBA32* dst = data.ptr+y*pitch;
            for (uint x = 0; x < size.x/2; x++) {
                src--;
                swap(*dst, *src);
                dst++;
            }
        }
    }

    void doMirrorX() {
        Color.RGBA32[] tmp = new Color.RGBA32[pitch];
        for (int y = 0; y < size.y/2; y++) {
            int ym = size.y - y - 1;
            tmp[] = data[y*pitch..(y+1)*pitch];
            data[y*pitch..(y+1)*pitch] =
                data[ym*pitch..(ym+1)*pitch];
            data[ym*pitch..(ym+1)*pitch] = tmp;
        }
        delete tmp;
    }
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
        //this data is held for a while in a region not scanned by the GC
        //(why??? I forgot)
        //but other references (at least gFramework.mSurfaceData) keep it alive
        SurfaceData data;

        //this is called from the framework's main loop, so there's not any
        //  GC/weakpointer weirdness
        void doFree() {
            if (data) {
                data.kill_driver_surface();
                data.pixels_free();
                assert(data in gFramework.mSurfaceData);
                gFramework.mSurfaceData.remove(data);
            }
            data = null;
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

//NOTE: stream must be seekable (used to back-patch the length), but the
//      functions still start writing at the preset seek position, and end
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
        SurfaceData mData;
    }

    ///"best" size for a large texture
    //just needed because OpenGL has an unknown max texture size
    //actually, it doesn't make sense at all
    const cStdSize = Vector2i(512, 512);

    this(Vector2i size, Transparency transparency, Color colorkey = Color(0)) {
        mData = new SurfaceData();

        mData.size = size;
        mData.transparency = transparency;
        mData.colorkey = colorkey;

        mData.pixels_alloc();

        readSurfaceProperties();

        gFramework.mSurfaceData[mData] = true; //don't GC-collect data
        gSurfaces.add(this);
    }

    //hackity hack
    final SurfaceData getData() {
        return mData;
    }

    ///kill driver's surface, probably copy data back
    final void passivate() {
        mData.kill_driver_surface();
    }

    ///return and possibly create the driver's surface
    final DriverSurface getDriverSurface(bool create = true) {
        return mData.get_driver_surface(create);
    }

    ///load surface into backend
    final void preload() {
        getDriverSurface(true);
    }

    //see SubSurface
    final SubSurface createSubSurface(Rect2i rc) {
        auto ss = new SubSurface();
        ss.mSurface = this;
        ss.mRect = rc;
        ss.mIndex = mData.subsurfaces.length;
        mData.subsurfaces ~= ss;
        //notify the driver of the new SubSurface entry
        if (auto drs = getDriverSurface(false)) {
            drs.newSubSurface(ss);
        }
        return ss;
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
        k.data = mData;
        if (!finalizer) {
            //if not from finalizer, actually can call C functions
            //so free it now (and not later, by lazy freeing)
            k.doFree();
            k = k.init; //reset
        }
        mData = null;
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
    }

    /// accessing pixels with lockPixelsRGBA32() will be S.L.O.W. (depending
    /// from the driver)
    /// if this is true (default value), then:
    /// - OpenGL: will steal data => even reading pixels is extremely slow
    /// - SDL: will convert surface to display format and will RLE compress
    ///   the image data, but reading is still fast (no stealing)
    /// after enabling caching, you can use preload() to do the driver specific
    /// surface conversion as mentioned above (or it will be done on next draw)
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
    /// why not just use size.x? I thought this would provide a simple way to
    ///     represent sub-surfaces (so that a Surface can reference a part of a
    ///     larger Surface), but maybe that idea is already dead...
    //xxx: add a "Rect2i area" parameter to return the pixels for a subrect?
    void lockPixelsRGBA32(out Color.RGBA32* pixels, out uint pitch) {
        if (mData.driver_surface) {
            mData.driver_surface.getPixelData();
        }
        mData.lock();
        assert(mData.data !is null);
        pixels = mData.data.ptr;
        pitch = mData.size.x;
    }
    /// must be called after done with lockPixelsRGBA32()
    /// "rc" is for the offset and size of the region to update
    void unlockPixels(in Rect2i rc) {
        mData.unlock();
        if (!rc.isNormal()) //now means it is empty
            return;
        if (mData.driver_surface && rc.size.quad_length > 0) {
            mData.driver_surface.updatePixels(rc);
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

//represents a sub rectangle of a Surface
//used to speed up drawing (HOPEFULLY)
final class SubSurface {
    private {
        int mIndex;
        Surface mSurface;
        Rect2i mRect;
    }

    //violating coding style for boring getters
    Surface surface() { return mSurface; }
    Vector2i origin() { return mRect.p1; }
    Vector2i size() { return mRect.size; }
    Rect2i rect() { return mRect; }

    //index into the corresponding Surface's SubSurface array
    //can be used by the framework driver to lokup driver specific stuff
    //(like a display list for the OpenGL driver)
    int index() {
        return mIndex;
    }

    void draw(Canvas c, Vector2i at) {
        c.drawFast(this, at);
    }
}

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
        DrawDriver mDrawDriver;
        DriverReload* mDriverReload;
        ConfigNode mLastWorkingDriver;

        bool mShouldTerminate;

        //holds the DriverSurfaces to prevent them being GC'ed
        //cf. i.e. createDriverSurface()
        bool[DriverSurface] mDriverSurfaces;
        //and this is something similar
        bool[SurfaceData] mSurfaceData;

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
        mSound = new Sound(fwconfig.getSubNode("sound"));

        replaceDriver(fwconfig);
    }

    private void replaceDriver(ConfigNode config) {
        ConfigNode drivers = config.getSubNode("drivers");
        if (!FrameworkDriverFactory.exists(drivers["base"])) {
            throw new FrameworkException("Base driver doesn't exist: "
                ~ drivers["base"]);
        }
        if (!DrawDriverFactory.exists(drivers["draw"])) {
            throw new FrameworkException("Draw driver doesn't exist: "
                ~ drivers["draw"]);
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
        //for graphics (pure SDL, OpenGL...)
        mDrawDriver = DrawDriverFactory.instantiate(drivers["draw"],
            config.getSubNode(drivers["draw"]));
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

        mDrawDriver.destroy();
        mDrawDriver = null;

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

    public DrawDriver drawDriver() {
        return mDrawDriver;
    }

    //--- DriverSurface handling

    package DriverSurface createDriverSurface(SurfaceData data) {
        DriverSurface res = mDrawDriver.createSurface(data);
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
        surface.kill();
        surface = null;
    }

    //--- Surface handling

    Surface createSurface(Vector2i size, Transparency transparency,
        Color colorkey = Color(0))
    {
        return new Surface(size, transparency, colorkey);
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
        return mDrawDriver.screenshot();
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

            Canvas c = mDrawDriver.startScreenRendering();
            if (onFrame) {
                onFrame(c);
            }
            drawSoftCursor(c);
            mDrawDriver.stopScreenRendering();
            mDriver.flipScreen();
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
            if (s.mData.driver_surface)
                count++;
            s.passivate();
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
        foreach (Sample s; gSounds.list) {
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
        count += mDrawDriver.releaseCaches();
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
        mDrawDriver.initVideoMode(mDriver.getVideoWindowState().actualSize());
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
                    auto d = s.mData.driver_surface;
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

alias StaticFactory!("DrawDrivers", DrawDriver, ConfigNode) DrawDriverFactory;
