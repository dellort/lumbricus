module game.gamemodes.lua;

import framework.framework;
import game.game;
import game.controller;
import game.gamemodes.base;
import utils.configfile;
import utils.misc;

class ModeLua : Gamemode {
    private {
        struct ModeConfig {
            char[] filename;
        }
        ModeConfig config;
    }

    this(GameController parent, ConfigNode cfgNode) {
        super(parent, cfgNode);
        config = cfgNode.getCurValue!(ModeConfig)();

        auto st = gFS.open(config.filename);
        scope(exit) st.close();
        engine.scripting.loadScript(config.filename, st);
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("lua");
    }
}
