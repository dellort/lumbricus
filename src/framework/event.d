/// Various types which are commonly needed for event handling...
module framework.event;

import utils.vector2;
import str = stdx.string;
public import framework.keysyms;

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
/// Call the delegate for each modifier which is set in s.
public void foreachSetModifier(ModifierSet s, void delegate(Modifier m) cb) {
    for (Modifier m = Modifier.min; m <= Modifier.max; m++) {
        if (modifierIsSet(s, m)) cb(m);
    }
}
public bool modifierIsExact(ModifierSet s, Modifier[] mods) {
    ModifierSet flags;
    foreach (ref m; mods) {
        flags += 1<<m;
    }
    return s == flags;
}
public bool modifierIsExact(ModifierSet s, Modifier mod) {
    return s == 1<<mod;
}

enum KeyEventType {
    Down, ///key pressed down
    Up, ///key released
    Press ///triggered on key down; but unlike Down, this is also autorepeated
}

/// Information about a key press, this also covers mouse buttons
public struct KeyInfo {
    /// type of event
    KeyEventType type;
    Keycode code;
    /// Fully translated according to system keymap and modifiers
    dchar unicode = '\0';
    /// set of active modifiers when event was fired
    ModifierSet mods;

    ///if not a control character
    bool isPrintable() {
        return unicode >= 0x20;
    }

    ///if mouse button
    bool isMouseButton() {
        return keycodeIsMouseButton(code);
    }

    bool isPress() {
        return type == KeyEventType.Press;
    }

    ///if type is KeyEventType.Down
    bool isDown() {
        return type == KeyEventType.Down;
    }

    bool isUp() {
        return type == KeyEventType.Up;
    }

    char[] toString() {
        return str.format("[KeyInfo: ev=%s code=%d mods=%d ch='%s']",
            ["down", "up", "press"][type],
            cast(int)code, cast(int)mods,
            isPrintable ? [unicode] : "None");
    }
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;

    char[] toString() {
        return str.format("[MouseInfo: pos=%s rel=%s]", pos, rel);
    }
}

//xxx invent something better, this looks like the very stupid C/SDL way
//  also, this should be strictly about input events, nothing else
//also note that the GUI code needs to copy and modify the mouse positions,
//because mouse positions are Widget-relative, which is why this is a struct
struct InputEvent {
    Vector2i mousePos; //always valid
    bool isKeyEvent;
    bool isMouseEvent;
    KeyInfo keyEvent; //valid if isKeyEvent
    MouseInfo mouseEvent; //valid if isMouseEvent

    //return if this is a mouse move or a mouse click event
    bool isMouseRelated() {
        return isMouseEvent || (isKeyEvent && keyEvent.isMouseButton);
    }

    char[] toString() {
        char[] s;
        if (isKeyEvent)
            s = keyEvent.toString();
        else if (isMouseEvent)
            s = mouseEvent.toString();
        else
            s = "?";
        return "Event " ~ s;
    }
}
