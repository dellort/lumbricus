module framework.i18n;
import utils.configfile;
import std.format;
import std.string;
import std.conv;

private ConfigNode gTranslations;

///Translator
///A module can instantiate this to have a default id-namespace prefix.
public class Translator {
    private ConfigNode subnode;
    private char[] namespace;

    this(char[] namespace) {
        this.namespace = namespace;
        subnode = gTranslations.getPath(namespace, false);
    }

    ///Translate a text, similar to the _() function.
    ///Warning: doesn't do namespace resolution.
    char[] opCall(char[] id, ...) {
        return DoTranslate(subnode, id, _arguments, _argptr);
    }
}

///Init translations.
///translations: A ConfigFile with the following format:
///     langid {
///         id1 = "Text {1} with arguments {2}"
///         ...
///         namespace1 {
///             idbla = "..."
///     ...
///lang: Language identifier.
public void initI18N(ConfigNode translations, char[] lang) {
    auto node = translations.findNode(lang);
    //default to English
    if (!node)
        node = translations.findNode("en");
    gTranslations = node;
}

///Translate an ID into text in the selected language.
///Unlike GNU Gettext, this only takes an ID, not an english text.
public char[] _(char[] id, ...) {
    int pos = rfind(id, '.');
    if (pos < 0)
        assert(pos == -1);
    ConfigNode node;
    if (gTranslations) {
        node = gTranslations.getPath(id[0 .. (pos<0?0:pos)], false);
    }
    return DoTranslate(node, id[pos+1 .. $], _arguments, _argptr);
}

//possibly replace by tango.text.convert.Layout()
private char[] trivialFormat(char[] text, TypeInfo[] arguments, void* argptr) {
    if (arguments.length > 64) {
        return "ERROR: not more than 64 arguments, please.";
    }

    //following 5 lines almost literally copied from Tango!
    void*[64] arglist = void;
    foreach (i, arg; arguments) {
        arglist[i] = argptr;
        argptr += (arg.tsize + int.sizeof - 1) & ~ (int.sizeof - 1);
    }

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
            if (s < 0 || s >= arguments.length) {
                return "ERROR: invalid argument number: '" ~ formatstr ~ "'.";
            }

            void addFormat(dchar c) {
                res ~= c;
            }

            //xxx: this is WRONG
            //it works, but if the argument is a string containing format
            //strings, doFormat() will interpret them.
            //complain at editor of doFormat()
            doFormat(&addFormat, arguments[s..s+1], arglist[s]);
        } else {
            res ~= text;
            text = null;
        }
    }
    return res;
}

private char[] DoTranslate(ConfigNode data, char[] id, TypeInfo[] arguments,
    void* argptr)
{
    char[] text;
    if (data) {
        text = data.getStringValue(id, "");
    }
    if (text.length == 0) {
        text = "ERROR: missing translation for ID '" ~ id ~ "'!";
    }
    return trivialFormat(text, arguments, argptr);
}
