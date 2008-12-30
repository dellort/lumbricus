module game.setup;

///should contain stuff for configuring a game before GameTask is spawned
///currently, only GameConfig setup and savegame utility functions

import framework.framework;
import game.gametask;
import game.gamepublic;
import game.levelgen.level;
import game.levelgen.generator;
import utils.configfile;
import utils.misc;

const cSavegamePath = "/savegames/";
const cSavegameExt = ".conf.gz";
const cSavegameDefName = "save";

//xxx doesn't really belong here
//not to be called by GameTask; instead, anyone who wants to start a game can
//call this to the params out from a configfile
//GameTask shoiuld not be responsible to choose any game configuration for you
GameConfig loadGameConfig(ConfigNode mConfig, Level level = null) {
    //log("loadConfig");
    GameConfig cfg = new GameConfig();

    if (level) {
        cfg.level = level;
    } else {
        int what = mConfig.selectValueFrom("level",
            ["generate", "load", "loadbmp", "restore"], 0);
        auto x = new LevelGeneratorShared();
        if (what == 0) {
            auto gen = new GenerateFromTemplate(x, cast(LevelTemplate)null);
            cfg.level = gen.render();
        } else if (what == 1) {
            cfg.level = loadSavedLevel(x,
                gFramework.loadConfig(mConfig["level_load"], true));
        } else if (what == 2) {
            auto gen = new GenerateFromBitmap(x);
            auto fn = mConfig["level_load_bitmap"];
            gen.bitmap(gFramework.loadImage(fn), fn);
            gen.selectTheme(x.themes.findRandom(mConfig["level_gfx"]));
            cfg.level = gen.render();
        } else if (what == 3) {
            cfg.load_savegame = gFramework.loadConfig(mConfig["level_restore"]);
            return cfg;
        } else {
            //wrong string in configfile or internal error
            throw new Exception("noes noes noes!");
        }
    }

    cfg.saved_level = cfg.level.saved;

    auto teamconf = gFramework.loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    cfg.levelobjects = mConfig.getSubNode("levelobjects");

    auto gamemodecfg = gFramework.loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    cfg.gamemode = modes.getSubNode(
        mConfig.getStringValue("gamemode",""));
    cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

    cfg.gfx = mConfig.getSubNode("gfx");
    cfg.weaponsets = mConfig.getValueArray!(char[])("weaponsets");
    if (cfg.weaponsets.length == 0) {
        cfg.weaponsets ~= "default";
    }

    return cfg;
}

char[][] listAvailableSavegames() {
    char[][] list;
    gFramework.fs.listdir(cSavegamePath, "*", false,
        (char[] filename) {
            if (endsWith(filename, cSavegameExt)) {
                list ~= filename[0 .. $ - cSavegameExt.length];
            }
            return true;
        }
    );
    return list;
}

bool loadSavegame(char[] save, out GameConfig cfg) {
    cfg = new GameConfig();
    auto saved = gFramework.loadConfig(cSavegamePath~save,
        false, true);
    if (!saved)
        return false;
    if (!saved.getSubNode("serialized", false))
        return false;
    cfg.load_savegame = saved;
    return true;
}
