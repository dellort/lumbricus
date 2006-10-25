module framework.framework;

import std.stream;
public import utils.vector2;
import framework.keysyms;
import utils.time;

debug import std.stdio;

private static Framework gFramework;

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

public class Surface {
    //true if this is the single and only screen surface!
    //(or the backbuffer)
    public abstract bool isScreen();

    //whether the surface is painted to the screen (set automatically)
    public abstract bool isOnScreen();
    public abstract void isOnScreen(bool onScreen);

    public abstract Vector2i size();

    //this is done so to be able OpenGL
    //(OpenGL would translate these calls to glNewList() and glEndList()
    public abstract Canvas startDraw();
    public abstract void endDraw();

    /// set colorkey, all pixels with that color will be transparent
    public abstract void enableColorkey(Color colorkey = cStdColorkey);
    /// enable use of the alpha channel
    public abstract void enableAlpha();

    public abstract Color colorkey();
    public abstract Transparency transparency();

    /// convert the image data to raw pixel data, using the given format
    public abstract bool convertToData(PixelFormat format, out uint pitch,
        out void* data);

    /// convert the texture to a transparency mask
    /// one pixel per byte; the pitch is the width (pixel = arr[y*w+x])
    /// transparent pixels are converted to 0, solid ones to 255
    //xxx: handling of alpha values unclear
    public byte[] convertToMask() {
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

        byte[] res = new byte[tex_w*tex_h];

        for (uint y = 0; y < tex_h; y++) {
            for (uint x = 0; x < tex_w; x++) {
                uint val = (cast(uint*)(cast(byte*)(texptr)+y*tex_pitch))[x];
                res[y*tex_w+x] =
                    cast(byte)((val & fmt.mask_a) ? 255 : 0);
            }
        }

        //dozens of garbage collected megabytes later...
        return res;
    }
}

public class Canvas {
    public abstract Vector2i size();

    //must be called after drawing done
    public abstract void endDraw();

    public void draw(Surface source, Vector2i destPos) {
        draw(source, destPos, Vector2i(0, 0), source.size);
    }

    public abstract void draw(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize);

    public abstract void drawCircle(Vector2i center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2i center, int radius,
        Color color);
    public abstract void drawLine(Vector2i p1, Vector2i p2, Color color);
    public abstract void drawRect(Vector2i p1, Vector2i p2, Color color);
    public abstract void drawFilledRect(Vector2i p1, Vector2i p2, Color color);

    public abstract void clear(Color color);
}

struct FontProperties {
    int size = 14;
    Color back = {0.0f,0.0f,0.0f,1.0f};
    Color fore = {1.0f,1.0f,1.0f,1.0f};
}

public class Font {
    /// draw UTF8 encoded text (use framework singleton to instantiate it)
    public abstract void drawText(Canvas canvas, Vector2i pos, char[] text);
    /// same for UTF-32
    public abstract void drawText(Canvas canvas, Vector2i pos, dchar[] text);
    /// return pixel width/height of the text
    public abstract Vector2i textSize(char[] text);
    public abstract Vector2i textSize(dchar[] text);

    public abstract FontProperties properties();
}

/// Information about a key press
public struct KeyInfo {
    Keycode code;
    /// Fully translated according to system keymap and modifiers
    dchar unicode = '\0';

    bool isPrintable() {
        return unicode >= 0x20;
    }
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;
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

    //initialize time between FPS recalculations
    static this() {
        cFPSTimeSpan = timeSecs(1);
    }

    public Vector2i mousePos() {
        return mMousePos;
    }

    public this() {
        mKeyStateMap = new bool[Keycode.max-Keycode.min+1];
        if (gFramework !is null) {
            throw new Exception("Framework is a singleton");
        }
        gFramework = this;
        setCurrentTimeDelegate(&getCurrentTime);
    }

    public abstract void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen);

    /// set window title
    public abstract void setCaption(char[] caption);

    public abstract Surface loadImage(Stream st, Transparency transp);
    public Surface loadImage(char[] fileName, Transparency transp) {
        return loadImage(new File(fileName,FileMode.In), transp);
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

    public abstract Font loadFont(Stream str, FontProperties fontProps);

    public abstract Surface screen();

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

            mFPSFrameCount++;
        }
    }

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

    protected void doKeyDown(in KeyInfo infos) {
        bool was_down = getKeyState(infos.code);

        updateKeyState(infos, true);
        if (!was_down && onKeyDown != null) {
            onKeyDown(infos);
        }

        if (onKeyPress != null) {
            onKeyPress(infos);
        }
    }

    protected void doKeyUp(in KeyInfo infos) {
        updateKeyState(infos, false);
        if (infos.code == Keycode.F4 && getModifierState(Modifier.Alt)) {
            doTerminate();
        }
        if (onKeyUp != null) {
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
            mMousePos = pos;
            if (onMouseMove != null) {
                onMouseMove(infos);
            }
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

    /// executed when receiving quit event from framework
    /// return false to abort quit
    public bool delegate() onTerminate;
    /// Event raised when the screen is repainted
    public void delegate() onFrame;
    /// Event raised on key-down/up events; these events are not auto repeated
    public void delegate(KeyInfo key) onKeyDown;
    public void delegate(KeyInfo key) onKeyUp;
    /// Event raised on key-down; this event is auto repeated
    public void delegate(KeyInfo key) onKeyPress;
    /// Event raised when the mouse pointer is changed
    /// Note that mouse button are managed by the onKey* events
    public void delegate(MouseInfo mouse) onMouseMove;
}
