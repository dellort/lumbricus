module framework.i18n;

import framework.filesystem;
import utils.configfile;
import utils.log;
import str = stdx.string;
import utils.misc;
import tango.util.Convert;

//NOTE: because normal varargs suck infinitely in D (you have to deal with
//    _arguments and _argptr), and because it's not simple to convert these
//    args to strings, I converted it to compile-time varargs (it's called
//    tuples). So all many functions are templated!
//    The old version is still in revision 71.
//xxx after r341, I changed most functions to use a char[][] instead of a tuple
//    this could make per-param-formatting less easy (i.e. number formatting)

//translator for root locale file (read-only, use accessor method below)

alias ConfigNode delegate(char[] section, bool asfilename = false,
    bool allowFail = false) ConfigLoaderDg;

private Translator gLocaleRoot;
private ConfigLoaderDg gConfigLoader;
//two-character locale id
public char[] gCurrentLanguage;
//fallback locale, in case the main locale file is not found
public char[] gFallbackLanguage;

private Log log;

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

///Translator
///This is used for every translation and contains an open locale file
///with a specific namespace
///All calls will never fail, but produce "ERROR: missing..." strings
///if anything goes wrong while loading or finding a translation
///Use bindNamespace to get a more specific Translator for a sub-namespace
public class Translator {
    private ConfigNode mNode;
    private bool mErrorString = true;
    private bool mFullIdOnError = false;

    //create translator from i18n subnode
    //note that the node may be null, in which case only error strings
    //will be returned
    private this(ConfigNode node) {
        if (!node)
            log("WARNING: Creating translator with empty node");
        mNode = node;
    }

    ///create a new Translator bound to the specified sub-namespace (relative
    ///to own namespace)
    Translator bindNamespace(char[] namespace) {
        ConfigNode node;
        if (mNode)
            node = mNode.getPath(namespace, false);
        if (!node)
            log("WARNING: Namespace "~namespace~" doesn't exist");
        return new Translator(node);
    }

    ///hack
    char[][] names() {
        char[][] res;
        if (!mNode)
            return null;
        foreach (char[] name, char[] value; mNode) {
            res ~= name;
        }
        return res;
    }

    ///load a language file from a language/locale directory
    ///initI18N() must have been called before
    this(char[] localePath) {
        assert(gCurrentLanguage.length > 0, "Call initI18N() before");
        auto node = localeNodeFromPath(localePath);
        this(node);
    }

    void addLocaleDir(char[] targetId, char[] localePath) {
        ConfigNode newNode = mNode.getSubNode(targetId);
        auto node = localeNodeFromPath(localePath);
        newNode.mixinNode(node);
    }

    private ConfigNode localeNodeFromPath(char[] localePath) {
        char[] localeFile = localePath ~ '/' ~ gCurrentLanguage;
        char[] fallbackFile = localePath ~ '/' ~ gFallbackLanguage;
        ConfigNode node = gConfigLoader(localeFile, false, true);
        if (!node)
            //try fallback
            node = gConfigLoader(fallbackFile, false, true);
        if (!node)
            log("WARNING: Failed to load any locale file from " ~ localePath
                ~ " with language '" ~ gCurrentLanguage ~ "', fallback '"
                ~ gFallbackLanguage ~ "'");
        return node;
    }

    ///argh: before r333, the constructor did exactly this
    ///Create a translator for the current language bound to the namespace ns
    static Translator ByNamespace(char[] ns) {
        return gLocaleRoot.bindNamespace(ns);
    }

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

    ///Translate a text, similar to the _() function.
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
        ConfigNode subnode;
        if (mNode)
            subnode = mNode.getPath(id, false);
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
        return formatfx(text, arguments, argptr);
    }
}

///Init translations.
///localePath: Path in VFS where locale files are stored (<langId>.conf)
///locale-specific files in <localePath>/<langId> will be mounted to root
///A locale file is a ConfigFile with the following format:
///     id1 = "Text {1} with arguments {2}"
///     ...
///     namespace1 {
///         idbla = "..."
///     }
///     ...
///lang: Language identifier.
public void initI18N(char[] localePath, char[] lang, char[] fallbackLang,
    ConfigLoaderDg configLoader)
{
    log = registerLog("i18n");
    gConfigLoader = configLoader;
    gCurrentLanguage = lang;
    gFallbackLanguage = fallbackLang;
    gLocaleRoot = new Translator(localePath);
}

///Translate an ID into text in the selected language.
///Unlike GNU Gettext, this only takes an ID, not an english text.
public char[] _(char[] id, ...) {
    return gLocaleRoot.translatefx(id, _arguments, _argptr);
}
