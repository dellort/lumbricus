module game.setup;

///should contain stuff for configuring a game before GameTask is spawned
///currently, only GameConfig setup and savegame utility functions

import common.common;
import framework.framework;
import game.gamepublic;
import game.levelgen.level;
import game.levelgen.generator;
import utils.configfile;
import utils.misc;

//xxx doesn't really belong here
//not to be called by GameTask; instead, anyone who wants to start a game can
//call this to the params out from a configfile
//GameTask should not be responsible to choose any game configuration for you
GameConfig loadGameConfig(ConfigNode mConfig, Level level = null,
    bool renderBitmaps = true)
{
    //log("loadConfig");
    GameConfig cfg = new GameConfig();

    if (level) {
        cfg.level = level;
    } else {
        auto x = new LevelGeneratorShared();
        switch (mConfig["level"]) {
        case "generate":
            auto gen = new GenerateFromTemplate(x, cast(LevelTemplate)null);
            cfg.level = gen.render(renderBitmaps);
            break;
        case "load":
            cfg.level = loadSavedLevel(x,
                gConf.loadConfig(mConfig["level_load"], true), renderBitmaps);
            break;
        case "loadbmp":
            auto gen = new GenerateFromBitmap(x);
            auto fn = mConfig["level_load_bitmap"];
            gen.bitmap(gFramework.loadImage(fn), fn);
            gen.selectTheme(x.themes.findRandom(mConfig["level_gfx"]));
            cfg.level = gen.render(renderBitmaps);
            break;
        default:
            //wrong string in configfile
            throw new Exception("noes noes noes!");
        }
    }

    cfg.saved_level = cfg.level.saved;

    auto teamconf = gConf.loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    cfg.levelobjects = mConfig.getSubNode("levelobjects");

    auto gamemodecfg = gConf.loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    cfg.gamemode = modes.getSubNode(
        mConfig.getStringValue("gamemode",""));

    //gamemode.conf contains all defined weapon sets, but we only
    //  want the ones used in the current game
    auto avWeaponSets = gamemodecfg.getSubNode("weapon_sets");
    char[][char[]] wCache;
    cfg.weapons = new ConfigNode();
    foreach (ConfigNode item; mConfig.getSubNode("weapons")) {
        if (item.value in wCache)
            //we already have this set, add a reference to it
            cfg.weapons.add(item.name, wCache[item.value]);
        else {
            //new set has to be included
            cfg.weapons.addNode(item.name, avWeaponSets.getSubNode(item.value));
            wCache[item.value] = item.name;
        }
    }

    cfg.gfx = mConfig.getSubNode("gfx");
    cfg.weaponsets = mConfig.getValueArray!(char[])("weaponsets");
    if (cfg.weaponsets.length == 0) {
        cfg.weaponsets ~= "default";
    }

    return cfg;
}
