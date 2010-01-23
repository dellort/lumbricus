module gui.styles;

import utils.configfile;
import utils.list2;
import utils.misc;
import utils.mybox;

//doesn't really belong here
import framework.font;
import utils.color;

import tango.core.Array : sort, find;
import arr = utils.array;
import str = utils.string;
import strparser = utils.strparser;


//the abstract interface for reading style properties
//although it contains some not strictly needed utility code
//the idea is that one time, one could implement an alternative system based
//  on scripting or so, and the interface should be forward-compatible
abstract class StylesLookup {
    private {
        //classes for the represented object
        char[][] mSortedClasses;
        //states for the represented object
        bool[char[]] mStates;
        //enabled and sorted states (where mStates is true)
        char[][] mSortedEnabledStates;
    }

    //user can set a callback; the callback will then be called everytime the
    //  value returned by get/getBox possibly has changed
    //void delegate() onChange;
    //using a flag, GUI code becomes easier (doesn't need to be able to handle
    //  change callbacks at any time)
    bool didChange;

    //provides a simplistic way to override a specific property with a
    //  user-defined value
    MyBox delegate(StylesLookup sender, char[] name, MyBox orig)
        onStyleOverride;

    final void triggerChange() {
        //if (onChange)
        //    onChange();
        didChange = true;
    }

    abstract {
        StylesBase parent();
        void parent(StylesBase p);

        //check by polling if there was e.g. a theme change
        void checkChanges();

        //backend function for getBox()
        protected MyBox doGetBox(char[] name);

        //called if the set of classes changed
        //must call triggerChange on its own (if needed)
        protected void changed_classes();

        //must call triggerChange on its own (if needed)
        protected void updateState(char[] name, bool val);
    }

    //treat return value as const etc.
    final char[][] sorted_classes() { return mSortedClasses; }
    final char[][] sorted_enabled_states() { return mSortedEnabledStates; }

    //a StylesLookup can be an instance of multiple styles classes
    //(actually, we don't need that; multiple classes are only used to simulate
    //  single inheritance, sigh.)
    final void addClass(char[] name) {
        //no duplicates
        if (find(mSortedClasses, name) < mSortedClasses.length)
            return;
        mSortedClasses ~= name;
        sort(mSortedClasses);
        changed_classes();
    }

    final void removeClass(char[] name) {
        int idx = find(mSortedClasses, name);
        if (idx == mSortedClasses.length)
            return;
        mSortedClasses = mSortedClasses[0..idx] ~ mSortedClasses[idx+1..$];
        changed_classes();
    }

    final void addClasses(char[][] cls) {
        foreach (char[] n; cls) {
            addClass(n);
        }
    }

    //enable/disable a state; default value for states is false
    //a state isn't declared or so; it just may or may not have influence on
    //  style property values
    final void setState(char[] name, bool val) {
        auto pstate = name in mStates;
        if (pstate && *pstate == val)
            return;
        mStates[name] = val;
        mSortedEnabledStates.length = 0;
        foreach (char[] name, bool value; mStates) {
            if (value)
                mSortedEnabledStates ~= name;
        }
        sort(mSortedEnabledStates);
        updateState(name, val);
    }

    //value for a style property with the given name
    //the style value depends from the theme config file, the enabled/disabled
    //  states, the set of added classes
    final MyBox getBox(char[] name) {
        MyBox val = doGetBox(name);
        if (onStyleOverride)
            val = onStyleOverride(this, name, val);
        return val;
    }

    //return the actual value for a property with the current state
    final T get(T)(char[] name) {
        return getBox(name).unbox!(T)();
    }
}

//per-GUI singleton that contains all style rules
abstract class StylesBase {
    abstract void addRules(ConfigNode rules);
    abstract void clearRules();
}

//---- pseudo css implementation
//as it is now, it's some sort of "uncascading CSS-like property lookup"

private {
    //the parser function turns the string into the value of the actual type and
    //  returns it; the previous value is passed as a box and can be used to do
    //  "relative" values (empty box is passed for top-level ones)
    alias MyBox function(char[], MyBox) ParserFn;
    ParserFn[char[]] gParserFns;
}

