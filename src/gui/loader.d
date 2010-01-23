module gui.loader;

import framework.i18n;
import gui.container;
import gui.widget;
import utils.configfile;
import utils.factory;
import utils.misc;

/// This class can construct a Widget tree from config files
/// (currently only one Wiget tree per file / LoadGui object)
class LoadGui {
    private {
        const cTemplate = "template";

        Widget[char[]] mWidgets;
        Widget mRoot;
        Factory!(Widget) mFactory;
        ConfigNode mTemplates;
        ConfigNode mConfig;
        Translator mLocale;

        class Loader : GuiLoader {
            ConfigNode mNode;

            this(ConfigNode n) {
                mNode = n;
            }

            ConfigNode node() {
                return mNode;
            }
            Widget loadWidget(ConfigNode from) {
                return loadFrom(from);
            }

            Translator locale() {
                return mLocale;
            }
        }
    }

    private Widget createWidget(char[] classname) {
        if (mFactory.exists(classname))
            return mFactory.instantiate(classname);
        if (WidgetFactory.exists(classname))
            return WidgetFactory.instantiate(classname);
        throw new CustomException("Widget '"~classname~"' not found.");
    }

    //templates: allow to mixin stuff from a "central" place
    //(template = include values and nodes from another ConfigNode)
    private void doTemplates(ConfigNode node) {
        auto templ = node.findNode(cTemplate);
        if (templ) {
            auto mix = mTemplates.findNode(templ.value);
            if (!mix)
                throw new CustomException("template not found: '"~templ.value~"'");
            node.mixinNode(mix);
            node.remove(cTemplate);
        }
    }

    //load a single Widget
    Widget loadFrom(ConfigNode node) {
        doTemplates(node);

        Widget res;

        //possible things:
        if (node.hasValue("class")) {
            //"class" to create a Widget from the factory
            auto classname = node.getStringValue("class", "no_class");
            res = createWidget(classname);
        } else if (node.hasValue("reference")) {
            //"reference" to include an existing, already created Widget
            res = lookup(node.getStringValue("reference"));
        } else {
            //or nothing (should it be allowed?)
            return null;
        }

        readWidgetProperties(res, node);
        return res;
    }

    ///read properties for an existing Widget
    void readWidgetProperties(Widget w, ConfigNode node) {
        doTemplates(node);

        auto name = node.findValue("name");
        if (name) {
            addNamedWidget(w, name.value);
        }

        //whatever that could be useful for
        if (node.getBoolValue("dont_read", false))
            return;

        w.loadFrom(new Loader(node));
    }

    ///enter a Widget, to support the "reference" field (also used internally)
    ///i.e. before loading, add a Widget here, and then reference it in the
    ///config file, using said field
    void addNamedWidget(Widget w, char[] name) {
        if ((name in mWidgets) && (mWidgets[name] !is w)) {
            throw new CustomException("double name: '"~name~"'");
        }
        w.styles.addClass("id-" ~ name);
        mWidgets[name] = w;
    }

    ///register a custom Widget under a name; overrides the global Widget
    ///factory (to avoid poluting the global namespace with special Widgets)
    void registerWidget(T : Widget)(char[] classname) {
        mFactory.register!(T)(classname);
    }

    ///toplevel Widget
    Widget root() {
        return mRoot;
    }

    ///get a named Widget (as set by "name"-field in the config file)
    T lookup(T : Widget = Widget)(char[] name, bool canfail = false) {
        auto p = name in mWidgets;
        T res;
        if (p)
            res = cast(T)(*p);
        if (!res && !canfail)
            throw new CustomException("LoadGui.lookup: '"~name~"' not found/invalid");
        return res;
    }

    this(ConfigNode node) {
        mFactory = new typeof(mFactory);

        mConfig = node;
        mTemplates = mConfig.getSubNode("templates");
        mTemplates.templatetifyNodes(cTemplate);


    }

    ///create and actually load GUI
    void load() {
        if (mRoot)
            return;
        char[] loc = mConfig["locale"];
        //returns copy of localeRoot if loc == ""
        mLocale = localeRoot.bindNamespace(loc);
        //if no locale is set, avoid destroying names with dots
        if (loc.length == 0)
            mLocale.fullIdOnError = true;
        //no "missing id" if no translation was found, just return string
        mLocale.errorString = false;
        foreach (char[] name, ConfigNode c; mConfig.getSubNode("elements")) {
            //hm, I resisted from that, it would be a hack
            //c.setStringValue("name", name);
            loadFrom(c);
        }
    }
}
