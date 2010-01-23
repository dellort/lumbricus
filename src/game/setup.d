module game.setup;

///should contain stuff for configuring a game before GameTask is spawned
///currently, only GameConfig setup and savegame utility functions

import common.common;
import framework.framework;
import game.levelgen.level;
import game.levelgen.generator;
import utils.configfile;
import utils.misc;

///Initial game configuration
//xxx this sucks etc.
class GameConfig {
    Level level;
    ConfigNode saved_level; //is level.saved
    ConfigNode plugins;
    ConfigNode teams;
    ConfigNode weapons;
    //objects which shall be created and placed into the level at initialization
    //(doesn't include the worms, ???)
    ConfigNode levelobjects;
    //infos for the graphicset, current items:
    // - config: string with the name of the gfx set, ".conf" will be appended
    //   to get the config filename ("wwp" becomes "wwp.conf")
    // - waterset: string with the name of the waterset (like "blue")
    //probably should be changed etc., so don't blame me
    ConfigNode gfx;
    char[] randomSeed;
    //contains subnode "access_map", which maps tag-names to team-ids
    //the tag-name is passed as first arg to GameEngine.executeCmd(), see there
    ConfigNode management;

    //state that survives multiple rounds, e.g. worm statistics and points
    ConfigNode gamestate;

    ConfigNode save() {
        //xxx: not nice. but for now...
        ConfigNode to = new ConfigNode();
        to.addNode("level", saved_level.copy);
        to.addNode("teams", teams.copy);
        to.addNode("weapons", weapons.copy);
        to.addNode("levelobjects", levelobjects.copy);
        to.addNode("gfx", gfx.copy);
        to.addNode("gamestate", gamestate.copy);
        to.addNode("plugins", plugins.copy);
        to.setStringValue("random_seed", randomSeed);
        to.addNode("management", management.copy);
        return to;
    }

    void load(ConfigNode n) {
        level = null;
        saved_level = n.getSubNode("level");
        teams = n.getSubNode("teams");
        weapons = n.getSubNode("weapons");
        levelobjects = n.getSubNode("levelobjects");
        gfx = n.getSubNode("gfx");
        gamestate = n.getSubNode("gamestate");
        plugins = n.getSubNode("plugins");
        randomSeed = n["random_seed"];
        management = n.getSubNode("management");
    }
}

//xxx doesn't really belong here
//not to be called by GameTask; instead, anyone who wants to start a game can
//call this to the params out from a configfile
//GameTask should not be responsible to choose any game configuration for you
GameConfig loadGameConfig(ConfigNode mConfig, Level level = null,
    bool renderBitmaps = true, ConfigNode persistentState = null)
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
                loadConfig(mConfig["level_load"], true), renderBitmaps);
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
            throw new CustomException("noes noes noes!");
        }
    }

    cfg.saved_level = cfg.level.saved;

    auto teamconf = loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    cfg.levelobjects = mConfig.getSubNode("levelobjects");

    auto gamemodecfg = loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    auto modeNode = modes.getSubNode(
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
    cfg.plugins = mConfig.getSubNode("plugins");
    //xxx always load default weaponset
    if (!cfg.plugins.hasSubNodes()) {
        cfg.plugins.getSubNode("ws_default");
    }
    cfg.plugins.getSubNode(modeNode["mode"]).mixinNode(modeNode, true);

    if (!persistentState)
        persistentState = mConfig.getSubNode("gamestate");
    cfg.gamestate = persistentState;

    //needs to be set up by user
    //for local games, the access tag "local" can be used to control all teams;
    //  so there's no access map needed
    cfg.management = mConfig.getSubNode("management");

    return cfg;
}
