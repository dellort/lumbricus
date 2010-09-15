module framework.i18n;

import framework.config;
import framework.filesystem;
import framework.globalsettings;
import utils.configfile;
import utils.log;
import utils.misc;
import str = utils.string;
import tango.util.Convert;

//NOTE: because normal varargs suck infinitely in D (you have to deal with
//    _arguments and _argptr), and because it's not simple to convert these
//    args to strings, I converted it to compile-time varargs (it's called
//    tuples). So all many functions are templated!
//    The old version is still in revision 71.
//xxx after r341, I changed most functions to use a char[][] instead of a tuple
//    this could make per-param-formatting less easy (i.e. number formatting)

//translator for root locale file (read-only, use accessor method below)

//two-character locale id
Setting gCurrentLanguage;
//fallback locale, in case the main locale file is not found
char[] gFallbackLanguage;

//called when the language is changed
//xxx GUI could install a property handler, but still need this because the
//  setting change callback is called before the translators are switched to
//  the new language, blergh
public void delegate() gOnChangeLocale;

private {
    Log log;
    bool gInitOnce = false;
    MountId gLocaleMount = MountId.max;
    char[] gActiveLanguage;
    Translator gLocaleRoot;
    ConfigNode gRootNode;

    struct LocaleDir {
        char[] targetId;
        char[] localePath;
    }
    LocaleDir[] gAdditionalDirs;
}

private const cDefLang = "en";

///localePath: Path in VFS where locale files are stored (<langId>.conf)
///locale-specific files in <localePath>/<langId> will be mounted to root
private const cLocalePath = "/locale";

static this() {
    gRootNode = new ConfigNode();
    gLocaleRoot = new Translator("", null);
    log = registerLog("i18n");
    gFallbackLanguage = cDefLang;
    //init value is "", so the GUI can now if the language was not chosen yet
    //the GUI then will annoy the user with a selection dialog
    gCurrentLanguage = addSetting!(char[])("locale", "", SettingType.Choice);
    //NOTE: a settings change handler is installed in initI18N()
    gOnRelistSettings ~= {
        gCurrentLanguage.choices = null;
        scanLocales((char[] id, char[] name1, char[] name2) {
            gCurrentLanguage.choices ~= id;
        });
    };
}

///root translator for config file used with initI18N
public Translator localeRoot() {
    return gLocaleRoot;
}

///description goes here (actually, I don't know what this is supposed to be)
///this could become more complex, e.g. think about "collect_item" in crate.d,
///where I currently translate the weapon name on server side
struct LocalizedMessage {
    char[] id;      ///translation ID
    char[][] args;  ///arguments for translation string
    uint rnd;       ///value for randomized selection of translations
}

private ConfigNode findNamespaceNode(ConfigNode rel, char[] idpath) {
    return rel.getPath(idpath, true);
}

private ConfigNode loadLocaleNodeFromPath(char[] localePath) {
    char[] localeFile = localePath ~ '/' ~ gActiveLanguage ~ ".conf";
    char[] fallbackFile = localePath ~ '/' ~ gFallbackLanguage ~ ".conf";
    ConfigNode node = loadConfig(localeFile, true);
    if (!node)
        //try fallback
        node = loadConfig(fallbackFile, true);
    if (!node) {
        log.warn("Failed to load any locale file from " ~ localePath
            ~ " with language '" ~ gActiveLanguage ~ "', fallback '"
            ~ gFallbackLanguage ~ "'");
        //dummy node; never return null
        node = new ConfigNode();
    }
    return node;
}

void addLocaleDir(char[] targetId, char[] localePath) {
    foreach (ref d; gAdditionalDirs) {
        if (d.localePath == localePath) {
            //already added
            return;
        }
    }
    //store for a later reinit call
    auto dir = LocaleDir(targetId, localePath);
    gAdditionalDirs ~= dir;
    reloadLocaleDir(dir);
}

private void reloadLocaleDir(LocaleDir dir) {
    ConfigNode newNode = findNamespaceNode(gRootNode, dir.targetId);
    assert(!!newNode);
    auto node = loadLocaleNodeFromPath(dir.localePath);
    newNode.mixinNode(node);
}

