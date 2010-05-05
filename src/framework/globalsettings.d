module framework.globalsettings;

import framework.config;
import utils.configfile;
import utils.misc;
import utils.strparser;

enum SettingType {
    Unknown,
    String,
    Choice,
    //float or int in range [0,100]
    Percent,
}

class Setting {
    char[] name;
    //should not set directly; use set()
    char[] value;
    //these are just hints (mainly for user interaction)
    SettingType type;
    char[][] choices;
    //called as a setting gets written
    void delegate(Setting s)[] onChange;

    T get(T)(T def = T.init) {
        T res = def;
        tryFromStr!(T)(value, res);
        return res;
    }

    void set(T)(T val) {
        char[] nv = toStr!(T)(val);
        if (nv != value) {
            value = nv;
            changed();
        }
    }

    private void changed() {
        foreach (cb; onChange)
            cb(this);
        foreach (cb; gOnSettingsChange)
            cb(this);
    }
}

//(not using an AA because AA messes up order [xxx does that matter?])
Setting[] gSettings;
//global change handlers; called for any changed property
void delegate(Setting s)[] gOnSettingsChange;

//these callbacks are called on initialization...
//- after all static module ctors have been run
//  (which means you can add callbacks inside module ctors)
//- after directories are "mounted"
void delegate()[] gOnRelistSettings;

void relistAllSettings() {
    foreach (c; gOnRelistSettings) { c(); }
}

Setting findSetting(char[] name) {
    foreach (s; gSettings) {
        if (s.name == name)
            return s;
    }
    return null;
}

Setting addSetting(T)(char[] name, T init_val = T.init,
    SettingType t = SettingType.Unknown)
{
    if (findSetting(name))
        throw new Exception("setting '"~name~"' already exists");
    auto s = new Setting;
    s.name = name;
    s.type = t;
    if (t == SettingType.Unknown) {
        //auto-guess a bit
        static if (is(T == char[])) {
            s.type = SettingType.String;
        } else static if (is(T == bool)) {
            s.type = SettingType.Choice;
            s.choices = ["false"[], "true"];
        }
    }
    gSettings ~= s;
    setSetting(name, init_val);
    return s;
}

T getSetting(T)(char[] name, T def = T.init) {
    Setting ps = findSetting(name);
    if (!ps)
        return def;
    return ps.get!(T)(def);
}

//if the setting didn't exist yet, it is added
void setSetting(T)(char[] name, T value) {
    Setting ps = findSetting(name);
    if (!ps) {
        addSetting!(T)(name, value);
    } else {
        ps.set!(T)(value);
    }
}

void addSettingsStruct(T)(char[] prefix, T init_val = T.init) {
    T x = init_val;
    const names = structMemberNames!(T)();
    foreach (int idx, i; x.tupleof) {
        addSetting!(typeof(i))(prefix ~ "." ~ names[idx], i);
    }
}
//NOTE: this is slow because of string memory allocation
T getSettingsStruct(T)(char[] prefix, T def = T.init) {
    T x = def;
    const names = structMemberNames!(T)();
    foreach (int idx, i; x.tupleof) {
        x.tupleof[idx] = getSetting!(typeof(i))(prefix ~ "." ~ names[idx], i);
    }
    return x;
}

//synchronize a variable with a Setting
//I guess this is only some sort of performance optimization helper
//GuardNan == true => don't accept nan (default/current value is used instead)
//  (if init value is nan, you may still run into trouble)
class SettingVar(T, bool GuardNan = true) {
    private {
        T mVar;
        Setting mSetting;
    }

    this(Setting s) {
        mSetting = s;
        onChange(s);
        mSetting.onChange ~= &onChange;
    }

    static SettingVar Add(char[] name, T init_val = T.init) {
        return new SettingVar(addSetting!(T)(name, init_val));
    }

    private void onChange(Setting s) {
        T r = s.get!(T)(mVar);
        if (GuardNan && r != r)
            return;
        mVar = r;
    }

    Setting setting() {
        return mSetting;
    }

    void set(T t) {
        //onChange callback sets the actual variable
        mSetting.set!(T)(t);
    }
    T get() {
        return mVar;
    }
}

//helpers to load/save to disk

void loadSettings() {
    ConfigNode node = loadConfig("settings2.conf", true, true);
    if (!node)
        return;
    foreach (ConfigNode sub; node) {
        //if a setting doesn't exist, it will be added (which may or may not
        //  what you want)
        //also, if a value is invalid, the code which needs the setting just has
        //  to deal with it (but it's the same when you e.g. write the setting
        //  from the commandline; but maybe one could provide a validator
        //  callback for settings which want it...?)
        setSetting!(char[])(sub.name, sub.value);
    }
}

void saveSettings() {
    auto n = new ConfigNode();
    foreach (s; gSettings) {
        n[s.name] = s.value;
    }
    saveConfig(n, "settings2.conf");
}
