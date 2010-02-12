module game.plugins;

import common.resset;
import common.resources : gResources, ResourceFile;
import framework.config;
import framework.framework;
import framework.i18n; //just because of weapon loading...
import game.controller_events;
import game.game;
import game.gfxset;
import game.gobject;
import game.weapon.weapon;
import utils.misc;
import utils.factory;
import utils.configfile;
import utils.path;
import utils.string : isIdentifier;

///thrown when a plugin fails to load; the game may still work without it
class PluginException : CustomException {
    this(char[] msg) {
        super(msg);
    }
}

//the "load-time" part of a plugin (static; loaded when GfxSet is created)
//always contains: dependencies, collisions, resources, sequences, locales
class Plugin {
    char[] name;            //unique plugin id
    char[][] dependencies;  //all plugins in this list will be loaded, too

    private {
        ConfigNode mConfig;
        ConfigNode mConfigWhateverTheFuckThisIs;
        ResourceFile mResources;
        GfxSet mGfx;
        char[][] mModules;
    }

    //called in resource-loading phase; currently name comes from plugin path
    //  conf = static plugin configuration
    this(char[] a_name, GfxSet gfx, ConfigNode conf) {
        name = a_name;
        if (!isIdentifier(name)) {
            throw new PluginException("Plugin name is not a valid identifier");
        }
        mGfx = gfx;
        mConfig = conf;
        assert(!!conf);
        dependencies = mConfig.getValue("dependencies", dependencies);

        //load resources
        if (gResources.isResourceFile(mConfig)) {
            try {
                mResources = gfx.addGfxSet(mConfig);
            //this doesn't work because error handling is generally crap
            } catch (LoadException e) {
                throw new PluginException("Failed to load resources: " ~ e.msg);
            }
            //load collisions
            char[] colFile = mConfig.getStringValue("collisions",
                "collisions.conf");
            auto coll_conf = loadConfig(mResources.fixPath(colFile), true,true);
            if (coll_conf) {
                try {
                    gfx.addCollideConf(coll_conf.getSubNode("collisions"));
                } catch (CustomException e) {
                    throw new PluginException("Failed to load collisions: "
                        ~ e.msg);
                }
            }
            //load locale
            //xxx fixed id "weapons"; has to change, but how?
            addLocaleDir("weapons", mResources.fixPath("locale"));
        }

        //
        mModules = conf.getValue("modules", mModules);

        //?
        mConfigWhateverTheFuckThisIs = mConfig.getSubNode("config");
    }

    //called from GfxSet.finishLoading(); resources are sealed and can be used
    void finishLoading() {
        if (mResources) {
            //load the weapons (they reference resources)
            char[] weaponsdir = mResources.fixPath("weapons");
            gFS.listdir(weaponsdir, "*.conf", false,
                (char[] path) {
                    //a weapons file can contain resources, collision map
                    //additions and a list of weapons
                    auto wp_conf = loadConfig(weaponsdir ~ "/"
                        ~ path[0..$-5]);
                    mGfx.addCollideConf(wp_conf.getSubNode("collisions"));
                    auto list = wp_conf.getSubNode("weapons");
                    foreach (ConfigNode item; list) {
                        loadWeaponClass(item);
                    }
                    return true;
                }
            );
        }
    }

    //called from GameEngine, to create the runtime part of this plugin
    void init(GameEngine eng) {
        //handling of internal plugins (special cased D-only plugin hack)
        char[] internal_plugin = mConfig["internal_plugin"];
        if (internal_plugin.length) {
            GamePluginFactory.instantiate(internal_plugin, eng,
                mConfigWhateverTheFuckThisIs);
        }

        //pass configuration as global "config"
        eng.scripting().setGlobal("config", mConfigWhateverTheFuckThisIs, name);
        bool[char[]] loadedModules;
        //each modules entry can be a file, or a pattern with wildcards
        foreach (modf; mModules) {
            //no fixup for illegal chars, allow wildcards
            auto mpath = VFSPath(mResources.fixPath(modf), false, true);

            gFS.listdir(mpath.parent, mpath.filename, false, (char[] relFn) {
                //why does listdir return relative filenames? I don't know
                char[] filename = mpath.parent.get(true, true) ~ relFn;
                //only load once
                if (filename in loadedModules) {
                    return true;
                }
                loadedModules[filename] = true;
                auto st = gFS.open(filename);
                scope(exit) st.close();
                //filename = for debug output; name = lua environment
                //xxx catch lua errors here, so other modules can be loaded?
                eng.scripting().loadScript(filename, st, name);
                return true;
            });
        }
        //no GameObject? hmm
    }

    //a weapon subnode of weapons.conf
    private void loadWeaponClass(ConfigNode weapon) {
        char[] type = weapon.getStringValue("type", "action");
        //xxx error handling
        //hope you never need to debug this code!
        WeaponClass c = WeaponClassFactory.instantiate(type, mGfx, weapon);
        mGfx.registerWeapon(c);
    }
}
