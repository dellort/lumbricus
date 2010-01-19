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

alias StaticFactory!("RegPlugins", RegisteredPlugin, char[], GfxSet, ConfigNode)
    RegPluginFactory;

//the "load-time" part of a plugin (static; loaded when GfxSet is created)
//always contains: dependencies, collisions, resources, sequences, locales
class RegisteredPlugin {
    char[] name;            //unique plugin id
    char[][] dependencies;  //all plugins in this list will be loaded, too

    protected {
        ConfigNode mConfig;
        ResourceFile mResources;
        GfxSet mGfx;
    }

    //called in resource-loading phase; currently name comes from plugin path
    //  conf = static plugin configuration
    this(char[] a_name, GfxSet gfx, ConfigNode conf) {
        name = a_name;
        mGfx = gfx;
        mConfig = conf;
        dependencies = mConfig.getValue("dependencies", dependencies);

        //load resources
        mResources = gfx.addGfxSet(mConfig);
        assert(!!mResources);
        //load collisions
        char[] colFile = mConfig.getStringValue("collisions","collisions.conf");
        auto coll_conf = loadConfig(mResources.fixPath(colFile), true, true);
        if (coll_conf)
            gfx.addCollideConf(coll_conf.getSubNode("collisions"));
        //load locale
        //xxx fixed id "weapons"; has to change, but how?
        addLocaleDir("weapons", mResources.fixPath("locale"));
    }

    //called from GfxSet.finishLoading(); resources are sealed and can be used
    void finishLoading() {
    }

    //called from GameEngine, to create the runtime part of this plugin
    //  cfg = dynamic plugin configuration
    void init(GameEngine eng, ConfigNode cfg) {
    }
}

//plain old weapon set; additionally contains some conf-based weapons
class WeaponsetPlugin : RegisteredPlugin {
    this(char[] a_name, GfxSet gfx, ConfigNode conf) {
        super(a_name, gfx, conf);
    }

    override void finishLoading() {
        super.finishLoading();
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

    //a weapon subnode of weapons.conf
    private void loadWeaponClass(ConfigNode weapon) {
        char[] type = weapon.getStringValue("type", "action");
        //xxx error handling
        //hope you never need to debug this code!
        WeaponClass c = WeaponClassFactory.instantiate(type, mGfx, weapon);
        mGfx.registerWeapon(c);
    }

    static this() {
        RegPluginFactory.register!(typeof(this))("weaponset");
    }
}

//lua-based plugin; additionally contains a list of lua modules
class LuaPlugin : RegisteredPlugin {
    protected {
        char[][] mModules;
    }

    this(char[] a_name, GfxSet gfx, ConfigNode conf) {
        super(a_name, gfx, conf);
        mModules = conf.getValue("modules", mModules);
    }

    override void init(GameEngine eng, ConfigNode cfg) {
        foreach (modf; mModules) {
            char[] filename = mResources.fixPath(modf);

            auto st = gFS.open(filename);
            scope(exit) st.close();
            //filename = for debug output; name = lua environment
            eng.scripting().loadScriptEnv(filename, name, st);
        }
        //no GameObject? hmm
    }

    static this() {
        RegPluginFactory.register!(typeof(this))("lua");
    }
}

//a plugin implemented in D; name has to match with GamePluginFactory
class InternalPlugin : RegisteredPlugin {
    this(char[] a_name, GfxSet gfx, ConfigNode conf) {
        super(a_name, gfx, conf);
        assert(GamePluginFactory.exists(name));
    }

    override void init(GameEngine eng, ConfigNode cfg) {
        GamePluginFactory.instantiate(name, eng, cfg);
    }

    static this() {
        RegPluginFactory.register!(typeof(this))("internal");
    }
}
