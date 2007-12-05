module framework.framework;

import std.stream;
public import utils.vector2;
public import utils.rect2;
public import utils.color;
public import framework.event;
public import framework.sound;
public import framework.keybindings;
import utils.time;
import utils.perf;
import utils.path;
import framework.font;
import conv = std.conv;
import str = std.string;
import framework.filesystem;
import framework.resources;
import config = utils.configfile;
import utils.log, utils.output;

debug import std.stdio;

public static Framework gFramework;

public Framework getFramework() {
    return gFramework;
}

public Color cStdColorkey = {r:1.0f, g:0.0f, b:1.0f, a:0.0f};

enum Transparency {
    None,
    Colorkey,
    Alpha,
    AutoDetect, //special value: get transparency from file when loading
                //invalid as surface transparency type
}

/// default display formats for surfaces (used in constructor-methods)
/// other formats can be used too, but these are supposed to be "important"
enum DisplayFormat {
    /// fastest format for drawing on the screen
    Screen,
    /// best format to draw on screen when you need alpha blending
    ScreenAlpha,
    /// best display format (usually 32 bit RGBA)
    Best,
    /// guaranteed to be 32 bit RGBA
    //xxx: use alpha transparency, on colorkey, SDL groks up (???)
    RGBA32,
}

public struct PixelFormat {
    uint depth; //in bits
    uint bytes; //per pixel
    uint mask_r, mask_g, mask_b, mask_a;

    char[] toString() {
        return str.format("[bits/bytes=%s/%s R/G/B/A=%#08x/%#08x/%#08x/%#08x]",
            depth, bytes, mask_r, mask_g, mask_b, mask_a);
    }
}

public class Surface {
    //true if this is the single and only screen surface!
    //(or the backbuffer)
    //public abstract bool isScreen();

    public abstract Vector2i size();

    public abstract Surface clone();
    public abstract void free();

    public abstract Canvas startDraw();
    //public abstract void endDraw();

    /// set colorkey, all pixels with that color will be transparent
    public abstract void enableColorkey(Color colorkey = cStdColorkey);
    /// enable use of the alpha channel
    public abstract void enableAlpha();

    /// hahaha!
    public abstract void forcePixelFormat(PixelFormat fmt);
    public abstract void lockPixels(out void* pixels, out uint pitch);
    /// like lockPixels(), but ensure RGBA32 format before
    /// (xxx see comment in SDL implementation)
    public abstract void lockPixelsRGBA32(out void* pixels, out uint pitch);
    /// must be called after done with lockPixels()
    public abstract void unlockPixels();

    /// return colorkey or a 0-alpha black, depending from transparency mode
    public abstract Color colorkey();
    public abstract Transparency transparency();

    /// Create a texture from this surface.
    /// The texture may or may not reflect changes to the surface since this
    /// function was called. Texture.recreate() will update the Texture.
    public abstract Texture createTexture();
    /// hmhm
    public abstract Texture createBitmapTexture();

    //mirror on Y axis
    public abstract Surface createMirroredY();
}

public abstract class Texture {
    /// return the underlying surface, may not reflect the current state of it
    public abstract Surface getSurface();
    public abstract void clearCache();
    public abstract Vector2i size();
    public abstract void setCaching(bool state);
}

/// Draw stuffies!
//HINT: The framework.sdl will implement this two times: once for SDL and once
//      for the OpenGL screen!
public class Canvas {
    public abstract Vector2i realSize();
    public abstract Vector2i clientSize();

    /// offset to add to client coords to get position of the fist
    /// visible upper left point on the screen or canvas (?)
    //(returns translation relative to last setWindow())
    public abstract Vector2i clientOffset();

    /// Get the rectangle in client coords which is visible
    /// (right/bottom borders exclusive)
    public abstract Rect2i getVisible();

    /// Return true if any part of this rectangle is visible
    //public abstract bool isVisible(in Vector2i p1, in Vector2i p2);

