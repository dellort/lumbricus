module game.plugins;

import common.lua; // : loadScript
import common.resset;
import common.resources : gResources, ResourceFile;
import framework.config;
import framework.filesystem;
import framework.i18n; //just because of weapon loading...
import game.core;
import game.gfxset;
import game.setup;
import utils.misc;
import utils.factory;
import utils.configfile;
import utils.log;
import utils.path;
import utils.string : isIdentifier;

//and another factory...
//"internal" plugins register here; these plugins don't have their own plugin
//  folder and are written in D
alias StaticFactory!("GamePlugins", GameObject, GameCore, ConfigNode)
    GamePluginFactory;

private static LogStruct!("game.plugins") log;

//another dumb singleton
class PluginBase {
    private {
        GameCore mEngine;
        GfxSet mGfx;
        bool[string] mLoadedPlugins;
        bool[string] mErrorPlugins; //like mLoadedPlugins, but error-flagged
        bool[string] mLoading;  //like mLoadedPlugins, but load-in-progress
        //list of active plugins, in load order
        Plugin[] mPlugins;
    }

    this(GameCore a_engine, GameConfig cfg) {
        mEngine = a_engine;
        mGfx = mEngine.singleton!(GfxSet)();

        foreach (ConfigNode sub; cfg.plugins) {
            //either an unnamed value, or a subnode with config items
            string pid = sub.value.length ? sub.value : sub.name;
            try {
                loadPlugin(pid, sub, cfg.plugins);
            } catch (CustomException e) {
                //xxx is continuing here really such a good idea
                log.error("Plugin '%s' failed to load: %s", pid, e);
                traceException(log.get, e);
            }
        }

        OnGameInit.handler(mGfx.events, &initplugins);
    }

    void loadPlugin(string pluginId, ConfigNode cfg, ConfigNode allPlugins) {
        if (pluginId in mLoadedPlugins) {
            return;
        }
        if (pluginId in mErrorPlugins) {
            log.warn("plugin '%s' has been marked as failed, will"
                " request for loading it ignored.",  pluginId);
            return;
        }
        if (pluginId in mLoading) {
            //produces a funny error message, but works
            throwError("circular plugin dependency detected");
        }

        mLoading[pluginId] = true;

        //oh the joys of exception handling...
        Plugin plugin;
        try {
            scope (exit) mLoading.remove(pluginId);
            plugin = doLoadPlugin(pluginId, cfg, allPlugins);
        } catch (CustomException e) {
            //oh noes! something went wrong!
            //flag as error, so that future attempts to load the plugin will
            //  be ignored, instead of retrying it (when several other plugins
            //  dependon the same failed plugins, several attempts are made)
            mErrorPlugins[pluginId] = true;
            e.msg = myformat("when loading plugin '%s': %s", pluginId, e.msg);
            throw e;
        }
        //otherwise, success!
        assert(!!plugin);
        mPlugins ~= plugin;
        mLoadedPlugins[pluginId] = true;
    }

    private Plugin doLoadPlugin(string pluginId, ConfigNode cfg,
        ConfigNode allPlugins)
    {
        assert(!!allPlugins);

        ConfigNode conf;
        if (GamePluginFactory.exists(pluginId)) {
            //internal plugin with no confignode
            conf = new ConfigNode();
            conf["internal_plugin"] = pluginId;
        } else {
            //normal case: plugin with plugin.conf
            string confFile = "plugins/" ~ pluginId ~ "/plugin.conf";
            //load plugin.conf as gfx set (resources and sequences)
            //may fail; but the resuting error msg will be already good enough
            conf = gResources.loadConfigForRes(confFile);
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
            } catch (CustomException e) {
                e.msg = myformat("when loading dependency '%s': %s", dep,
                    e.msg);
                throw e;
            }
        }

        return newPlugin;
    }

    private void initplugins() {
        foreach (plg; mPlugins) {
            //xxx controller is not yet available; plugins have to be careful
            //    best way around: add more events for different states of
            //    game initialization
            try {
                plg.doinit(mEngine);
            } catch (CustomException e) {
                log.error("Plugin '%s' failed to init(): %s", plg.name, e);
                traceException(log.get, e);
            }
        }
    }
}

