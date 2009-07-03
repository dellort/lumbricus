module gui.styles;

import utils.configfile;
import utils.factory;
import strparser = utils.strparser;
import utils.list2;
import utils.misc;
import utils.mybox;

//doesn't really belong here
import utils.color : Color;

import tango.core.Array : sort, find;
import str = utils.string;

alias StaticFactory!("style_values", StyleValue, Styles, char[], ConfigNode)
    StyleValueFactory;

/+
Some useless documentation.

http://www.w3.org/TR/CSS21/
http://www.w3.org/TR/CSS21/selector.html
http://www.w3.org/TR/CSS21/cascade.html

Styles can be compared to CSS from HTML (how properties are defined, not the
formatting abilities).
A style is a named property with a type, a selector, and a property definition.
- the name defines the meaning of the property (e.g. 'fontsize')
- the type is what the property returns (int for fontsize)
- the selector defines which elements are affected by the property, e.g. there
  can be several elements with different font sizes
- the property definition sets the value of the property; at least for now,
  this can be either an absolute value, or a value relative to the preceeding
  element
The class Styles contains a collection of styles, and Styles classes are ordered
hierarchically. At the top, there's a global Styles class which (probably) will
be used to set the GUI theme, and on the bottom there are Styles classes for
individual widgets. Styles in the bottom override/are based on styles from the
top.

The GUI will have one Styles instance per Widget, and with each instance, some
properties can be associated:
- ID (name) of the element (Styles.id())
- class tags (Styles.addClasses(classes))
- a number of boolean states (Styles.setState(name, state))
Styles definitions are tagged with a selector. The element must have all classes
and active states of the selector to match. If the selector defines an ID, the
element must have the same ID as the selector.

The actual functionality is to get a property value by calling:
    int val = style.getValue!(int)("some_int_property");

Selector strings:
A selector is a string made of a list of items. Each item is prefixed with one
of the following:
- $ for the element name
- / for a class
- : for a state
After the prefix, the name of the element is followed. The items are simply
concatenated to form the selector string:
    /foo$bla:muh/la /li
Is a selector with the classes foo, la and li, the state muh, and the id bla.
Additionally, several selectors can be or-combined with a ',', and the
definition matches for one of the selectors:
    selector1, selector2, selector3

All property definitions (aka Style.Rule) are ordered by the specificity of
the selector, how the concept works see CSS specification (LOL).

Config-file format:
    styles { //node passed to Styles.addRules()
        //selector string with the syntax mentioned above
        "/foo $bla" {
            //property name = property definition, passed to StyleValue
            fontsize = "10"
            property2 {
                //StyleValue can also take a subnode
            }
        }
        "selector2" {
            //...
        }
        //...
    }

Resolving a value:
- start in the Styles class on which getValue was called
- go through the (sorted!) list of the locally defined rules
- if any rule matches, calculate the value using its attached property
  definition and return the value
- if none found, continue searching the rules in the parent
  important: the state of the first Styles instance is used, and not the one
    from the parent (id, classes and states are all taken into account)
- if still none found... assertion failed

Inheritance of values:
- absolute values never depend from other values
- relative values can depend from the value of the same property of the parent
  Styles instance; the value is simply
    parent_styles.getValue!(SameType)(samepropertyname)

+/