///Translator
///This is used for every translation and contains an open locale file
///with a specific namespace
///All calls will never fail, but produce "ERROR: missing..." strings
///if anything goes wrong while loading or finding a translation
///Use bindNamespace to get a more specific Translator for a sub-namespace
public class Translator {
    private {
        bool mErrorString = true;
        bool mFullIdOnError = false;
        char[] mSubNs;
    }

    private this() {
    }

    ///create translator from i18n subnode
    ///note that the node may be null, in which case only error strings
    ///will be returned
    ///bindNamespace() is a shortcut for this
    private this(char[] namespace, Translator parent) {
        if (parent) {
            char[] pns = parent.fullNamespace();
            //don't ask me why the length check is needed
            if (pns.length)
                namespace = pns ~ "." ~ namespace;
        }
        mSubNs = namespace;
    }

    ///create a new Translator bound to the specified sub-namespace (relative
    ///to own namespace)
    Translator bindNamespace(char[] namespace) {
        return new Translator(namespace, this);
    }

    char[] fullNamespace() {
        return mSubNs;
    }

    //may return null
    private ConfigNode node() {
        //NOTE: can't cache the per-namespace confignode, because the
        //  ConfigNode reference gets invalid when locales are reloaded
        //possible alternative: keep a global list of all translators ever
        //  created, and loop over them as locales get reloaded (to keep memory
        //  usage bounded, one could cache exactly one Translator for each
        //  namespace, i.e. cache Translator instances)
        return findNamespaceNode(gRootNode, mSubNs);
    }

    ///hack
    char[][] names() {
        char[][] res;
        auto subnode = node();
        if (!subnode)
            return null;
        foreach (char[] name, char[] value; subnode) {
            res ~= name;
        }
        return res;
    }

    //--- the following two properties are only used by dark corners of the GUI

    ///true (default): return an error string if no translation was found
    ///false: return the id if no translation was found
    bool errorString() {
        return mErrorString;
    }
    void errorString(bool e) {
        mErrorString = e;
    }

    bool fullIdOnError() {
        return mFullIdOnError;
    }
    void fullIdOnError(bool f) {
        mFullIdOnError = f;
    }

    ///Translate a text, similar to the translate() function.
    ///Warning: doesn't do namespace resolution.
    char[] opCall(char[] id, ...) {
        return translatefx(id, _arguments, _argptr);
    }

    private char[] lastId(char[] id) {
        int pos = str.rfind(id, '.');
        if (pos < 0)
            assert(pos == -1);
        return id[pos+1 .. $];
    }

    private char[] errorId(char[] id) {
        return mFullIdOnError?id:lastId(id);
    }

    template Tuple(T...) {
        alias T Tuple;
    }

    //generate a tuple than contains T Repeat-times
    //e.g. GenTuple!(int, 3) => Tuple!(int, int, int)
    template GenTuple(T, uint Repeat) {
        static if (Repeat > 0) {
            alias Tuple!(T, GenTuple!(T, Repeat-1)) GenTuple;
        } else {
            alias T GenTuple;
        }
    }

    /** Pass arguments as char[][] instead of vararg
     * msg.rnd = random value for multiple choice values, like:
     *  id {
     *     "Option 1"
     *     "Option 2"
     * }
     */
    char[] translateLocalizedMessage(LocalizedMessage msg) {
        //basically, this generates 10 function calls to tovararg()
        //it copies all elements from the array into p, and then expands p as
        // arguments for tovararg()
        //at runtime, the function with the correct number of params is called
        const cMaxParam = 10;
        alias GenTuple!(char[], cMaxParam) Params;
        Params p;
        if (msg.args.length > p.length) {
            assert(false, "increase cMaxParam in i18n.d");
        }
        char[] tovararg(...) {
            return translatefx(msg.id, _arguments, _argptr, msg.rnd);
        }
        foreach (int i, x; p) {
            if (i == msg.args.length) {
                return tovararg(p[0..i]);
            }
            char[] s = msg.args[i];
            //prefix arguments with _ to translate them too (e.g. _messageid)
            if (s.length > 1 && s[0] == '_') {
                s = opCall(s[1..$]);
            }
            p[i] = s;
        }
        assert(false);
    }

