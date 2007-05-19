module framework.i18n;

import utils.configfile;
import std.format;
import std.string;
import std.conv;

//NOTE: because normal varargs suck infinitely in D (you have to deal with
//    _arguments and _argptr), and because it's not simple to convert these
//    args to strings, I converted it to compile-time varargs (it's called
//    tuples). So all many functions are templated!
//    The old version is still in revision 71.

private ConfigNode gTranslations;
public char[] gCurrentLanguage;

///Translator
///A module can instantiate this to have a default id-namespace prefix.
public class Translator {
    private ConfigNode subnode;
    private char[] namespace;

    this(char[] namespace) {
        this.namespace = namespace;
        if (gTranslations)
            subnode = gTranslations.getPath(namespace, false);
    }

    ///Translate a text, similar to the _() function.
    ///Warning: doesn't do namespace resolution.
    char[] opCall(T...)(char[] id, T t) {
        return DoTranslate(subnode, id, t);
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
public void initI18N(ConfigNode node, char[] lang) {
    gCurrentLanguage = lang;
    gTranslations = node;
}

///Translate an ID into text in the selected language.
///Unlike GNU Gettext, this only takes an ID, not an english text.
public char[] _(T...)(char[] id, T t) {
    int pos = rfind(id, '.');
    if (pos < 0)
        assert(pos == -1);
    ConfigNode node;
    if (gTranslations) {
        node = gTranslations.getPath(id[0 .. (pos<0?0:pos)], false);
    }
    return DoTranslate(node, id[pos+1 .. $], t);
}

char[] argToString(T...)(int x, T t) {
    foreach (i, y; t) {
        if (x == i) {
            return format("%s", y);
        }
    }
    return "out of bounds";
}

//possibly replace by tango.text.convert.Layout()
//uh well, if you want a runtime-version of this
//(it's compile-time because it's templated)
private char[] trivialFormat(T...)(char[] text, T t) {
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

	    res ~= argToString(s, t);
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

private char[] DoTranslate(T...)(ConfigNode data, char[] id, T t)
{
    char[] text;
    if (data) {
        text = data.getStringValue(id, "");
    }
    if (text.length == 0) {
        text = "ERROR: missing translation for ID '" ~ id ~ "'!";
    }
    return trivialFormat(text, t);
}