    //must be called after drawing done
    public abstract void endDraw();

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize);

    public abstract void drawCircle(Vector2i center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2i center, int radius,
        Color color);
    public abstract void drawLine(Vector2i p1, Vector2i p2, Color color);
    public abstract void drawRect(Vector2i p1, Vector2i p2, Color color);
    /// properalpha: ignored in OpenGL mode, hack for SDL only mode :(
    public abstract void drawFilledRect(Vector2i p1, Vector2i p2, Color color,
        bool properalpha = true);

    public abstract void clear(Color color);

    /// Set a clipping rect, and use p1 as origin (0, 0)
    public abstract void setWindow(Vector2i p1, Vector2i p2);
    /// Add translation offset, by which all coordinates are translated
    public abstract void translate(Vector2i offset);
    /// Set the cliprect (doesn't change "window" or so).
    public abstract void clip(Vector2i p1, Vector2i p2);
    /// push/pop state as set by setWindow() and translate()
    public abstract void pushState();
    public abstract void popState();

    /// Fill the area (destPos, destPos+destSize) with source, tiled on wrap
    //warning: not very well tested
    //will be specialized in OpenGL
    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        int w = source.size.x1;
        int h = source.size.x2;
        int x;
        Vector2i tmp;

        if (w == 0 || h == 0)
            return;

        int y = 0;
        while (y < destSize.y) {
            tmp.y = destPos.y + y;
            int resty = ((y+h) < destSize.y) ? h : destSize.y - y;
            x = 0;
            while (x < destSize.x) {
                tmp.x = destPos.x + x;
                int restx = ((x+w) < destSize.x) ? w : destSize.x - x;
                draw(source, tmp, Vector2i(0, 0), Vector2i(restx, resty));
                x += restx;
            }
            y += resty;
        }
    }
}

//returns number of released resources (surfaces, currently)
public alias int delegate() CacheReleaseDelegate;

/// For Framework.getInfoString()
/// Entries from Framework.getInfoStringNames() correspond to this
/// Each entry describes a piece of information which can be queried by calling
/// Framework.getInfoString().
enum InfoString {
    Framework,
    Backend,
    ResourceList,
    Custom0, //hack lol
}

/// Contains event- and graphics-handling
public class Framework {
    //contains keystate (key down/up) for each key; indexed by Keycode
    private bool mKeyStateMap[];
    private bool mCapsLock;
    private Vector2i mMousePos;

    private Time mFPSLastTime;
    private uint mFPSFrameCount;
    private float mFPSLastValue;

    private static Time cFPSTimeSpan; //how often to recalc FPS

    //least time per frame; for fixed framerate (0 to disable)
    private static Time mTimePerFrame;

    private Time mLastFrameTime;

    //another singelton
    private FontManager mFontManager;
    private FileSystem mFilesystem;
    public Resources resources;

    private bool mEnableEvents = true;

    private Color mClearColor;

    private CacheReleaseDelegate[] mCacheReleasers;

    protected Log log;
    private Log mLogConf;

    static this() {
        //initialize time between FPS recalculations
        cFPSTimeSpan = timeSecs(1);
    }

    /// Get a string for a specific entry (see InfoString).
    /// Overridden by the framework implementation.
    /// Since it can have more than one line, it's always terminated with \n
    public char[] getInfoString(InfoString s) {
        return "?\n";
    }

    void setDebug(bool set) {
        //default: nop
    }

    /// Return valid InfoString entry numbers and their name (see InfoString).
    public InfoString[char[]] getInfoStringNames() {
        return [cast(char[])"framework": InfoString.Framework,
                "backend": InfoString.Backend,
                "resource_list": InfoString.ResourceList,
                "custom0": InfoString.Custom0];
    }

    /// register a callback which is called on releaseCaches()
    public void registerCacheReleaser(CacheReleaseDelegate callback) {
        mCacheReleasers ~= callback;
    }

