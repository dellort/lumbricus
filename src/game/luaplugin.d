module game.luaplugin;

import framework.framework;
import game.controller;
import game.controller_events;
import game.game;
import game.gobject;
import utils.configfile;
import utils.misc;

//lua script as generic GameObject (only good for plugin loading)
//questionable way to load scripts, but needed for game mode right now
class LuaPlugin : GameObject {
    private {
        struct Config {
            char[] filename;
        }
        Config config;
    }

    this(GameEngine a_engine, ConfigNode cfgNode) {
        super(a_engine, "luaplugin");
        config = cfgNode.getCurValue!(Config)();

        auto st = gFS.open(config.filename);
        scope(exit) st.close();
        engine.scripting.loadScript(config.filename, st);
    }

    override bool activity() {
        return false;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("lua");
    }
}
