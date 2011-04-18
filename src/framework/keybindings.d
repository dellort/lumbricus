module framework.keybindings;

import framework.event;
import framework.i18n; //for translate* functions
import framework.keysyms;
import config = utils.configfile;
import utils.log;
import utils.misc;
import utils.vector2;
import str = utils.string;

//describes a key binding
//you can construct one from keyboard input (FromKeyInfo()) and simply compare
//  the result with an existing key binding to see if a key shortcut was hit
struct BindKey {
    Keycode code;
    ModifierSet mods;

    static BindKey FromKeyInfo(KeyInfo info) {
        BindKey k;
        k.code = info.code;
        k.mods = info.mods;
        return k;
    }

    //parse a whitespace separated list of strings into sth. that can be passed
    //  to KeyBindings.addBinding()
    //return success (members are only changed if successful)
    bool parse(string bindstr) {
        BindKey out_bind;
        foreach (string s; str.split(bindstr)) {
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
    string unparse() {
        string[] stuff;
        stuff = [translateKeycodeToKeyID(code)];
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            if (modifierIsSet(mods, mod))
                stuff ~= modifierToString(mod);
        }
        return str.join(stuff, " ");
    }

    string toString() {
        return "[KeyBind "~unparse()~"]";
    }

}

/// Map key combinations to IDs (strings).
public class KeyBindings {
    private struct Entry {
        string bind_to;
        BindKey key;
    }

    private Entry[] mBindings;

    //returns if there's a matching binding
    bool checkBinding(BindKey key) {
        return findBinding(key).length > 0;
    }

    string findBinding(BindKey key) {
        foreach (ref e; mBindings) {
            if (e.key == key)
                return e.bind_to;
        }
        return null;
    }

    string findBinding(KeyInfo info) {
        return findBinding(BindKey.FromKeyInfo(info));
    }

    /// Add a binding.
    bool addBinding(string bind_to, BindKey k) {
        mBindings ~= Entry(bind_to, k);
        return true;
    }

    /// Add a binding (by string).
    bool addBinding(string bind_to, string bindstr) {
        BindKey k;
        if (!k.parse(bindstr))
            return false;
        return addBinding(bind_to, k);
    }

    //wrapper can't deal with overloaded functions (D's fault)
    bool scriptAddBinding(string bind_to, string bindstr) {
        return addBinding(bind_to, bindstr);
    }

    /// Remove all key combinations that map to the binding bind_to.
    void removeBinding(string bind_to) {
    again:
        foreach (int i, Entry e; mBindings) {
            if (e.bind_to == bind_to) {
                mBindings = mBindings[0..i] ~ mBindings[i+1..$];
                goto again;
            }
        }
    }

    /// Return the arguments for the addBinding() call which created bind_to.
    /// Return value is false if not found.
    bool readBinding(string bind_to, out BindKey key) {
        foreach (e; mBindings) {
            if (e.bind_to == bind_to) {
                key = e.key;
                return true;
            }
        }
        return false;
    }

    void clear() {
        mBindings = null;
    }

    void loadFrom(config.ConfigNode node) {
        foreach (config.ConfigNode v; node) {
            string cmd, key;
            if (v.hasNode("cmd")) {
                //xxx with the changes in configfile, this is redundant now
                cmd = v["cmd"];
                key = v["key"];
            } else {
                cmd = v.name;
                key = v.value;
            }
            if (!addBinding(cmd, str.tolower(key))) {
                gLog.error("Could not bind '{}' to '{}' in {}", key, cmd,
                    node.locationString());
            }
        }
    }

    /// Enum all defined bindings.
    /// Caller must not add or remove bindings while enumerating.
    void enumBindings(void delegate(string bind, BindKey k) callback) {
        if (!callback)
            return;

        foreach (Entry e; mBindings) {
            callback(e.bind_to, e.key);
        }
    }
}

Translator localizedKeynames() {
    //NOTE: bindNamespace can't cache Translators on its own, because they are
    //  not stateless for stupid reasons (something with error handling...)
    static Translator gKeynameTranslator;
    if (!gKeynameTranslator)
        gKeynameTranslator = localeRoot.bindNamespace("keynames");
    return gKeynameTranslator;
}

//translate into translated user-readable string
string translateKeyshortcut(BindKey key) {
    auto tl = localizedKeynames();
    string res = tl(translateKeycodeToKeyID(key.code), "?");
    foreachSetModifier(key.mods,
        (Modifier mod) {
            res = tl(modifierToString(mod), "?") ~ "+" ~ res;
        }
    );
    return res;
}

//xxx maybe move to framework
string translateBind(KeyBindings b, string bind) {
    BindKey k;
    if (!b.readBinding(bind, k)) {
        return "-";
    } else {
        return translateKeyshortcut(k);
    }
}