    /// release all cached data, which can easily created again (i.e. font glyph
    /// surfaces)
    /// returns number of freed resources (cf. CacheReleaseDelegate)
    public int releaseCaches() {
        int released;
        foreach (r; mCacheReleasers) {
            released += r();
        }
        return released;
    }

    /// set texture caching; if set, it could be faster but also memory hungrier
    public void setAllowCaching(bool set) {
        //framework could override this
    }

    /// set a fixed framerate / a maximum framerate
    /// fps = framerate, or 0 to disable fixed framerate
    public void fixedFramerate(int fps) {
        if (fps == 0) {
            mTimePerFrame = timeMsecs(0);
        } else {
            mTimePerFrame = timeMsecs(1000/fps);
        }
    }

    public Vector2i mousePos() {
        return mMousePos;
    }
    public abstract void mousePos(Vector2i newPos);

    public void clearColor(Color c) {
        mClearColor = c;
    }
    public Color clearColor() {
        return mClearColor;
    }

    public abstract bool grabInput();

    public abstract void grabInput(bool grab);

    public this(char[] arg0, char[] appId) {
        log = registerLog("Fw");
        mKeyStateMap = new bool[Keycode.max-Keycode.min+1];
        if (gFramework !is null) {
            throw new Exception("Framework is a singleton");
        }

        mFilesystem = new FileSystem(arg0, appId);
        resources = new Resources();

        gFramework = this;
        setCurrentTimeDelegate(&getCurrentTime);
    }

    public abstract void setVideoMode(Vector2i size, int bpp, bool fullscreen);
    //version for default arguments
    public void setVideoMode(Vector2i size, int bpp = -1) {
        setVideoMode(size, bpp, fullScreen());
    }

    public abstract void setFullScreen(bool s);

    public abstract uint bitDepth();
    public abstract bool fullScreen();

    /// set window title
    public abstract void setCaption(char[] caption);

    public abstract Surface loadImage(Stream st, Transparency transp);
    public Surface loadImage(char[] path,
        Transparency t = Transparency.AutoDetect)
    {
        log("load image: %s", path);
        scope stream = fs.open(path, FileMode.In);
        auto image = loadImage(stream, t);
        return image;
    }

    /+
    /// create an image based on the given data and on the pixelformat
    /// data can be null, in this case, the function allocates (GCed) memory
    public abstract Surface createImage(Vector2i size, uint pitch,
        PixelFormat format, Transparency transp, void* data);

    //xxx code duplication, (re)move
    public Surface createImageRGBA32(Vector2i size, uint pitch,
        Transparency transp, void* data)
    {
        return createImage(size, pitch, findPixelFormat(DisplayFormat.RGBA32),
            transp, data);
    }
    +/

    /// get a "standard" pixel format (sigh)
    //NOTE: implementor is supposed to overwrite this and to catch the current
    //  screen format values
    public PixelFormat findPixelFormat(DisplayFormat fmt) {
        switch (fmt) {
            case DisplayFormat.Best, DisplayFormat.RGBA32: {
                //keep in sync with SDL implementation's lockPixelsRGBA32()
                PixelFormat ret;
                ret.depth = 32;
                ret.bytes = 4;
                ret.mask_r = 0x00ff0000;
                ret.mask_g = 0x0000ff00;
                ret.mask_b = 0x000000ff;
                ret.mask_a = 0xff000000;
                return ret;
            }
            default:
                assert(false);
        }
    }

    /// create a surface in the current display format
    public abstract Surface createSurface(Vector2i size, DisplayFormat fmt,
        Transparency transp);

    /// a surface of size 1x1 with a pixel of given color
    public Surface createPixelSurface(Color color) {
        auto surface = createSurface(Vector2i(1, 1), DisplayFormat.RGBA32,
            Transparency.None);
        void* data; uint pitch;
        surface.lockPixelsRGBA32(data, pitch);
        *(cast(uint*)data) = color.toRGBA32();
        surface.unlockPixels();
        return surface;
    }

