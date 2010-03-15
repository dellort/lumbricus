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
import game.setup;
import utils.misc;
import utils.factory;
import utils.configfile;
import utils.log;
import utils.path;
import utils.string : isIdentifier;

///thrown when a plugin fails to load; the game may still work without it
class PluginException : CustomException {
    this(char[] msg) {
        super(msg);
    }
}

//another dumb singleton
class PluginBase {
    private {
        GfxSet mGfx;
        bool[char[]] mLoadedPlugins;
        //list of active plugins, in load order
        Plugin[] mPlugins;
    }

    this(GfxSet gfx, GameConfig cfg) {
        mGfx = gfx;

        foreach (ConfigNode sub; cfg.plugins) {
            //either an unnamed value, or a subnode with config items
            char[] pid = sub.value.length ? sub.value : sub.name;
            try {
                loadPlugin(pid, sub, cfg.plugins);
            } catch (PluginException e) {
                //xxx we need "something" to handle non-fatal errors
                Trace.formatln("Plugin '{}' failed to load: {}", pid, e.msg);
            }
        }

        OnGameInit.handler(gfx.events, &initplugins);
    }

    void loadPlugin(char[] pluginId, ConfigNode cfg, ConfigNode allPlugins) {
        assert(!!allPlugins);
        if (pluginId in mLoadedPlugins) {
            return;
        }

        ConfigNode conf;
        if (GamePluginFactory.exists(pluginId)) {
            //internal plugin with no confignode
            conf = new ConfigNode();
            conf["internal_plugin"] = pluginId;
        } else {
            //normal case: plugin with plugin.conf
            char[] confFile = "plugins/" ~ pluginId ~ "/plugin.conf";
            //load plugin.conf as gfx set (resources and sequences)
            try {
                conf = gResources.loadConfigForRes(confFile);
            } catch (CustomException e) {
                throw new PluginException("Failed to load plugin.conf ("
                    ~ e.msg ~ ")");
            }
        }

        //mixin dynamic configuration
        if (cfg) {
            conf.getSubNode("config").mixinNode(cfg, true);
        }

        Plugin newPlugin = new Plugin(pluginId, mGfx, conf);

        //this will place dependencies in the plugins[] first, making them load
        //  before the current plugin
        foreach (dep; newPlugin.dependencies) {
            try {
                loadPlugin(dep, allPlugins.findNode(dep), allPlugins);
            } catch (PluginException e) {
                throw new PluginException("Dependency '" ~ dep
                    ~ "' failed to load: " ~ e.msg);
            }
        }

        mPlugins ~= newPlugin;
        mLoadedPlugins[pluginId] = true;
    }

    private void initplugins(GameObject sender) {
        GameEngine engine = sender.engine;
        foreach (plg; mPlugins) {
            //xxx controller is not yet available; plugins have to be careful
            //    best way around: add more events for different states of
            //    game initialization
            try {
                plg.init(engine);
            } catch (CustomException e) {
                //wtfwtfwtfwtf
                Trace.formatln("Plugin '{}' failed to init(): {}", plg.name,
                    e.msg);
                engine.error("Plugin '{}' failed to init(): {}", plg.name,
                    e.msg);
            }
        }
    }
}

//the "load-time" part of a plugin (static; loaded when GfxSet is created)
//always contains: dependencies, collisions, resources, sequences, locales
class Plugin {
    char[] name;            //unique plugin id
    char[][] dependencies;  //all plugins in this list will be loaded, too

    static LogStruct!("game.plugins") log;

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
        log("loading '{}'", name);
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

    //called from GameEngine, to create the runtime part of this plugin
    void init(GameEngine eng) {
        log("init '{}'", name);
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

            bool loaded = false;

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
                log("load lua script for '{}': {}", name, filename);
                eng.scripting().loadScript(filename, st, name);
                loaded = true;
                return true;
            });

            if (!loaded)
                assert(false, "not loaded: '"~modf~"'");
        }
        //no GameObject? hmm
    }
}
