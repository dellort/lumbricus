module framework.framework;

import std.stream;
public import utils.vector2;
import framework.keysyms;
import utils.time;
import framework.font;
import conv = std.conv;
import str = std.string;
import framework.filesystem;
import config = utils.configfile;

debug import std.stdio;

package static Framework gFramework;

public Framework getFramework() {
    return gFramework;
}

public Color cStdColorkey = {r:1.0f, g:0.0f, b:1.0f, a:0.0f};

public struct Color {
    //values between 0.0 and 1.0, 1.0 means full intensity
    //(a is the alpha value; 1.0 means fully opaque)
    float r, g, b, a;

    /// a value that can be used as epsilon when comparing colors
    //0.3f is a fuzzify value, with 255 I expect colors to be encoded with at
    //most 8 bits
    public static const float epsilon = 0.3f * 1.0f/255;

    /// clamp all components to the range [0.0, 1.0]
    public void clamp() {
        if (r < 0.0f) r = 0.0f;
        if (r > 1.0f) r = 1.0f;
        if (g < 0.0f) g = 0.0f;
        if (g > 1.0f) g = 1.0f;
        if (b < 0.0f) b = 0.0f;
        if (b > 1.0f) b = 1.0f;
        if (a < 0.0f) a = 0.0f;
        if (a > 1.0f) a = 1.0f;
    }

    public static Color opCall(float r, float g, float b, float a) {
        Color res;
        res.r = r;
        res.g = g;
        res.b = b;
        res.a = a;
        return res;
    }
    public static Color opCall(float r, float g, float b) {
        return opCall(r,g,b,1.0f);
    }
    public static Color opCall(float c) {
        return opCall(c,c,c);
    }

    Color opMul(float m) {
        Color res = *this;
        res *= m;
        return res;
    }
    void opMulAssign(float m) {
        r = r*m;
        g = g*m;
        b = b*m;
    }
}

enum Transparency {
    None,
    Colorkey,
    Alpha
}

/// default display formats for surfaces (used in constructor-methods)
/// other formats can be used too, but these are supposed to be "important"
enum DisplayFormat {
    /// fastest format for drawing on the screen
    Screen,
    /// exactly equal to the screen format (xxx: ever needed???)
    ReallyScreen,
    /// best display format (usually 32 bit RGBA)
    Best,
    /// guaranteed to be 32 bit RGBA
    //xxx: use alpha transparency, on colorkey, SDL groks up (???)
    RGBA32,
}

//xxx: ?
public uint colorToRGBA32(Color color) {
    uint r = cast(ubyte)(255*color.r);
    uint g = cast(ubyte)(255*color.g);
    uint b = cast(ubyte)(255*color.b);
    uint a = cast(ubyte)(255*color.a);
    return a << 24 | r << 16 | g << 8 | b;
}

public struct PixelFormat {
    uint depth; //in bits
    uint bytes; //per pixel
    uint mask_r, mask_g, mask_b, mask_a;
}

/// Subregion of a texture.
//(hm, putting that into Texture would be too expensive I guess)
public struct TextureRef {
    Texture texture;
    Vector2i pos, size;
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

    /// convert the image data to raw pixel data, using the given format
    public abstract bool convertToData(PixelFormat format, out uint pitch,
        out void* data);

    /// Create a texture from this surface.
    /// The texture may or may not reflect changes to the surface since this
    /// function was called. Texture.recreate() will update the Texture.
    public abstract Texture createTexture();
    /// hmhm
    public abstract Texture createBitmapTexture();

    //mirror on Y axis
    public abstract Surface createMirroredY();

