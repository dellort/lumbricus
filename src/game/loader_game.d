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

class GameLoader : Loader {
    private ConfigNode mConfig;
    private GameConfig mGameConfig;
    private GuiMain mGui;
    //xxx replace this by a GuiFrame thing or so
    private GuiObject[] mGameGuiObjects;
    private bool mGameGuiOpened;

    GameEngine thegame;
    ClientGameEngine clientengine;
    GameView gameView;
    Scene metascene;

    this(ConfigNode config, GuiMain mgui) {
        mConfig = config;
        mGui = mgui;
        registerChunk(&unloadGui);
        registerChunk(&unloadGame);
        registerChunk(&loadConfig);
        registerChunk(&initGameEngine);
        registerChunk(&initClientEngine);
        registerChunk(&initializeGameGui);
    }

    private bool unloadGui() {
        if (mGameGuiOpened) {
            //xxx implement correct focus handling
            mGui.setFocus(null);
            assert(gameView !is null);
            assert(mGui !is null);
            gameView.gamescene = null;
            gameView.controller = null;
            foreach (GuiObject o; mGameGuiObjects) {
                //should be enough
                o.active = false;
            }
            mGameGuiObjects = null;
            gameView = null;

            mGameGuiOpened = false;
        }

        return true;
    }

    private bool unloadGame() {
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
        thegame = new GameEngine(mGameConfig);

        return true;
    }

    private bool initClientEngine() {
        //resetTime();
        //xxx README: since the scene is recreated for each level, there's no
        //            need to remove them all in Game.kill()
        clientengine = new ClientGameEngine(thegame);
        metascene = new MetaScene([clientengine.scene]);

        //yes, really twice, as no game time should pass while loading stuff
        //resetTime();

        //callback when invoking cmdStop
        //mOnStopGui = &closeGame;

        return true;
    }

    private bool initializeGameGui() {
        mGameGuiOpened = true;

        void addGui(GuiObject obj) {
            mGui.add(obj, GUIZOrder.Gui);
            mGameGuiObjects ~= obj;
        }

        addGui(new WindMeter(clientengine));
        addGui(new GameTimer(clientengine));
        addGui(new PrepareDisplay(clientengine));
        auto msg = new MessageViewer();
        addGui(msg);

        thegame.controller.messageCb = &msg.addMessage;
        thegame.controller.messageIdleCb = &msg.idle;

        gameView = new GameView(clientengine);
        gameView.loadBindings(globals.loadConfig("wormbinds")
            .getSubNode("binds"));
        mGui.add(gameView, GUIZOrder.Game);
        mGameGuiObjects ~= gameView;
        //xxx no focus changes yet
        mGui.setFocus(gameView);

        gameView.controller = thegame.controller;
        gameView.gamescene = metascene;

        //start at level center
        gameView.view.scrollCenterOn(thegame.gamelevel.offset
            + thegame.gamelevel.size/2, true);

        return true;
    }
}