/// This manages both stand-alone styles and entities, which use styles. If you
/// want to use the ID, classes or states stuff (basically anything, that makes
/// the styles useful), you have to instantiate an own Styles class, even if
/// you don't to define your own element specific styles.
class Styles {
    private {
        Styles mParent;
        List2!(Styles) mChildren;

        //element ID for the represented object
        char[] mElementID; //=="" if none (matches all)
        //classes for the represented object
        char[][] mSortedClasses;
        //states for the represented object
        bool[char[]] mStates;
        //enabled and sorted states (where mStates is true)
        char[][] mSortedEnabledStates;

        //sorted by selector (descending)
        Rule[] mSortedRules;
        //increased on every selector definition
        //used to include definition order into mSortedRules sort order
        int mRuleDeclarationCounter;

        //last lookups, can even reference objects from the parent style
        StyleValue[char[]] mCachedValues;

        //incremented by did_change()
        long mChangeTimestamp;

        class Rule {
            char[] name;
            Selector selector;
            //source of the contents, reparsed every time the rule is
            //reevaluated
            ConfigNode contents;
            //lazily instantiated
            //the object is kept to make frequent state changes GC friendlier
            StyleValue cached_value;

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
        class Selector {
            char[] id; //=="" if none (=> match all)
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
                char[][] segments = splitPrefixDelimiters(src, ["$", "/", ":"]);
                foreach (s; segments) {
                    s = str.strip(s);
                    auto rest = str.strip(s[1..$]);
                    if (rest == "") {
                        throw new Exception("not enough text");
                    }
                    if (s[0] == '$') {
                        if (id.length > 0)
                            throw new Exception("more than one # in selector");
                        id = rest;
                    } else if (s[0] == '/') {
                        sorted_classes ~= rest;
                    } else if (s[0] == ':') {
                        sorted_states ~= rest;
                    } else {
                        throw new Exception("unparsable string in selector");
                    }
                }
                sort(sorted_classes);
                sort(sorted_states);
            }

            //sort value (higher => more specific, cf. CSS)
            long specificity() {
                long a = id.length > 0;
                long b = sorted_classes.length;
                long c = sorted_states.length;
                long d = declaration;
                assert((b | c) < (1<<8) && d < (1<<16), "static limit lol");
                return (a << 8*4) | (b << 8*3) | (c << 8*2) | d;
            }

            //check if selector matches with current Styles state
            //checking the property name is handled elsewhere
            bool match(Styles element) {
                //if the selector has an ID, always compare
                if (id.length && id != element.mElementID)
                    return false;
                //classes and states match in the same way
                //all items in the selector must be present in the element
                return sorted_array_is_contained(element.mSortedClasses,
                        sorted_classes)
                    && sorted_array_is_contained(element.mSortedEnabledStates,
                        sorted_states);
            }

            char[] toString() {
                char[] res;
                void addstuff(char[] pref, char[][] arr) {
                    foreach (x; arr) {
                        res ~= pref ~ x;
                    }
                }
                addstuff("$", id.length ? [id] : []);
                addstuff("/", sorted_classes);
                addstuff(":", sorted_states);
                if (!(id.length | sorted_classes.length | sorted_states.length))
                    res ~= "*";
                res ~= myformat(" #{}", declaration);
                return res;
            }
        }
    }

    this() {
        mChildren = new typeof(mChildren);
        did_change();
    }

    //called after anything possibly changed (even called on state changes,
    //which might happen very frequently)
    private void did_change() {
        mChangeTimestamp++;
        //propagate down so that inherited values are rechecked and updated
        foreach (c; mChildren) {
            c.did_change();
        }
        //this sucks a bit
        //and don't remove the AA entries to avoids memory trashing on updates
        foreach (ref StyleValue v; mCachedValues) {
            v = null;
        }
    }

    Styles parent() {
        return mParent;
    }
    void parent(Styles new_parent) {
        if (mParent is new_parent)
            return;
        if (mParent) {
            mParent.mChildren.remove(this);
        }
        mParent = new_parent;
        if (mParent) {
            mParent.mChildren.add(this);
        }
        did_change();
    }

