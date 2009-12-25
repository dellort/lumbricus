module common.settings;

import framework.config;
import framework.framework;
import gui.widget : GUI;
import utils.configfile;
import utils.proplist;
import utils.misc;

PropertyList gSettings;

PropertyChoice gGuiTheme;

static this() {
    gSettings = new PropertyList;
    gSettings.name = "global";
    gSettings.addNode(gFrameworkSettings);

    //bad idea, but nobody cares
    auto cmd = new PropertyCommand();
    cmd.name = "save";
    cmd.onCommand = toDelegate(&saveSettings);
    gSettings.addNode(cmd);

    auto guisettings = gSettings.addList("gui");
    gGuiTheme = new PropertyChoice;
    gGuiTheme.name = "theme";
    guisettings.addNode(gGuiTheme);
}

void prepareSettings() {
    foreach (c; GUI.listThemes()) {
        gGuiTheme.add(c);
    }
}

void loadSettings() {
    ConfigNode node = loadConfig("settings.conf", true);
    settingsFromConfig(gSettings, node);
}

void saveSettings() {
    auto n = settingsToConfig(gSettings);
    saveConfig(n, "settings.conf");
}

//maybe move to proplist.d

void settingsFromConfig(PropertyNode s, ConfigNode n) {
    void recurse(PropertyNode p, ConfigNode node) {
        //xxx some error handling would be nice:
        //  1. unparseable values
        //  2. config nodes/values that don't exist in the property list
        if (auto v = cast(PropertyValue)p) {
            try {
                v.setAsString(node.value);
            } catch (InvalidValue e) {
                //the user should be warned, or so
                assert(false, "add error handling for "~e.toString());
            }
        } else {
            foreach (sub; p.asList()) {
                auto n2 = node.findNode(sub.name);
                if (n2)
                    recurse(sub, n2);
            }
        }
    }
    recurse(s, n);
}

ConfigNode settingsToConfig(PropertyNode s) {
    auto res = new ConfigNode();
    void recurse(PropertyNode n) {
        if (auto v = cast(PropertyValue)n) {
            if (cast(PropertyCommand)v)
                return;
            //getPath() so, that nodes are only created when actually needed
            //xxx n.path() leads to memory waste
            res.getPath(n.path(s), true).value = v.asString;
        } else {
            foreach (sub; n.asList()) {
                recurse(sub);
            }
        }
    }
    recurse(s);
    return res;
}
