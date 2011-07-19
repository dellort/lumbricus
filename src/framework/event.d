/// Various types which are commonly needed for event handling...
module framework.event;

import utils.vector2;
import utils.misc : myformat;
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

string modifierToString(Modifier mod) {
    final switch (mod) {
        case Modifier.Alt: return "mod_alt";
        case Modifier.Control: return "mod_ctrl";
        case Modifier.Shift: return "mod_shift";
    }
}

bool stringToModifier(string str, out Modifier mod) {
    switch (str) {
        case "mod_alt": mod = Modifier.Alt; return true;
        case "mod_ctrl": mod = Modifier.Control; return true;
        case "mod_shift": mod = Modifier.Shift; return true;
        default:
    }
    return false;
}

/// translate a Keycode to a OS independent key ID string
/// return null for Keycode.KEY_INVALID
string translateKeycodeToKeyID(Keycode code) {
    foreach (KeycodeToName item; g_keycode_to_name) {
        if (item.code == code) {
            return item.name;
        }
    }
    return null;
}

/// reverse operation of translateKeycodeToKeyID()
Keycode translateKeyIDToKeycode(string keyid) {
    foreach (KeycodeToName item; g_keycode_to_name) {
        if (item.name == keyid) {
            return item.code;
        }
    }
    return Keycode.INVALID;
}

/// Where mod is a Modifier and modifierset is a ModifierSet:
/// bool modifier_active = !!((1<<mod) & modifierset)
/// ("!!" means convert to bool)
alias uint ModifierSet;

public bool modifierIsSet(ModifierSet s, Modifier m) {
    return !!((1<<m) & s);
}
public void modifierSet(ref ModifierSet s, Modifier m) {
    s |= (1<<m);
}
/// Call the delegate for each modifier which is set in s.
public void foreachSetModifier(ModifierSet s, scope void delegate(Modifier m) cb) {
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

/// Information about a key press, this also covers mouse buttons
public struct KeyInfo {
    Keycode code;
    bool isDown;
    /// Fully translated according to system keymap and modifiers
    /// length 0 if no text representation
    string unicode;
    /// set of active modifiers when event was fired
    ModifierSet mods;
    /// whether this event is an artifical one coming from autorepeat
    bool isRepeated;

    ///if not a control character
    bool isPrintable() {
        return unicode.length > 0;
    }

    ///if mouse button
    bool isMouseButton() {
        return keycodeIsMouseButton(code);
    }

    bool isModifierKey() {
        return keycodeIsModifierKey(code);
    }

    ///invariant: isDown != isUp
    bool isUp() {
        return !isDown;
    }

    string toString() {
        string modstr = "[";
        //append all modifiers
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            if ((1<<mod) & mods) {
                modstr ~= myformat("%s ", modifierToString(mod));
            }
        }
        modstr ~= "]";

        return myformat("[KeyInfo: ev=%s code=%s ('%s') mods=%s isRepeated=%s"
            " ch='%s']", isDown ? "down" : "up",
            cast(int)code, translateKeycodeToKeyID(code), modstr, isRepeated,
            isPrintable ? unicode : "None");
    }
}

public struct MouseInfo {
    Vector2i pos;
    Vector2i rel;

    string toString() {
        return myformat("[MouseInfo: pos=%s rel=%s]", pos, rel);
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

    string toString() {
        string s;
        if (isKeyEvent)
            s = keyEvent.toString();
        else if (isMouseEvent)
            s = mouseEvent.toString();
        else
            s = "?";
        return "Event " ~ s;
    }
}