//the "load-time" part of a plugin (static; loaded when GfxSet is created)
//always contains: dependencies, collisions, resources, sequences, locales
class Plugin {
    string name;            //unique plugin id
    string[] dependencies;  //all plugins in this list will be loaded, too

    private {
        ConfigNode mConfig, mCollisions;
        ConfigNode mConfigWhateverTheFuckThisIs;
        ResourceFile mResources;
        GfxSet mGfx;
        string[] mModules;
    }

    //called in resource-loading phase; currently name comes from plugin path
    //  conf = static plugin configuration
    this(string a_name, GfxSet gfx, ConfigNode conf) {
        name = a_name;
        log.minor("loading '%s'", name);
        if (!isIdentifier(name)) {
            throwError("Plugin name '%s' in %s is not a valid identifier.",
                name, conf.locationString);
        }
        mGfx = gfx;
        mConfig = conf;
        assert(!!conf);
        dependencies = mConfig.getValue("dependencies", dependencies);

        //load resources
        if (gResources.isResourceFile(mConfig)) {
            try {
                mResources = gfx.addGfxSet(mConfig);
            } catch (CustomException e) {
                e.msg = myformat("when loading resources for plugin %s: %s",
                    name, e.msg);
                throw e;
            }
            //load collisions
            string colFile = mConfig.getStringValue("collisions", "");
            if (colFile.length) {
                auto c = loadConfig(mResources.fixPath(colFile));
                mCollisions = c.getSubNode("collisions");
            }
            //load locale
            //  each entry is name=path
            //  name is the namespace under which the locales are loaded
            //  path is a relative path within the plugin's directory
            //xxx: the locales remain globally available, even if the game ends?
            auto locales = mConfig.getValue!(string[string])("locales");
            foreach (string name, string path; locales) {
                addLocaleDir(name, mResources.fixPath(path));
            }
        }

        //
        mModules = conf.getValue("modules", mModules);

        //?
        mConfigWhateverTheFuckThisIs = mConfig.getSubNode("config");
    }

    //create the runtime part of this plugin
    void doinit(GameCore eng) {
        log("init '%s'", name);

        if (mCollisions) {
            try {
                eng.physicWorld.collide.loadCollisions(mCollisions);
            } catch (CustomException e) {
                e.msg = myformat("when loading collisions for plugin %s: %s",
                    name, e.msg);
                throw e;
            }
        }

        //handling of internal plugins (special cased D-only plugin hack)
        string internal_plugin = mConfig["internal_plugin"];
        if (internal_plugin.length) {
            GamePluginFactory.instantiate(internal_plugin, eng,
                mConfigWhateverTheFuckThisIs);
        }

        //pass configuration as global "config"
        eng.scripting().setGlobal("config", mConfigWhateverTheFuckThisIs, name);
        bool[string] loadedModules;
        //each modules entry can be a file, or a pattern with wildcards
        foreach (modf; mModules) {
            //no fixup for illegal chars, allow wildcards
            auto mpath = VFSPath(mResources.fixPath(modf), false, true);

            bool loaded = false;

            //xxx should separate loading from parsing, maybe?
            gFS.listdir(mpath.parent, mpath.filename, false, (string relFn) {
                //why does listdir return relative filenames? I don't know
                string filename = mpath.parent.get(true, true) ~ relFn;
                //only load once
                if (filename in loadedModules) {
                    return true;
                }
                loadedModules[filename] = true;
                //filename = for debug output; name = lua environment
                //xxx catch lua errors here, so other modules can be loaded?
                log("load lua script for '%s': %s", name, filename);
                loadScript(eng.scripting(), filename, name);
                loaded = true;
                return true;
            });

            //file not found
            if (!loaded) {
                throwError("when loading plugin '%s': %s couldn't be found.",
                    name, mpath);
            }
        }
        //no GameObject? hmm
    }
}