class StylesPseudoCSS : StylesBase {
    private {
        //sorted by selector (descending)
        Rule[] mSortedRules;
        //increased on every selector definition
        //used to include definition order into mSortedRules sort order
        int mRuleDeclarationCounter;

        PropertiesSet[] mLoadedProps;

        //incremented everytime rules are added/changed/removed
        //trigger complete reloads
        int mReloadCounter;
    }

    private class Rule {
        char[] name;
        Selector selector;
        //source of the contents, reparsed every time the rule is
        //reevaluated
        ConfigNode contents;

        char[] toString() {
            assert(contents.name == name);
            return myformat("{}: '{}' '{}'", name, selector.toString(),
                contents.value/+writeAsString()+/);
        }
    }

    //full selector; there's also a way to or-combine two selectors, but
    //this is only syntactic sugar for defining two selectors (with same
    //contents), e.g. "a, b" <node> => "a" <node> "b" <node>, so this isn't
    //here.
    private class Selector {
        char[][] sorted_classes;
        char[][] sorted_states;
        int declaration; //sequential declaration number

        this(char[] src, int decl) {
            declaration = decl;
            //a selector is just a sequence of prefixed strings concatenated
            //prefixed are:
            //  $id (only at most one allowed)
            //  /class
            //  :state
            //and as a special case, *
            src = str.strip(src);
            if (src == "*")
                return;
            char[][] segments = str.splitPrefixDelimiters(src,
                ["/", ":"]);
            foreach (s; segments) {
                s = str.strip(s);
                auto rest = str.strip(s[1..$]);
                if (rest == "") {
                    throw new CustomException("not enough text");
                }
                if (s[0] == '/') {
                    sorted_classes ~= rest;
                } else if (s[0] == ':') {
                    sorted_states ~= rest;
                } else {
                    throw new CustomException("unparsable string in selector");
                }
            }
            sort(sorted_classes);
            sort(sorted_states);
        }

        //sort value (higher => more specific, cf. CSS)
        long specificity() {
            long a = sorted_classes.length;
            long b = sorted_states.length;
            long c = declaration;
            assert((a | b) < (1<<8) && c < (1<<16), "static limit lol");
            return (a << 8*4) | (b << 8*3) | c;
        }

        char[] toString() {
            char[] res;
            void addstuff(char[] pref, char[][] arr) {
                foreach (x; arr) {
                    res ~= pref ~ x;
                }
            }
            addstuff("/", sorted_classes);
            addstuff(":", sorted_states);
            if (!(sorted_classes.length | sorted_states.length))
                res ~= "*";
            res ~= myformat(" #{}", declaration);
            return res;
        }
    }


    this() {
    }

    //the rules node contains "selector { rulelist }" entries
    void addRules(ConfigNode rules) {
        foreach (ConfigNode item; rules) {
            auto selectors = parse_selector(item.name);
            //xxx: check if rule names are unique in item node
            foreach (ConfigNode def; item) {
                foreach (sel; selectors) {
                    Rule r = new Rule();
                    r.name = def.name;
                    r.contents = def;
                    r.selector = sel;
                    mSortedRules ~= r;
                }
            }
        }
        sort(mSortedRules, (Rule e1, Rule e2) {
            return e2.selector.specificity < e1.selector.specificity;
        });
        reload();
    }

    private Selector[] parse_selector(char[] selector) {
        Selector[] selectors;
        foreach (s; str.split(selector, ",")) {
            selectors ~= new Selector(s, mRuleDeclarationCounter++);
        }
        return selectors;
    }

    void clearRules() {
        mSortedRules = null;
        mRuleDeclarationCounter = 0;
        reload();
    }

    //clear caches
    private void reload() {
        mReloadCounter++;
        mLoadedProps = null;
    }

    //for debugging
    char[] rulesString() {
        char[] res;
        foreach(r; mSortedRules) {
            res ~= r.toString() ~ "\n";
        }
        return res;
    }