    /// convert the texture to a transparency mask
    /// one pixel per byte; the pitch is the width (pixel = arr[y*w+x])
    /// transparent pixels are converted to 0, solid ones to 255
    //xxx: handling of alpha values unclear
    public ubyte[] convertToMask() {
        //copied from level/renderer.d
        //this is NOT nice, but sucks infinitely

        PixelFormat fmt;
        //xxx this isn't good and nice; needs rework anyway
        fmt.depth = 32; //SDL doesn't like depth=24 (maybe it takes 3 bytes pp)
        fmt.bytes = 4;
        fmt.mask_r = 0xff0000;
        fmt.mask_g = 0x00ff00;
        fmt.mask_b = 0x0000ff;
        fmt.mask_a = 0xff000000;

        uint tex_pitch;
        void* tex_data;
        convertToData(fmt, tex_pitch, tex_data);
        uint tex_w = size.x;
        uint tex_h = size.y;
        uint* texptr = cast(uint*)tex_data;

        ubyte[] res = new ubyte[tex_w*tex_h];

        for (uint y = 0; y < tex_h; y++) {
            uint* val = cast(uint*)(cast(byte*)(texptr)+y*tex_pitch);
            for (uint x = 0; x < tex_w; x++) {
                res[y*tex_w+x] =
                    cast(ubyte)((*val & fmt.mask_a) ? 255 : 0);
                val++;
            }
        }

        //dozens of garbage collected megabytes later...
        return res;
    }
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

    //must be called after drawing done
    public abstract void endDraw();

