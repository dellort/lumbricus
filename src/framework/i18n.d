module framework.i18n;

import framework.filesystem;
import utils.configfile;
import utils.log;
import stdx.format;
import stdx.string;
import stdx.conv;

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

///Translator
///This is used for every translation and contains an open locale file
///with a specific namespace
///All calls will never fail, but produce "ERROR: missing..." strings
///if anything goes wrong while loading or finding a translation
///Use bindNamespace to get a more specific Translator for a sub-namespace
public class Translator {
    private ConfigNode mNode;
    private bool mErrorString = true;

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

    ///Translate a text, similar to the _() function.
    ///Warning: doesn't do namespace resolution.
    char[] opCall(T...)(char[] id, T t) {
        //convert tuple to string array
        //yes, it's a bit sad; it was soo nice before (r341)
        char[][] bla;
        foreach (y; t) {
            bla ~= format("%s", y);
        }
        return translateWithArray(id, bla);
    }

    private char[] lastId(char[] id) {
        int pos = rfind(id, '.');
        if (pos < 0)
            assert(pos == -1);
        return id[pos+1 .. $];
    }

    char[] translateWithArray(char[] id, char[][] args) {
        ConfigNode subnode;
        if (mNode)
            subnode = mNode.getPath(id, false);
        return DoTranslate(subnode, lastId(id), args);
    }

    /** like translateWithArray, but with multiple-choice based on rnd, e.g.
      id {
          "Option 1"
          "Option 2"
      }
    */
    char[] translateWithArrayMC(char[] id, char[][] args, uint rnd) {
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
        return DoTranslate(subnode, lastId(id), args);
    }

    private char[] DoTranslate(ConfigNode data, char[] id, char[][] t) {
        char[] text;
        if (data)
            text = data.value;
        if (text.length == 0) {
            if (mErrorString)
                text = "ERROR: missing translation for ID '" ~ id ~ "'!";
            else
                text = id;
        }
        return trivialFormat(text, t);
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
public char[] _(T...)(char[] id, T t) {
    return gLocaleRoot(id, t);
}

//possibly replace by tango.text.convert.Layout()
//this once was generic (using tuples); see above
private char[] trivialFormat(char[] text, char[][] t) {
    char[] res;
    while (text.length > 0) {
        int start = find(text, '{');
        if (start >= 0) {
            res ~= text[0 .. start];
            text = text[start+1 .. $];
            int end = find(text, '}');
            if (end < 0) {
                return "ERROR: missing '}' in string '" ~ text ~ "'!";
            }
            char[] formatstr = text[0 .. end];
            text = text[end+1 .. $];
            //interpret format string: currently it contains a number only
            int s;
            try {
                s = toInt(formatstr);
            } catch (ConvError e) {
                return "ERROR: invalid number: '" ~ formatstr ~ "'!";
            }
            if (s < 0 || s >= t.length) {
                return "ERROR: invalid argument number: '" ~ formatstr ~ "'.";
            }

            res ~= t[s];
        } else {
            if (res.length == 0) {
               res = text;
            } else {
                res ~= text;
            }
            text = null;
        }
    }
    return res;
}