    //used by StylesLookupImpl
    //creates a block of property value for a specific widget class (defined by
    //  the list of classes that a widget is part of)
    private PropertiesSet loadSet(char[][] sorted_classes) {
        foreach (p; mLoadedProps) {
            if (p.mSortedClasses == sorted_classes)
                return p;
        }

        auto res = new PropertiesSet();
        res.mSortedClasses = sorted_classes.dup;

        foreach (r; mSortedRules) {
            if (!arr.arraySortedIsContained(res.mSortedClasses,
                r.selector.sorted_classes))
                continue;
            //create exactly matching PropertiesSet.List for the states
            bool sub_found = false;
            foreach (cur; res.mSortedProperties) {
                if (cur.mSortedStates == r.selector.sorted_states) {
                    sub_found = true;
                    break;
                }
            }
            if (!sub_found) {
                alias PropertiesSet.List L;
                L sub = new L();
                sub.mSortedStates = r.selector.sorted_states;
                //xxx is this sorting correct, does it make sense?
                res.mSortedProperties ~= sub;
                sort(res.mSortedProperties, (L a, L b) {
                    return b.mSortedStates.length < a.mSortedStates.length;
                });
                //all states that can influence property lookup
                foreach (s; sub.mSortedStates) {
                    res.mAllStates[s] = true;
                }
            }
            //write rule value to all states that match
            char[] s = r.contents.getCurValue!(char[])();
            MyBox empty;
            if (!(r.name in gParserFns)) {
                assert(false, "unregged style: "~r.name);
            }
            MyBox val = gParserFns[r.name](s, empty);
            assert(!val.empty());
            foreach (cur; res.mSortedProperties) {
                if (!arr.arraySortedIsContained(cur.mSortedStates,
                    r.selector.sorted_states))
                    continue;
                auto pbox = r.name in cur.mProperties;
                //if already defined, don't overwrite??
                if (!pbox) {
                    cur.mProperties[r.name] = val;
                }
            }
        }

/+
        Trace.formatln("create prop...");
        Trace.formatln("classes: {}", res.mSortedClasses);
        Trace.formatln("all states: {}", res.mAllStates.keys);
        foreach (s; res.mSortedProperties) {
            Trace.formatln("- for states: {}", s.mSortedStates);
            foreach (char[] k, MyBox v; s.mProperties) {
                if (strparser.hasBoxParser(v.type)) {
                    Trace.formatln("  {} = '{}'", k, strparser.boxToString(v));
                } else {
                    Trace.formatln("  {} = ?", k);
                }
            }
        }
+/

        mLoadedProps ~= res;
        return res;
    }

}

//properties for a specific set of classes
//contains all properties for all possible states per class
private class PropertiesSet {
    char[][] mSortedClasses;
    List[] mSortedProperties;
    //all states referenced by mProperties
    //this can be used to check if a state change possibly requires a re-lookup
    bool[char[]] mAllStates;

    //different property lists for each state set
    static class List {
        char[][] mSortedStates;
        //contains all properties that were globally registered
        MyBox[char[]] mProperties;
    }
}

final class StylesLookupImpl : StylesLookup {
    private {
        int mAge = -1;
        StylesPseudoCSS mParent;
        //for the current set of classes
        //if the classes get changed (happens rarely), it must be looked up
        //  again
        PropertiesSet mCurrentSet;
        //if the states get changed, must (possibly) looked up again
        PropertiesSet.List mCurrentList;
    }

    override void parent(StylesBase p) {
        if (mParent is p)
            return;
        mParent = castStrict!(StylesPseudoCSS)(p);
        checkChanges();
    }
    override StylesBase parent() {
        return mParent;
    }

    final void checkChanges() {
        if (mParent && mParent.mReloadCounter == mAge)
            return;
        if (mParent)
            mAge = mParent.mReloadCounter;
        mCurrentSet = null;
        mCurrentList = null;
        triggerChange();
    }

    override MyBox doGetBox(char[] name) {
        checkChanges();
        if (!mParent)
            assert(false, "lookup in unlinked StylesLookupImpl");
        if (!mCurrentSet) {
            assert(!mCurrentList);
            mCurrentSet = mParent.loadSet(sorted_classes());
        }
        if (!mCurrentList) {
            foreach (l; mCurrentSet.mSortedProperties) {
                if (arr.arraySortedIsContained(sorted_enabled_states(),
                    l.mSortedStates))
                {
                    mCurrentList = l;
                    break;
                }
            }
            assert(!!mCurrentList, "this shouldn't happen!");
        }
        auto pprop = name in mCurrentList.mProperties;
        if (!pprop) {
            assert(false, "property '"~name~"' wasn't declared in styles-root?");
        }
        return *pprop;
    }

    override void changed_classes() {
        mAge = -1;
        checkChanges();
    }

