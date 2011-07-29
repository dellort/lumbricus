module framework.globalsettings;

import framework.config;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.strparser;

private LogStruct!("settings") log;

enum SettingType {
    Unknown,
    String,
    Choice,
    //unranged integer
    Integer,
    //ranged integer (see Setting.choices)
    IntRange,
    //float or int in range [0,100]
    Percent,
}

class Setting {
    string name;
    //should not set directly; use set()
    string value;
    //.type and .choices are just hints (mainly for user interaction)
    SettingType type;
    //depends from .type:
    //  SettingType.Choice: list of possible values
    //  SettingType.IntRange choices[0] = min, choices[1] = max
    string[] choices;
    //called as a setting gets written
    void delegate(Setting s)[] onChange;

    T get(T)(T def = T.init) {
        T res = def;
        tryFromStr!(T)(value, res);
        return res;
    }

    void set(T)(T val) {
        string nv = toStr!(T)(val);
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

Setting findSetting(string name) {
    foreach (s; gSettings) {
        if (s.name == name)
            return s;
    }
    return null;
}

Setting addSetting(T)(string name, T init_val = T.init,
    SettingType t = SettingType.Unknown)
{
    if (findSetting(name))
        throw new Exception("setting '"~name~"' already exists");
    auto s = new Setting;
    s.name = name;
    s.type = t;
    if (t == SettingType.Unknown) {
        //auto-guess a bit
        static if (is(T == string)) {
            s.type = SettingType.String;
        } else static if (is(T == int)) {
            s.type = SettingType.Integer;
        } else static if (is(T == bool)) {
            s.type = SettingType.Choice;
            s.choices = ["false"[], "true"];
        }
    }
    gSettings ~= s;
    setSetting(name, init_val);
    return s;
}

T getSetting(T)(string name, T def = T.init) {
    Setting ps = findSetting(name);
    if (!ps)
        return def;
    return ps.get!(T)(def);
}

//if the setting didn't exist yet, it is added
void setSetting(T)(string name, T value) {
    Setting ps = findSetting(name);
    if (!ps) {
        addSetting!(T)(name, value);
    } else {
        ps.set!(T)(value);
    }
}

void addSettingsStruct(T)(string prefix, T init_val = T.init) {
    T x = init_val;
    enum names = structMemberNames!(T)();
    foreach (int idx, i; x.tupleof) {
        addSetting!(typeof(i))(prefix ~ "." ~ names[idx], i);
    }
}
//NOTE: this is slow because of string memory allocation
T getSettingsStruct(T)(string prefix, T def = T.init) {
    T x = def;
    enum names = structMemberNames!(T)();
    foreach (int idx, i; x.tupleof) {
        x.tupleof[idx] = getSetting!(typeof(i))(prefix ~ "." ~ names[idx], i);
    }
    return x;
}

void settingMakeIntRange(Setting s, int min, int max) {
    argcheck(s.type == SettingType.Integer);
    s.choices = [toStr(min), toStr(max)];
    s.type = SettingType.IntRange;
}

//set the given setting to the next valid value; wrap around if the last valid
//  setting was reached
//this works for SettingType.Choice and SettingType.IntRange
//direction is upwards if dir>=0 or downwards if dir < 0
//set to first choice if current value is invalid (reason: otherwise, using key
//  shortcuts to cycle through values would do nothing => confusion)
//do nothing on other errors
void settingCycle(string name, int dir = +1) {
    Setting s = findSetting(name);
    if (!s)
        return;
    dir = dir >= 0 ? +1 : -1;
    if (s.type == SettingType.Choice) {
        int found = -1;
        foreach (int i, c; s.choices) {
            if (s.value == c) {
                found = i;
                break;
            }
        }
        if (found >= 0) {
            s.set(s.choices[realmod!(size_t)(found + dir, $)]);
        } else if (s.choices.length) {
            s.set(s.choices[0]);
        }
    } else if (s.type == SettingType.IntRange) {
        int min, max;
        if (s.choices.length != 2)
            return;
        if (!(tryFromStr(s.choices[0], min) && tryFromStr(s.choices[1], max)))
            return;
        if (min >= max)
            return;
        int cur = s.get!(int)();
        if (cur < min || cur > max) {
            cur = min;
        } else {
            cur = realmod!(int)(cur + dir - min, max + 1 - min) + min;
        }
        s.set!(int)(cur);
    }
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

    static SettingVar Add(string name, T init_val = T.init) {
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

//helper to show user help string
string settingValueHelp(string setting) {
    string res;
    void write(T...)(string fmt, T args) {
        res ~= myformat(fmt, args) ~ "\n";
    }

    Setting s = findSetting(setting);

    if (!s) {
        write("Unknown setting '%s'!", setting);
        return res;
    }

    write("Possible values for setting '%s':", s.name);

    if (s.type == SettingType.Choice) {
        foreach (c; s.choices) {
            write("   %s", c);
        }
    } else if (s.type == SettingType.String) {
        write("   <any string>");
    } else if (s.type == SettingType.Integer) {
        write("   <integer number>");
    } else if (s.type == SettingType.IntRange) {
        if (s.choices.length == 2) {
            write("   <integer number in range [%s, %s]>", s.choices[0],
                s.choices[1]);
        } else {
            write("   ?");
        }
    } else if (s.type == SettingType.Percent) {
        write("   <number between 0 and 100>");
    } else {
        write("   <unknown>");
    }

    return res;
}

//helpers to load/save to disk

enum cSettingsFile = "settings2.conf";

void loadSettings() {
    log.minor("Loading global settings from %s", cSettingsFile);
    ConfigNode node = loadConfig(cSettingsFile, true);
    if (!node)
        return;
    foreach (ConfigNode sub; node) {
        //if a setting doesn't exist, it will be added (which may or may not
        //  what you want)
        //also, if a value is invalid, the code which needs the setting just has
        //  to deal with it (but it's the same when you e.g. write the setting
        //  from the commandline; but maybe one could provide a validator
        //  callback for settings which want it...?)
        setSetting!(string)(sub.name, sub.value);
    }
}

void saveSettings() {
    log.minor("Saving global settings to %s", cSettingsFile);
    auto n = new ConfigNode();
    foreach (s; gSettings) {
        n[s.name] = s.value;
    }
    saveConfig(n, cSettingsFile);
}
