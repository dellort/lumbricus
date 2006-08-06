module framework.framework;

import std.stream;
public import utils.vector2;
import framework.keysyms;

private static Framework gFramework;

public Framework getFramework() {
    return gFramework;
}

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

public struct PixelFormat {
    uint depth; //in bits
    uint bytes; //per pixel
    uint mask_r, mask_g, mask_b, mask_a;
}

public class Surface {
    public abstract Vector2i size();

    //this is done so to be able OpenGL
    //(OpenGL would translate these calls to glNewList() and glEndList()
    public abstract Canvas startDraw();
    public abstract void endDraw();
    
    /// convert the image data to raw pixel data, using the given format
    public abstract bool convertToData(PixelFormat format, out uint pitch,
        out void* data);
    
    /// set colorkey, all pixels with that color will be transparent
    //I'm not sure how this would work with OpenGL...
    public abstract void colorkey(Color colorkey);
}

public class Canvas {
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
}

struct FontProperties {
    int size = 14;
    Color back = {0.0f,0.0f,0.0f,1.0f};
    Color fore = {1.0f,1.0f,1.0f,1.0f};
}

public class Font {
    public abstract void drawText(Canvas canvas, Vector2i pos, char[] text);
}

/// Information about a key press
public struct KeyInfo {
    Keycode code;
    /// Fully translated according to system keymap and modifiers
    dchar unicode = '\0';
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;
}

public enum Modifier {
    Alt,
    Control,
    Shift,
    Numlock,
}

/// Contains event- and graphics-handling
public class Framework {
    //contains keystate (key down/up) for each key; indexed by Keycode
    private bool mKeyStateMap[];
    private bool mCapsLock, mNumLock;
    private Vector2i mMousePos;

    public this() {
        mKeyStateMap = new bool[Keycode.max-Keycode.min+1];
        if (gFramework !is null) {
            throw new Exception("Framework is a singleton");
        }
        gFramework = this;
    }

    public abstract void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen);

    /// set window title
    public abstract void setCaption(char[] caption);

    public abstract Surface loadImage(Stream st);
    public Surface loadImage(char[] fileName) {
        return loadImage(new File(fileName,FileMode.In));
    }
    
    /// create an image based on the given data and on the pixelformat
    /// data can be null, in this case, the function allocates (GCed) memory
    public abstract Surface createImage(uint width, uint height, uint pitch,
        PixelFormat format, void* data);
    
    /// create a surface in the current display format
    public abstract Surface createSurface(uint width, uint height);

    public abstract Font loadFont(Stream str, FontProperties fontProps);

    public abstract Surface screen();

    /// Main-Loop
    public abstract void run();

    /// set to true if run() should exit
    protected bool shouldTerminate;

    /// requests main loop to terminate
    public void terminate() {
        shouldTerminate = true;
    }
    
    /// return number of invocations of onFrame pro second
    public abstract float FPS();

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