    //the rules node contains "selector { rulelist }" entries
    void addRules(ConfigNode rules) {
        foreach (ConfigNode item; rules) {
            char[] selector = item.name;
            Selector[] selectors;
            foreach (s; str.split(selector, ",")) {
                selectors ~= new Selector(s, mRuleDeclarationCounter++);
            }
            foreach (ConfigNode def; item) {
                //xxx: check if rule names are unique in item node
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
        did_change();
    }

    //for debugging
    char[] rulesString() {
        char[] res;
        foreach(r; mSortedRules) {
            res ~= r.toString() ~ "\n";
        }
        return res;
    }
    char[] statesString() {
        return myformat("id='{}' classes={} states={}", id(), mSortedClasses,
            mSortedEnabledStates);
    }

    ///The ID is an (unique, although not enfocred) name for the element managed
    ///by this Styles object. Empty string "" for no name.
    void id(char[] set) {
        mElementID = set;
        did_change();
    }
    char[] id() {
        return mElementID;
    }

    ///The classes define the type of the element (or rather aspects of element,
    ///becauses an element can be part of mutiple classes).
    void addClasses(char[][] cls) {
        foreach (char[] n; cls) {
            addClass(n);
        }
    }
    void addClass(char[] cls) {
        //no duplicates
        if (find(mSortedClasses, cls) >= mSortedClasses.length) {
            mSortedClasses ~= cls;
        }
        sort(mSortedClasses);
        did_change();
    }
    void setClasses(char[][] cls) {
        mSortedClasses = null;
        addClasses(cls);
    }
    void removeClass(char[] cls) {
        int idx = find(mSortedClasses, cls);
        if (idx == mSortedClasses.length)
            return;
        mSortedClasses = mSortedClasses[0..idx] ~ mSortedClasses[idx+1..$];
        did_change();
    }

    ///States are like classes, but more dynamic and can be enabled/disabled
    ///frequently.
    //(xxx: lol the only actual difference to classes is the selectivity of the
    //      rules, is that important?)
    void setState(char[] name, bool value) {
        bool* pv = name in mStates;
        if (pv ? *pv == value : !value)
            return;
        //state change
        mStates[name] = value;
        mSortedEnabledStates.length = 0;
        foreach (char[] name, bool value; mStates) {
            if (value)
                mSortedEnabledStates ~= name;
        }
        sort(mSortedEnabledStates);
        did_change();
    }

    private Rule findPropertyRule(Styles caller, char[] name) {
        Rule winner;
        foreach (Rule r; mSortedRules) {
            if (r.name != name)
                continue;
            if (r.selector.match(caller)) {
                winner = r;
                break;
            }
        }
        //like in CSS: if the style was defined locally and matches, it always
        //  wins over the global styles
        if (winner)
            return winner;
        //ask parent
        if (mParent)
            winner = mParent.findPropertyRule(caller, name);
        if (!winner) {
            //what to do? the property was never defined
        }
        return winner;
    }

    //warning: the StyleValue instance for a property might change randomly
    //         this is mostly because I didn't want to create a new instance
    //         for each widget/property pair
    private StyleValue getValueObject(char[] name) {
        auto pval = name in mCachedValues;
        StyleValue res;
        if (pval) {
            res = *pval; //can be null too
        }
        if (!res) {
            //new lookup
            Rule r = findPropertyRule(this, name);
            if (!r) {
                //no matching rule
                assert(false, "no matching rule for: "~name);
            }
            if (!r.cached_value) {
                //new value
                r.cached_value = StyleValueFactory.instantiate(name, this,
                    r.name, r.contents);
            }
            res = r.cached_value;
        }
        //lazy check for changes, possibly update value (but not necessarily)
        res.check_update();
        //res object changed => update cache
        if (!pval || *pval !is res)
            mCachedValues[name] = res;
        return res;
    }

    //return the actual value for a property with the current state
    T getValue(T)(char[] name) {
        auto obj = getValueObject(name);
        assert(!!obj);
        StyleValueT!(T) t = cast(StyleValueT!(T))obj;
        if (t) {
            return t.value;
        } else {
            return t.boxedValue().unbox!(T)();
        }
    }

    MyBox getValueBox(char[] name) {
        auto obj = getValueObject(name);
        assert(!!obj);
        return obj.boxedValue();
    }
}

/// Single value of a property in a specific context.
/// This is always type dependent, and the type specific parts are handled by
/// inheritance.
/// Warning: the user must not used the value object directly, instead he must
///          use Styles.getValue()/getValueBox()
///          reason: depending from the current state, different StyleValue
///          instances might be used, and calling boxedValue()/value() doesn't
///          automatically update the value after state changes
class StyleValue {
    private {
        char[] mName;
        Styles mOwner;
        //change counter from mOwner
        //note that this counter also changes
        long mChangeTimestamp;
        bool mInitialized;
    }

    protected ConfigNode mDefinition;
    //can be set in the constructor to indicate if the value definition depends
    //from the parent... return value must remain constant after the ctor
    protected bool mDependsFromParent;

    this(Styles a_owner, char[] a_name, ConfigNode a_definition) {
        mOwner = a_owner;
        mName = a_name;
        mDefinition = a_definition;
    }

    char[] name() {
        return mName;
    }

    private void check_update() {
        if (mChangeTimestamp == mOwner.mChangeTimestamp)
            return;
        mChangeTimestamp = mOwner.mChangeTimestamp;
        //a StyleValue is always bound to a specific value definition
        //this means if it's not relative, it doesn't depend from anything but
        //the definition, and it is constant
        if (mInitialized && !mDependsFromParent)
            return;
        do_update();
        mInitialized = true;
    }

    protected abstract void do_update();
    abstract MyBox boxedValue();
}

//base class for actual (derived) handler classes
//for some types, this class might be all what is needed
class StyleValueT(T) : StyleValue {
    private {
        T mTheValue;
    }

    //can be read by calculate_value() is mDependsFromParent is true
    protected T mParentValue;

    this(Styles a_owner, char[] a_name, ConfigNode a_definition) {
        super(a_owner, a_name, a_definition);
    }

    T value() {
        //could call check_update() here, but this actually doesn't make sense;
        //the StyleValue instance could change depending from state anyway, and
        //the user is forced to use Styles.getValue()
        return mTheValue;
    }

    override void do_update() {
        if (mDependsFromParent) {
            //xxx: could check if the value has actually changed
            Styles p = mOwner.parent;
            if (p) {
                mParentValue = p.getValue!(T)(name);
            } else {
                T ini;
                mParentValue = ini;
            }
        }
        mTheValue = calculate_value();
    }

    //produce value from the config node
    //by default: read a string and parse it with strparser
    //if mDependsFromParent is true, mParentValue is valid
    protected T calculate_value() {
        return strparser.stringToType!(T)(mDefinition.value);
    }

    MyBox boxedValue() {
        return MyBox.Box!(T)(value);
    }
}

//can be used for any type that has opMul / opAdd
//if value definitions start with "+" or "-", the value is added to the parent
//value; if it ends with "%", the number is interpreted as percent value and
//is used with opMul to scale the parent value
//second operand for mul is float, for add it's T
class StyleValueScalar(T, bool mul = true, bool add = true) : StyleValueT!(T) {
    private {
        T mConstant;
        float scale;
        bool do_mul, do_add;
    }

    this(Styles a_owner, char[] a_name, ConfigNode a_definition) {
        super(a_owner, a_name, a_definition);

        if (mDefinition.first)
            throw new Exception("unused subnodes");
        parse(mDefinition.value);
        mDependsFromParent = do_mul || do_add;
    }

    private void parse(char[] src) {
        static if (mul) {
            if (str.endsWith(src, "%")) {
                do_mul = true;
                scale = strparser.stringToType!(float)(src[0..$-1]) / 100.0f;
                return;
            }
        }
        bool neg;
        static if (add) {
            if (str.startsWith(src, "+")) {
                src = src[1..$];
                do_add = true;
            } else if (str.startsWith(src, "-")) {
                src = src[1..$];
                do_add = true;
                neg = true;
            }
        }
        mConstant = strparser.stringToType!(T)(src);
        static if (add) {
            if (neg)
                mConstant = -mConstant;
        }
    }

    override T calculate_value() {
        T pv = mParentValue;
        if (do_mul) {
            static if (mul) {
                return cast(T)(pv * scale);
            } else {
                assert(false);
            }
        } else if (do_add) {
            static if (add) {
                return pv + mConstant;
            } else {
                assert(false);
            }
        } else {
            return mConstant;
        }
    }
}

//xxx: add relative stuff later, e.g. color or alpha changes
class StyleValueColor : StyleValueT!(Color) {
    private {
        Color mColor;
    }

    this(Styles a_owner, char[] a_name, ConfigNode a_definition) {
        super(a_owner, a_name, a_definition);

        mColor = Color.fromString(mDefinition.value);
    }

    override Color calculate_value() {
        return mColor;
    }
}

//convencience functions blergh (oh god why)
void styleRegisterInt(char[] name) {
    StyleValueFactory.register!(StyleValueScalar!(int))(name);
}
void styleRegisterFloat(char[] name) {
    StyleValueFactory.register!(StyleValueScalar!(float))(name);
}
void styleRegisterString(char[] name) {
    //abuse
    StyleValueFactory.register!(StyleValueScalar!(char[], false, false))(name);
}
void styleRegisterColor(char[] name) {
    StyleValueFactory.register!(StyleValueColor)(name);
}
void styleRegisterBool(char[] name) {
    //also abuse
    StyleValueFactory.register!(StyleValueScalar!(bool, false, false))(name);
}

unittest {
    styleRegisterInt("prop1");
    styleRegisterInt("rel");
    Styles s_root1 = new Styles();
    auto root1 = new ConfigNode();
    auto s1 = root1.add("*");
    s1.add("prop1", "123");
    s1.add("prop2", "456");
    s1.add("rel", "200");
    auto s2 = root1.add("/cl1 $name1");
    s2.add("prop1", "2123");
    s2.add("prop2", "2456");
    auto s3 = root1.add("/cl1 / cl2");
    s3.add("prop1", "3123");
    s3.add("prop2", "3456");
    auto s4 = root1.add(":xd");
    s4.add("rel", "600");
    s_root1.addRules(root1);
    assert(s_root1.getValue!(int)("prop1") == 123);
    s_root1.id = "name1";
    assert(s_root1.getValue!(int)("prop1") == 123);
    s_root1.addClasses(["cl1"]);
    assert(s_root1.getValue!(int)("prop1") == 2123);
    auto s_root2 = new Styles();
    s_root2.parent = s_root1;
    auto root2 = new ConfigNode();
    auto s2_1 = root2.add("*");
    s2_1.add("rel", "20%");
    auto s2_2 = root2.add(":xd");
    s2_2.add("rel", "50%");
    s_root2.addRules(root2);
    assert(s_root2.getValue!(int)("rel") == 40);
    s_root2.setState("xd", true);
    assert(s_root2.getValue!(int)("rel") == 100);
    s_root2.setState("xd", false);
    assert(s_root2.getValue!(int)("rel") == 40);
    s_root1.setState("xd", true);
    assert(s_root2.getValue!(int)("rel") == 120);
    assert(s_root2.getValue!(int)("prop1") == 123);
    s_root2.addClasses(["cl1"]);
    assert(s_root2.getValue!(int)("prop1") == 123);
    s_root2.addClasses(["cl2"]);
    assert(s_root2.getValue!(int)("prop1") == 3123);
    //Trace.formatln("{} {}", s_root1.rulesString(), s_root1.statesString());
    //Trace.formatln("{} {}", s_root2.rulesString(), s_root2.statesString());
    //Trace.formatln("{}", s_root2.getValue!(int)("prop1"));
}

//utility functions

//return true when b is contained completely in a
//both arrays must be sorted!
bool sorted_array_is_contained(T)(T[] a, T[] b) {
    int ia;
    outer: for (int ib = 0; ib < b.length; ib++) {
        while (ia < a.length) {
            if (b[ib] == a[ia])
                continue outer;
            ia++;
        }
        //not found
        return false;
    }
    return true;
}

unittest {
    assert(sorted_array_is_contained([0,1,2,3,5,7], [1,2,5]));
    assert(!sorted_array_is_contained([1,2,5], [0,1,2,3,5,7]));
    assert(sorted_array_is_contained([1,2,5], [1,2,5]));
    assert(sorted_array_is_contained([1,2,5], cast(int[])[]));
    assert(!sorted_array_is_contained(cast(int[])[], [1,2,5]));
}

//split after delimiters and keep the delimiters as prefixes
//never adds empty strings to the result
//rest of documentation see unittest lol
char[][] splitPrefixDelimiters(char[] s, char[][] delimiters) {
    char[][] res;
    int last_delim = 0;
    for (;;) {
        int next = -1;
        int delim_len;
        foreach (del; delimiters) {
            auto v = str.find(s[last_delim..$], del);
            if (v >= 0 && (next < 0 || v <= next)) {
                next = v;
                delim_len = del.length;
            }
        }
        if (next < 0)
            break;
        next += last_delim;
        last_delim = delim_len;
        auto pre = s[0..next];
        if (pre.length)
            res ~= pre;
        s = s[next..$];
    }
    if (s.length)
        res ~= s;
    return res;
}

unittest {
    assert(splitPrefixDelimiters("abc#de#fghi", ["#"])
        == ["abc", "#de", "#fghi"]);
    assert(splitPrefixDelimiters("##abc##", ["#"]) == ["#", "#abc", "#", "#"]);
    assert(splitPrefixDelimiters("abc#de,fg,#", ["#", ","])
        == ["abc", "#de", ",fg", ",", "#"]);
}


