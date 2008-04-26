module framework.keybindings;

import framework.framework;
import config = utils.configfile;

debug import std.stdio;

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
    //only for readBinding()
    private Key[char[]] mReverseLookup;

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
        mReverseLookup[bind_to] = k;
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
        mReverseLookup.remove(bind);
    }

    /// Return the arguments for the addBinding() call which created "bind".
    /// Return value is false if not found.
    bool readBinding(char[] bind, out Keycode code, out ModifierSet mods) {
        Key* k = bind in mReverseLookup;
        if (!k)
            return false;
        code = k.code;
        mods = cast(ModifierSet)k.required_mods;
        return true;
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

    /// For a given key event (code, mods) check whether a or b wins, and return
    /// the winner. If the event matches neither a nor b, return null. If both
    /// match equally (it's a draw), always return a.
    /// Both a and b can be null, null ones are handled as no-match.
    public static KeyBindings compareBindings(KeyBindings a, KeyBindings b,
        Keycode code, ModifierSet mods)
    {
        int wa = a ? a.checkBinding(code, mods) : -1;
        int wb = b ? b.checkBinding(code, mods) : -1;
        if (wa >= wb && wa >= 0)
            return a;
        else if (wb >= 0)
            return b;
        return null;
    }
    public static KeyBindings compareBindings(KeyBindings a, KeyBindings b,
        KeyInfo info)
    {
        return compareBindings(a, b, info.code, info.mods);
    }
}
