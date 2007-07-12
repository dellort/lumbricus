module game.gametask;

import common.common;
import common.task;
import game.gui.gameframe;
import game.game : GameConfig;
import levelgen.level;
import levelgen.generator;
import utils.configfile;

class GameTask : Task {
    private {
        GameFrame mWindow;
    }

    //not happy with this; but who cares
    //this _really_ should be considered to be a debugging features
    //(to use it from the factory)
    //use the other constructor and pass it a useful GameConfig
    this(TaskManager tm) {
        super(tm);
        initGame(loadGameConfig(globals.anyConfig.getSubNode("newgame")));
    }

    //start a game
    this(TaskManager tm, GameConfig cfg) {
        super(tm);
        initGame(cfg);
    }

    //start game intialization
    //it's not clear when initialization is finished (but it shows a loader gui)
    private void initGame(GameConfig cfg) {
        //xxx maybe move functionality out of GameFrame, i.e. loading of stuff!
        mWindow = new GameFrame(cfg);
        manager.guiMain.mainFrame.add(mWindow);
    }

    override protected void onKill() {
        //smash it up (forced kill; unforced goes into terminate())
        mWindow.remove(); //from GUI
        mWindow.kill();   //deinitialize
    }

    override protected void onFrame() {
        //xxx do game simulation _here_
        //and don't use the gui hooks (Widget.simulate()) for that
    }

    static this() {
        TaskFactory.register!(typeof(this))("game");
    }
}

//xxx doesn't really belong here
//not to be called by GameTask; instead, anyone who wants to start a game can
//call this to the params out from a configfile
//GameTask shoiuld not be responsible to choose any game configuration for you
GameConfig loadGameConfig(ConfigNode mConfig, Level level = null) {
    //log("loadConfig");
    GameConfig cfg;
    if (level) {
        cfg.level = level;
    } else {
        bool load = mConfig.selectValueFrom("level", ["generate", "load"]) == 1;
        auto x = new genlevel.LevelGenerator();
        if (load) {
            cfg.level =
                x.renderSavedLevel(globals.loadConfig(mConfig["level_load"]));
        } else {
            genlevel.LevelTemplate templ =
                x.findRandomTemplate(mConfig["level_template"]);
            genlevel.LevelTheme gfx = x.findRandomGfx(mConfig["level_gfx"]);

            cfg.level = generateAndSaveLevel(x, templ, null, gfx);
        }
    }
    auto teamconf = globals.loadConfig("teams");
    cfg.teams = teamconf.getSubNode("teams");

    auto gamemodecfg = globals.loadConfig("gamemode");
    auto modes = gamemodecfg.getSubNode("modes");
    cfg.gamemode = modes.getSubNode(
        mConfig.getStringValue("gamemode",""));
    cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

    return cfg;
}

//xxx doesn't really belong here
//generate level and save generated level as lastlevel.conf
//any param other than gen can be null
Level generateAndSaveLevel(LevelGenerator gen, LevelTemplate templ,
    LevelGeometry geo, LevelTheme gfx)
{
    templ = templ ? templ : gen.findRandomTemplate("");
    gfx = gfx ? gfx : gen.findRandomGfx("");
    //be so friendly and save it
    ConfigNode saveto = new ConfigNode();
    auto res = gen.renderLevelGeometry(templ, geo, gfx, saveto);
    saveConfig(saveto, "lastlevel.conf");
    return res;
}
