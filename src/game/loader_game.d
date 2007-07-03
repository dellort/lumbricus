module game.loader_game;

import game.loader;
import game.game;
import game.common;
import game.clientengine;
import game.scene;
import gui.gui;
import gui.guiobject;
import gui.gameview;
import gui.gametimer;
import gui.windmeter;
import gui.preparedisplay;
import gui.messageviewer;
import genlevel = levelgen.generator;
import utils.configfile;
import utils.log;

//stupid hack to access GameFrame, hopefully goes away very soon
interface GameGui {
    void addGui(GuiObject obj);
    void killGui();
}

class GameLoader : Loader {
    private ConfigNode mConfig;
    private GameConfig mGameConfig;
    private GameGui mGui;
    private bool mGameGuiOpened;
    private Log log;

    GameEngine thegame;
    ClientGameEngine clientengine;
    GameView gameView;

    this(ConfigNode config, GameGui mgui) {
        log = registerLog("GameLoader");
        mConfig = config;
        mGui = mgui;
        registerChunk(&loadConfig);
        registerChunk(&initGameEngine);
        registerChunk(&initClientEngine);
        registerChunk(&initializeGameGui);
    }

    override void unload() {
        unloadGui();
        unloadGame();
        super.unload();
    }

    private bool unloadGui() {
        log("unloadGui");
        if (mGameGuiOpened) {
            assert(gameView !is null);
            assert(mGui !is null);
            gameView.gamescene = null;
            gameView.controller = null;
            mGui.killGui();
            gameView = null;

            mGameGuiOpened = false;
        }

        return true;
    }

    private bool unloadGame() {
        log("unloadGame");
        if (thegame) {
            thegame.kill();
            //delete thegame;
            thegame = null;
        }
        if (clientengine) {
            clientengine.kill();
            delete clientengine;
            clientengine = null;
        }

        return true;
    }

    private bool loadConfig() {
        log("loadConfig");
        auto x = new genlevel.LevelGenerator();
        GameConfig cfg;
        bool load = mConfig.selectValueFrom("level", ["generate", "load"]) == 1;
        if (load) {
            cfg.level =
                x.renderSavedLevel(globals.loadConfig(mConfig["level_load"]));
        } else {
            genlevel.LevelTemplate templ =
                x.findRandomTemplate(mConfig["level_template"]);
            genlevel.LevelTheme gfx = x.findRandomGfx(mConfig["level_gfx"]);

            //be so friendly and save it
            ConfigNode saveto = new ConfigNode();
            cfg.level = x.renderLevel(templ, gfx, saveto);
            saveConfig(saveto, "lastlevel.conf");
        }
        auto teamconf = globals.loadConfig("teams");
        cfg.teams = teamconf.getSubNode("teams");

        auto gamemodecfg = globals.loadConfig("gamemode");
        auto modes = gamemodecfg.getSubNode("modes");
        cfg.gamemode = modes.getSubNode(
            mConfig.getStringValue("gamemode",""));
        cfg.weapons = gamemodecfg.getSubNode("weapon_sets");

        mGameConfig = cfg;

        return true;
    }

    private bool initGameEngine() {
        log("initGameEngine");
        thegame = new GameEngine(mGameConfig);

        return true;
    }

    private bool initClientEngine() {
        log("initClientEngine");
        //xxx README: since the scene is recreated for each level, there's no
        //            need to remove them all in Game.kill()
        clientengine = new ClientGameEngine(thegame);

        //callback when invoking cmdStop
        //mOnStopGui = &closeGame;

        return true;
    }

    private bool initializeGameGui() {
        log("initializeGameGui");
        mGameGuiOpened = true;

        mGui.addGui(new WindMeter(clientengine));
        mGui.addGui(new GameTimer(clientengine));
        mGui.addGui(new PrepareDisplay(clientengine));
        auto msg = new MessageViewer();
        mGui.addGui(msg);

        thegame.controller.messageCb = &msg.addMessage;
        thegame.controller.messageIdleCb = &msg.idle;

        gameView = new GameView(clientengine);
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));
        mGui.addGui(gameView);
        gameView.zorder = GUIZOrder.Game;

        gameView.controller = thegame.controller;
        gameView.gamescene = clientengine.scene;

        //start at level center
        gameView.view.scrollCenterOn(thegame.gamelevel.offset
            + thegame.gamelevel.size/2, true);

        return true;
    }

    override void finished() {
        super.finished();
        log("Done");
    }
}