    ///returns true if the passed id is available
    bool hasId(char[] id) {
        auto subnode = node();
        return subnode && subnode.getPath(id, false);
    }

    //like formatfx, only the format string is loaded by id
    private char[] translatefx(char[] id, TypeInfo[] arguments,
        va_list argptr, uint rnd = 0)
    {
        if (id.length > 0 && id[0] == '.') {
            //prefix the id with a . to translate in gLocaleRoot
            return gLocaleRoot.translatefx(id[1..$], arguments, argptr, rnd);
        }
        //empty id, empty result
        if (id.length == 0)
            return "";
        ConfigNode subnode = node();
        //Trace.formatln("{} '{}'", subnode.locationString(), id);
        if (subnode)
            subnode = findNamespaceNode(subnode, id);
        if (subnode && subnode.count > 0) {
            //if the node was found and contains multiple values, select one
            rnd = rnd % subnode.count;
            uint curIdx = 0;
            foreach (ConfigNode node; subnode) {
                if (curIdx == rnd) {
                    subnode = node;
                    break;
                }
                curIdx++;
            }
        }
        return DoTranslate(subnode, errorId(id), arguments, argptr);
    }

    private char[] DoTranslate(ConfigNode data, char[] id,
        TypeInfo[] arguments, va_list argptr)
    {
        char[] text;
        if (data)
            text = data.value;
        if (text.length == 0) {
            if (mErrorString)
                text = "ERROR: missing translation for ID '" ~ id ~ "'!";
            else
                text = id;
        }
        //seems that tango formatting can't handle that case
        if (text.length == 0)
            return "";
        return myformat_fx(text, arguments, argptr);
    }
}

//search locale directory for translation files (<lang>.conf)
//  e.g. cb("de", "German", "Deutsch")
void scanLocales(void delegate(char[] id, char[] name_en, char[] name_loc) cb) {
    gFS.listdir("/locale/", "*.conf", false, (char[] filename) {
        const trail = ".conf";
        if (!str.endsWith(filename, trail))
            return true;
        auto node = loadConfig(cLocalePath ~ '/' ~ filename, true);
        if (node) {
            char[] name_en = node["langname_en"];
            char[] name_loc = node["langname_local"];
            char[] id = filename[0..$-trail.length];
            cb(id, name_en, name_loc);
        }
        return true;
    });
}

///Init translations.
///A locale file is a ConfigFile with the following format:
///     id1 = "Text {1} with arguments {2}"
///     ...
///     namespace1 {
///         idbla = "..."
///     }
///     ...
///um, and I guess it tries to load /locale/<current_lang>.conf
///set the language using gCurrentLanguage, and it will be automatically
/// reinitialized - this is only to force reinitialization (e.g. after you
//  mounted new locale directories)
public void initI18N() {
    if (!gInitOnce) {
        gInitOnce = true;
        gCurrentLanguage.onChange ~= delegate(Setting g) { initI18N(); };
    }

    char[] lang = gCurrentLanguage.value;

    gActiveLanguage = lang;

    //xxx do we need this?
    //apparently the idea was that you could load locale specific images etc.
    //  as well, but it isn't needed for the normal translation mechanism
    //disabled for now
    /+
    try {
        //link locale-specific files into root
        gFS.unmount(gLocaleMount);
        gLocaleMount = gFS.link(cLocalePath ~ '/' ~ lang,"/",false,1);
    } catch (FilesystemException e) {
        //don't crash if current locale has no locale-specific files
        log("catched {}", e);
    }
    +/

    //reloading process:
    //1. clear root node
    //2. re-read all directories and mix them into the root node
    gRootNode.clear();
    //main locale file
    reloadLocaleDir(LocaleDir("", cLocalePath));
    //additional locale files, like for weapon names in weapon plugins
    foreach (d; gAdditionalDirs) {
        reloadLocaleDir(d);
    }

    if (gOnChangeLocale)
        gOnChangeLocale();
}

///Translate an ID into text in the selected language.
///Unlike GNU Gettext, this only takes an ID, not an english text.
public char[] translate(char[] id, ...) {
    return gLocaleRoot.translatefx(id, _arguments, _argptr);
}
