module framework.framework;

import std.stream;
import vector;
import framework.keysyms;

public struct Color {
    int r, g, b, a;
}

public class Surface {
    public Vector2 size() {
        return Vector2(width(), height());
    }
    public abstract int width();
    public abstract int height();
}

/** Enthält Bitmap-Daten, Verlustfreie Konvertierung bei Wechsel
 *  der Bit-Tiefe.
 */
public class Image {
    public abstract Surface surface();
}

/** Mutable surface
 */
public class Canvas {
    public void draw(Surface source, Vector2 destPos) {
        draw(source, destPos, Vector2(0, 0), source.size);
    }

    public abstract void draw(Surface source, Vector2 destPos,
        Vector2 sourcePos, Vector2 sourceSize);
    public abstract void drawCircle(Vector2 center, int radius, Color color);
    public abstract void drawFilledCircle(Vector2 center, int radius,
        Color color);
    public abstract void drawLine(Vector2 p1, Vector2 p2, Color color);
    public abstract void drawRect(Vector2 p1, Vector2 p2, Color color);
    public abstract void drawFilledRect(Vector2 p1, Vector2 p2, Color color);

    public abstract Surface surface();
}

struct FontProperties {
    int size = 14;
    Color back = {0,0,0,255};
    Color fore = {255,255,255,255};
}

public class Font {
    public abstract void drawText(Canvas canvas, Vector2 pos, char[] text);
}

/// Information about a key press
public struct KeyInfo {
    Keycode code;
    /// Fully translated according to system keymap
    wchar unicode = '\0';
}

public struct MouseInfo {
    Vector2 pos;
    Vector2 rel;
}

public enum Modifier {
    Alt = 1,
    Control = 2,
    Shift = 4,
}

/// Contains event- and graphics-handling
public class Framework {
    //contains keystate (key down/up) for each key; indexed by Keycode
    private bool mKeyStateMap[];
    private Vector2 mousePos;

    public this() {
        mKeyStateMap = new bool[Keycode.max-Keycode.min+1];
    }

    public abstract void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen);

    public abstract Image loadImage(Stream st);
    public Image loadImage(char[] fileName) {
        return loadImage(new File(fileName,FileMode.In));
    }

    public abstract Font loadFont(Stream str, FontProperties fontProps);

    public abstract Canvas screen();

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

    protected void doUpdateMousePos(Vector2 pos) {
        if (mousePos != pos) {
            MouseInfo infos;
            infos.pos = pos;
            infos.rel = pos - mousePos;
            mousePos = pos;
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