    override void updateState(char[] name, bool val) {
        checkChanges();
        if (mCurrentSet && !(name in mCurrentSet.mAllStates))
            return;
        mCurrentList = null;
        triggerChange();
    }
}

MyBox parseString(char[] s, MyBox prev) {
    return MyBox.Box(s);
}

MyBox parseFromStr(T)(char[] s, MyBox prev) {
    return MyBox.Box!(T)(fromStr!(T)(s));
}

MyBox parseColor(char[] s, MyBox prev) {
    Color prevcolor;
    if (!prev.empty())
        prevcolor = prev.unbox!(Color)();
    //xxx: relative color values, e.g. see GTK RC files (shade functions, ...)
    Color c = Color.fromString(s, prevcolor);
    return MyBox.Box(c);
}

//can be used for any type that has opMul / opAdd
//if value definitions start with "+" or "-", the value is added to the parent
//value; if it ends with "%", the number is interpreted as percent value and
//is used with opMul to scale the parent value
//second operand for mul is float, for add it's T
//xxx this sort of stuff would be better handled by a scripting language
MyBox parseFromStrScalar(T)(char[] src, MyBox prev) {
    T prevval;
    if (!prev.empty())
        prevval = prev.unbox!(T)();

    T value = 0;

    if (str.endsWith(src, "%")) {
        float scale = strparser.fromStr!(float)(src[0..$-1]) / 100.0f;
        value = cast(T)(prevval * scale);
    } else {
        bool neg, add;

        if (str.startsWith(src, "+")) {
            src = src[1..$];
            add = true;
        } else if (str.startsWith(src, "-")) {
            src = src[1..$];
            add = true;
            neg = true;
        }

        value = strparser.fromStr!(T)(src);
        if (neg)
            value = -value;
        if (add)
            value = prevval + value;
    }

    return MyBox.Box!(T)(value);
}

MyBox parseFont(char[] src, MyBox prev) {
    FontProperties props;
    if (!prev.empty())
        props = prev.unbox!(FontProperties)();
    props = gFontManager.getStyle(src, false);
    return MyBox.Box!(FontProperties)(props);
}

MyBox parseStrparser(T)(char[] src, MyBox prev) {
    MyBox v = strparser.stringToBox!(T)(src);
    if (v.empty())
        throw new CustomException("can't parse as "~T.stringof~" :"~src);
    return v;
}

//register a style property with the given name and parser function
//see ParserFn for what it does
void styleRegisterValue(char[] name, ParserFn parser) {
    gParserFns[name] = parser;
}

//convencience functions blergh (oh god why)
void styleRegisterInt(char[] name) {
    styleRegisterValue(name, &parseFromStrScalar!(int));
}
void styleRegisterFloat(char[] name) {
    styleRegisterValue(name, &parseFromStrScalar!(float));
}
void styleRegisterString(char[] name) {
    styleRegisterValue(name, &parseString);
}
void styleRegisterColor(char[] name) {
    styleRegisterValue(name, &parseColor);
}
void styleRegisterBool(char[] name) {
    styleRegisterValue(name, &parseFromStr!(bool));
}
void styleRegisterFont(char[] name) {
    styleRegisterValue(name, &parseFont);
}

void styleRegisterStrParser(T)(char[] name) {
    styleRegisterValue(name, &parseStrparser!(T));
}

/+
Basic ideas for property lookup:

http://www.w3.org/TR/CSS21/
http://www.w3.org/TR/CSS21/selector.html
http://www.w3.org/TR/CSS21/cascade.html


Selector strings:
A selector is a string made of a list of items. Each item is prefixed with one
of the following:
- / for a class
- : for a state
After the prefix, the name of the element is followed. The items are simply
concatenated to form the selector string:
    /foo:muh/la /li
Is a selector with the classes foo, la and li, the state muh.
Additionally, several selectors can be or-combined with a ',', and the
definition matches for one of the selectors:
    selector1, selector2, selector3

All property definitions (aka Style.Rule) are ordered by the specificity of
the selector, how the concept works see CSS specification (LOL).

Config-file format:
    styles { //node passed to Styles.addRules()
        //selector string with the syntax mentioned above
        + "/foo :bla" {
            //property name = property definition, passed to StyleValue
            fontsize = "10"
            property2 {
                //StyleValue can also take a subnode
            }
        }
        + "selector2" {
            //...
        }
        //...
    }


+/