    /// load a font, Stream "str" should contain a .ttf file
    public abstract Font loadFont(Stream str, FontProperties fontProps);

    /// load a font using the font manager
    public Font getFont(char[] id) {
        return fontManager.loadFont(id);
    }

    public FontManager fontManager() {
        if (!mFontManager)
            mFontManager = new FontManager();
        return mFontManager;
    }

    public abstract Surface screen();

    public FileSystem fs() {
        return mFilesystem;
    }

    public abstract Sound sound();

    public config.ConfigNode loadConfig(char[] section, bool asfilename = false,
        bool allowFail = false)
    {
        VFSPath file = VFSPath(section ~ (asfilename ? "" : ".conf"));
        log("load config: %s", file);
        try {
            scope s = fs.open(file);
            auto f = new config.ConfigFile(s, file.get(), &logconf);
            if (!f.rootnode)
                throw new Exception("?");
            return f.rootnode;
        } catch (Exception e) {
            if (!allowFail)
                throw e;
        }
        log("config file %s failed to load (allowFail = true)", file);
        return null;
    }

    private void logconf(char[] log) {
        if (!mLogConf) {
            mLogConf = registerLog("configfile");
            assert(mLogConf !is null);
        }
        mLogConf("%s", log);
    }

    /// Main-Loop
    public void run() {
        while(!shouldTerminate) {
            // recalc FPS value
            Time curtime = getCurrentTime();
            if (curtime >= mFPSLastTime + cFPSTimeSpan) {
                mFPSLastValue = (cast(float)mFPSFrameCount
                    / (curtime - mFPSLastTime).msecs) * 1000.0f;
                mFPSLastTime = curtime;
                mFPSFrameCount = 0;
            }

            run_fw();

            //wait for fixed framerate?
            Time time = getCurrentTime();
            Time diff = mTimePerFrame - (time - curtime);
            if (diff > timeSecs(0)) {
                sleepTime(diff);
            }

            //real frame time
            Time cur = getCurrentTime();
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

    public abstract void sleepTime(Time relative);

    protected abstract void run_fw();

    /// set to true if run() should exit
    protected bool shouldTerminate;

    /// requests main loop to terminate
    public void terminate() {
        shouldTerminate = true;
    }

    public abstract Time getCurrentTime();

    /// return number of invocations of onFrame pro second
    public float FPS() {
        return mFPSLastValue;
    }

    /// translate a Keycode to a OS independent key ID string
    /// return null for Keycode.KEY_INVALID
    public char[] translateKeycodeToKeyID(Keycode code) {
        foreach (KeycodeToName item; g_keycode_to_name) {
            if (item.code == code) {
                return item.name;
            }
        }
        return null;
    }

    /// reverse operation of translateKeycodeToKeyID()
    public Keycode translateKeyIDToKeycode(char[] keyid) {
        foreach (KeycodeToName item; g_keycode_to_name) {
            if (item.name == keyid) {
                return item.code;
            }
        }
        return Keycode.INVALID;
    }

    public char[] modifierToString(Modifier mod) {
        switch (mod) {
            case Modifier.Alt: return "mod_alt";
            case Modifier.Control: return "mod_ctrl";
            case Modifier.Shift: return "mod_shift";
        }
    }

    public bool stringToModifier(char[] str, out Modifier mod) {
        switch (str) {
            case "mod_alt": mod = Modifier.Alt; return true;
            case "mod_ctrl": mod = Modifier.Control; return true;
            case "mod_shift": mod = Modifier.Shift; return true;
            default:
        }
        return false;
    }

    private void updateKeyState(in KeyInfo infos, bool state) {
        assert(infos.code >= Keycode.min && infos.code <= Keycode.max);
        mKeyStateMap[infos.code - Keycode.min] = state;
    }

    /// Query if key is currently pressed down (true) or not (false)
    public bool getKeyState(Keycode code) {
        assert(code >= Keycode.min && code <= Keycode.max);
        return mKeyStateMap[code - Keycode.min];
    }

    /// return if Modifier is applied
    public bool getModifierState(Modifier mod) {
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

    /// return true if all modifiers in the set are applied
    /// empty set applies always
    public bool getModifierSetState(ModifierSet mods) {
        return (getModifierSet() & mods) == mods;
    }

    public bool isModifierKey(Keycode c) {
        switch (c) {
            case Keycode.RALT, Keycode.RCTRL, Keycode.RSHIFT:
            case Keycode.LALT, Keycode.LCTRL, Keycode.LSHIFT:
                return true;
            default:
                return false;
        }
    }

    public ModifierSet getModifierSet() {
        ModifierSet mods;
        for (uint n = Modifier.min; n <= Modifier.max; n++) {
            if (getModifierState(cast(Modifier)n))
                mods |= 1 << n;
        }
        return mods;
    }

    //called from framework implementation... relies on key repeat
    protected void doKeyDown(KeyInfo infos) {
        infos.type = KeyEventType.Down;

        bool was_down = getKeyState(infos.code);

        updateKeyState(infos, true);
        if (!was_down) {
            //if (handleShortcuts(infos, true)) {
            //    //it did handle the key; don't do anything more with that key
            //    return;
            //}
            if (onKeyDown && mEnableEvents) {
                bool handle = onKeyDown(infos);
                /* commented out, doesn't seem logical
                if (!handle)
                    return;*/
            }
        }

        if (onKeyPress != null && mEnableEvents) {
            infos.type = KeyEventType.Press;
            onKeyPress(infos);
        }
    }

    protected void doKeyUp(in KeyInfo infos) {
        infos.type = KeyEventType.Up;

        updateKeyState(infos, false);

        //xxx: huh? shouldn't that be done by the OS' window manager?
        if (infos.code == Keycode.F4 && getModifierState(Modifier.Alt)) {
            doTerminate();
        }

        if (onKeyUp && mEnableEvents) {
            onKeyUp(infos);
        }
    }

    //returns true if key is a mouse button
    public static bool keyIsMouseButton(Keycode key) {
        return key >= cKeycodeMouseStart && key <= cKeycodeMouseEnd;
    }

    protected void doUpdateMousePos(Vector2i pos) {
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
            if (onMouseMove != null && mEnableEvents) {
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

    public char[] keyinfoToString(KeyInfo infos) {
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

    public void enableEvents(bool enable) {
        mEnableEvents = enable;
    }
    public bool enableEvents() {
        return mEnableEvents;
    }

    private Vector2i mStoredMousePos, mLockedMousePos, mMouseCorr;
    private bool mLockMouse;
    private int mFooLockCounter;

    ///This will move the mouse cursor to screen center and keep it there
    ///It is probably a good idea to hide the cursor first, as it will still
    ///be moveable and generate events, but "snap" back to the locked position
    ///Events will show the mouse cursor standing at its locked position
    ///and only show relative motion
    public void lockMouse() {
        if (!mLockMouse) {
            mLockedMousePos = screen.size/2;
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
    public void unlockMouse() {
        if (mLockMouse) {
            mousePos = mStoredMousePos;
            mLockMouse = false;
            mMouseCorr = Vector2i(0);
        }
    }

    protected bool doTerminate() {
        bool term = true;
        if (onTerminate != null) {
            term = onTerminate();
        }
        if (term) {
            terminate();
        }
        return term;
    }

    ///Cleanups (i.e. free all still used resources)
    public abstract void deinitialize();

    public abstract void cursorVisible(bool v);
    public abstract bool cursorVisible();

    public PerfTimer[char[]] timers() {
        return null;
    }

    Time lastFrameTime() {
        return mLastFrameTime;
    }

    /// executed when receiving quit event from framework
    /// return false to abort quit
    public bool delegate() onTerminate;
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
