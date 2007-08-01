/// Various types which are commonly needed for event handling...
module framework.event;

import utils.vector2;
import str = std.string;
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

enum KeyEventType {
    Down,
    Up,
    Press
}

/// Information about a key press
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
            cast(dchar)(isPrintable ? unicode : '?'));
    }
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;
}