    public void draw(Texture source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public void draw(TextureRef texture, Vector2i dest) {
        draw(texture.texture, dest, texture.pos, texture.size);
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

public enum Modifier {
    Alt,
    Control,
    Shift,
    //we don't consider Numlock to be a modifier anymore
    //instead, the keyboard driver is supposed to deliver different keycodes
    //for the numpad-keys, when numlock is toggled
    //Numlock,
}

/// Where mod is a Modifier and modifierset is a ModifierSet:
/// bool modifier_active = !!((1<<mod) & modifierset)
/// ("!!" means convert to bool)
public typedef uint ModifierSet;

public bool modifierIsSet(ModifierSet s, Modifier m) {
    return !!((1<<m) & s);
}
public void modifierSet(inout ModifierSet s, Modifier m) {
    s |= (1<<m);
}
public void foreachSetModifier(ModifierSet s, void delegate(Modifier m) cb) {
    for (Modifier m = Modifier.min; m <= Modifier.max; m++) {
        if (modifierIsSet(s, m)) cb(m);
    }
}

/// Information about a key press
public struct KeyInfo {
    Keycode code;
    /// Fully translated according to system keymap and modifiers
    dchar unicode = '\0';
    /// set of active modifiers when event was fired
    ModifierSet mods;

    bool isPrintable() {
        return unicode >= 0x20;
    }
    bool isMouseButton() {
        return code >= cKeycodeMouseStart && code <= cKeycodeMouseEnd;
    }

    char[] toString() {
        return str.format("[KeyInfo: code=%d mods=%d ch='%s'",
            cast(int)code, cast(int)mods,
            cast(dchar)(isPrintable ? unicode : '?'));
    }
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;
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

    //another singelton
    private FontManager mFontManager;
    private FileSystem mFilesystem;

    private bool mEnableEvents = true;

    //initialize time between FPS recalculations
    static this() {
        cFPSTimeSpan = timeSecs(1);
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

    public abstract bool grabInput();

    public abstract void grabInput(bool grab);

    public this(char[] arg0, char[] appId) {
        mKeyStateMap = new bool[Keycode.max-Keycode.min+1];
        if (gFramework !is null) {
            throw new Exception("Framework is a singleton");
        }
        mFilesystem = new FileSystem(arg0, appId);
        gFramework = this;
        setCurrentTimeDelegate(&getCurrentTime);
    }

    public abstract void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen);

    public abstract uint bitDepth();

    /// set window title
    public abstract void setCaption(char[] caption);

    public abstract Surface loadImage(Stream st, Transparency transp);
    public Surface loadImage(char[] fileName, Transparency transp) {
        return loadImage(fs.open(fileName,FileMode.In), transp);
    }

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
        *(cast(uint*)data) = colorToRGBA32(color);
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

            mFPSFrameCount++;
        }
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
    protected void doKeyDown(in KeyInfo infos) {
        bool was_down = getKeyState(infos.code);

        updateKeyState(infos, true);
        if (!was_down) {
            //if (handleShortcuts(infos, true)) {
            //    //it did handle the key; don't do anything more with that key
            //    return;
            //}
            if (onKeyDown && mEnableEvents) {
                bool handle = onKeyDown(infos);
                if (!handle)
                    return;
            }
        }

        if (onKeyPress != null && mEnableEvents) {
            onKeyPress(infos);
        }
    }

    protected void doKeyUp(in KeyInfo infos) {
        updateKeyState(infos, false);
        if (infos.code == Keycode.F4 && getModifierState(Modifier.Alt)) {
            doTerminate();
        }
        //if (!handleShortcuts(infos, false)) {
            if (onKeyUp && mEnableEvents) onKeyUp(infos);
        //}
    }

    //returns true if key is a mouse button
    public static bool keyIsMouseButton(Keycode key) {
        return key >= cKeycodeMouseStart && key <= cKeycodeMouseEnd;
    }

    protected void doUpdateMousePos(Vector2i pos) {
        Vector2i realPos = pos;
        if (mLockMouse) {
            pos += mMouseCorr;
        }
        if (mMousePos != pos) {
            MouseInfo infos;
            infos.pos = pos;
            if (mLockMouse)
                infos.pos -= mMouseCorr;
            infos.rel = pos - mMousePos;
            mMousePos = pos;
            if (onMouseMove != null && mEnableEvents) {
                onMouseMove(infos);
            }
            if (mLockMouse) {
                mousePos = mLockedMousePos;
                mMouseCorr += (realPos-mLockedMousePos);
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

    ///This will move the mouse cursor to screen center and keep it there
    ///It is probably a good idea to hide the cursor first, as it will still
    ///be moveable and generate events, but "snap" back to the locked position
    public void lockMouse() {
        mLockedMousePos = screen.size/2;
        mStoredMousePos = mousePos;
        mLockMouse = true;
        mousePos = mLockedMousePos;
        mMouseCorr = mStoredMousePos - mLockedMousePos;
    }

    ///Remove the mouse lock and move the cursor back to where it was before
    public void unlockMouse() {
        mousePos = mStoredMousePos;
        mLockMouse = false;
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

    public abstract void cursorVisible(bool v);
    public abstract bool cursorVisible();

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
}

/// Map key combinations to IDs (strings).
public class KeyBindings {
    private struct Key {
        Keycode code;
        //bit field, each bit as in Modifier enum
        uint required_mods;
    }
    private struct Entry {
        char[] bound_to;
        uint required_mods;
    }

    private Entry[Key] mBindings;

    private uint countmods(uint mods) {
        uint sum = 0;
        for (int n = Modifier.min; n <= Modifier.max; n++) {
            sum += !!(mods & (1 << n));
        }
        return sum;
    }

    //find the key which matches with the _most_ modifiers
    //to do that, try with all permutations (across active mods) :/
    private Entry* doFindBinding(Keycode code, uint mods, uint pos = 0) {
        if (!(mods & (1<<pos))) {
            pos++;
            if (pos > Modifier.max) {
                //recursion end
                Key k;
                k.code = code;
                k.required_mods = mods;
                return k in mBindings;
            }
        }
        //bit is set at this position...
        //try recursively with and without that bit set
        Entry* e1 = doFindBinding(code, mods & ~(1<<pos), pos+1);
        Entry* e2 = doFindBinding(code, mods, pos+1);

        //check which wins... if both are non-null, that with more modifiers
        if (e1 && e2) {
            e1 = countmods(e1.required_mods) > countmods(e2.required_mods)
                ? e1 : e2;
            e2 = null;
        }
        if (!e1) {
            e1 = e2; e2 = null;
        }

        return e1;
    }

    //returns how many modifiers the winning key binding eats up
    //return -1 if no match
    public int checkBinding(Keycode code, ModifierSet mods) {
        Entry* e = doFindBinding(code, mods);
        if (!e) {
            return -1;
        } else {
            return countmods(e.required_mods);
        }
    }

    public char[] findBinding(Keycode code, ModifierSet mods) {
        Entry* e = doFindBinding(code, mods);
        if (!e) {
            return null;
        } else {
            return e.bound_to;
        }
    }

    public char[] findBinding(KeyInfo info) {
        return findBinding(info.code, info.mods);
    }

    //parse a whitespace separated list of strings into sth. that can be passed
    //to addBinding()
    public bool parseBindString(char[] bindstr, out Keycode out_code,
        out ModifierSet out_mods)
    {
        foreach (char[] s; str.split(bindstr)) {
            Modifier mod;
            if (gFramework.stringToModifier(s, mod)) {
                out_mods |= (1<<mod);
            } else {
                if (out_code != Keycode.INVALID)
                    return false;
                out_code = gFramework.translateKeyIDToKeycode(s);
                if (out_code == Keycode.INVALID)
                    return false;
            }
        }
        return (out_code != Keycode.INVALID);
    }
    //undo parseBindString, return bindstr
    public char[] unparseBindString(Keycode code, ModifierSet mods) {
        char[][] stuff;
        stuff = [gFramework.translateKeycodeToKeyID(code)];
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            if (modifierIsSet(mods, mod))
                stuff ~= gFramework.modifierToString(mod);
        }
        return str.join(stuff, " ");
    }

    /// Add a binding.
    public bool addBinding(char[] bind_to, Keycode code, ModifierSet mods) {
        Key k;
        k.code = code;
        k.required_mods = mods;

        Entry e;
        e.bound_to = bind_to;
        e.required_mods = k.required_mods;;

        mBindings[k] = e;
        return true;
    }

    /// Add a binding (by string).
    public bool addBinding(char[] bind_to, char[] bindstr) {
        Keycode code;
        ModifierSet mods;
        if (!parseBindString(bindstr, code, mods))
            return false;
        return addBinding(bind_to, code, mods);
    }

    /// Remove all key combinations that map to the binding "bind".
    public void removeBinding(char[] bind) {
        //hm...
        Key[] keys;
        foreach (Key k, Entry e; mBindings) {
            if (bind == e.bound_to)
                keys ~= k;
        }
        foreach (Key k; keys) {
            mBindings.remove(k);
        }
    }

    public void clear() {
        mBindings = null;
    }

    public void loadFrom(config.ConfigNode node) {
        foreach (char[] name, char[] value; node) {
            if (!addBinding(name, str.tolower(value))) {
                debug writefln("could not bind '%s' '%s'", name, value);
            }
        }
    }

    /// Enum all defined bindings.
    /// Caller must not add or remove bindings while enumerating.
    public void enumBindings(void delegate(char[] bind, Keycode code,
        ModifierSet mods) callback)
    {
        if (!callback)
            return;

        foreach (Key k, Entry e; mBindings) {
            callback(e.bound_to, k.code, cast(ModifierSet)k.required_mods);
        }
    }
}

//xxx: move... what about color.d?
public bool parseColor(char[] s, inout Color color) {
    //predefined colors
    //if you have time, move this into a configfile! :-)
    Color[char[]] colors;
    colors["white"] = Color(1.0f);
    colors["black"] = Color(0.0f);
    colors["off"] = Color(0.0f);
    colors["grey"] = Color(0.5f);
    colors["red"] = Color(1.0f,0,0);
    colors["blue"] = Color(0,0,1.0f);
    colors["green"] = Color(0,1.0f,0);
    colors["yellow"] = Color(1.0f,1.0f,0);
    colors["magenta"] = Color(1.0f,0,1.0f);
    colors["cyan"] = Color(0,1.0f,1.0f);

    if (s in colors) {
        color = colors[s];
        return true;
    }

    char[][] values = str.split(s);
    if (values.length < 3 || values.length > 4)
        return false;
    try {
        float r = conv.toFloat(values[0]);
        float g = conv.toFloat(values[1]);
        float b = conv.toFloat(values[2]);
        float a = 1.0f;
        if (values.length > 3) {
            a = conv.toFloat(values[3]);
        }
        color = Color(r, g, b, a);
        return true;
    } catch (conv.ConvOverflowError e) {
    } catch (conv.ConvError e) {
    }
    return false;
}

//colorparser for boxes (used by the commandline)
import utils.strparser;
import utils.mybox;

private MyBox parseColorBox(char[] s) {
    Color res;
    if (parseColor(s, res)) {
        return MyBox.Box(res);
    }
    return MyBox();
}

static this() {
    gBoxParsers[typeid(Color)] = &parseColorBox;
}
