module framework.framework;

import std.stream;
public import utils.vector2;
public import framework.keysyms;

public struct Color {
    float r, g, b, a;

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

public class Surface {
    public abstract Vector2i size();

    //this is done so to be able OpenGL
    //(OpenGL would translate these calls to glNewList() and glEndList()
    public abstract Canvas startDraw();
    public abstract void endDraw();
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
    Color fore = {1.0f,0.0f,0.0f,1.0f};
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
    }

    public abstract void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen);

    /// set window title
    public abstract void setCaption(char[] caption);

    public abstract Surface loadImage(Stream st);
    public Surface loadImage(char[] fileName) {
        return loadImage(new File(fileName,FileMode.In));
    }

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
