module framework.keybindings;

import framework.keysyms;
import framework.event;
import config = utils.configfile;
import utils.misc;
import utils.vector2;
import str = utils.string;

//describes a key binding
struct BindKey {
    Keycode code;
    ModifierSet mods;

    static BindKey fromKeyInfo(KeyInfo info) {
        BindKey k;
        k.code = info.code;
        k.mods = info.mods;
        return k;
    }

    //parse a whitespace separated list of strings into sth. that can be passed
    //  to KeyBindings.addBinding()
    //return success (members are only changed if successful)
    bool parse(char[] bindstr) {
        BindKey out_bind;
        foreach (char[] s; str.split(bindstr)) {
            Modifier mod;
            if (stringToModifier(s, mod)) {
                out_bind.mods |= (1<<mod);
            } else {
                if (out_bind.code != Keycode.INVALID)
                    break;
                out_bind.code = translateKeyIDToKeycode(s);
                if (out_bind.code == Keycode.INVALID)
                    break;
            }
        }
        bool success = (out_bind.code != Keycode.INVALID);
        if (success)
            *this = out_bind;
        return success;
    }

    //undo parse(), return bindstr
    char[] unparse() {
        char[][] stuff;
        stuff = [translateKeycodeToKeyID(code)];
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            if (modifierIsSet(mods, mod))
                stuff ~= modifierToString(mod);
        }
        return str.join(stuff, " ");
    }

}

/// Map key combinations to IDs (strings).
public class KeyBindings {
    private struct Entry {
        char[] bound_to;
        uint required_mods;
    }

    private Entry[BindKey] mBindings;
    //only for readBinding()
    private BindKey[char[]] mReverseLookup;

    private uint countmods(uint mods) {
        uint sum = 0;
        for (int n = Modifier.min; n <= Modifier.max; n++) {
            sum += !!(mods & (1 << n));
        }
        return sum;
    }

    //find the key which matches with the _most_ modifiers
    //to do that, try with all permutations (across active mods) :/
    private Entry* doFindBinding(BindKey bind, uint mods, uint pos = 0) {
        if (!(mods & (1<<pos))) {
            pos++;
            if (pos > Modifier.max) {
                //recursion end
                BindKey k = bind;
                k.mods = mods;
                return k in mBindings;
            }
        }
        //bit is set at this position...
        //try recursively with and without that bit set
        Entry* e1 = doFindBinding(bind, mods & ~(1<<pos), pos+1);
        Entry* e2 = doFindBinding(bind, mods, pos+1);

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
    int checkBinding(BindKey key) {
        Entry* e = doFindBinding(key, key.mods);
        if (!e) {
            return -1;
        } else {
            return countmods(e.required_mods);
        }
    }

    char[] findBinding(BindKey key) {
        Entry* e = doFindBinding(key, key.mods);
        if (!e) {
            return null;
        } else {
            return e.bound_to;
        }
    }

    char[] findBinding(KeyInfo info) {
        return findBinding(BindKey.fromKeyInfo(info));
    }

    /// Add a binding.
    bool addBinding(char[] bind_to, BindKey k) {
        Entry e;
        e.bound_to = bind_to;
        e.required_mods = k.mods;;

        mBindings[k] = e;
        mReverseLookup[bind_to] = k;
        return true;
    }

    /// Add a binding (by string).
    bool addBinding(char[] bind_to, char[] bindstr) {
        BindKey k;
        if (!k.parse(bindstr))
            return false;
        return addBinding(bind_to, k);
    }

    /// Remove all key combinations that map to the binding "bind".
    void removeBinding(char[] bind) {
        //hm...
        BindKey[] keys;
        foreach (BindKey k, Entry e; mBindings) {
            if (bind == e.bound_to)
                keys ~= k;
        }
        foreach (BindKey k; keys) {
            mBindings.remove(k);
        }
        mReverseLookup.remove(bind);
    }

    /// Return the arguments for the addBinding() call which created "bind".
    /// Return value is false if not found.
    bool readBinding(char[] bind, out BindKey key) {
        BindKey* k = bind in mReverseLookup;
        if (!k)
            return false;
        key = *k;
        return true;
    }

    void clear() {
        mBindings = null;
        mReverseLookup = null;
    }

    void loadFrom(config.ConfigNode node) {
        foreach (config.ConfigNode v; node) {
            char[] cmd, key;
            if (v.hasNode("cmd")) {
                //xxx with the changes in configfile, this is redundant now
                cmd = v["cmd"];
                key = v["key"];
            } else {
                cmd = v.name;
                key = v.value;
            }
            if (!addBinding(cmd, str.tolower(key))) {
                debug Trace.formatln("could not bind '{}' '{}'", cmd, key);
            }
        }
    }

    /// Enum all defined bindings.
    /// Caller must not add or remove bindings while enumerating.
    void enumBindings(void delegate(char[] bind, BindKey k) callback) {
        if (!callback)
            return;

        foreach (BindKey k, Entry e; mBindings) {
            callback(e.bound_to, k);
        }
    }

    /// For a given key event (code, mods) check whether a or b wins, and return
    /// the winner. If the event matches neither a nor b, return null. If both
    /// match equally (it's a draw), always return a.
    /// Both a and b can be null, null ones are handled as no-match.
    static KeyBindings compareBindings(KeyBindings a, KeyBindings b,
        BindKey key)
    {
        int wa = a ? a.checkBinding(key) : -1;
        int wb = b ? b.checkBinding(key) : -1;
        if (wa >= wb && wa >= 0)
            return a;
        else if (wb >= 0)
            return b;
        return null;
    }
}
