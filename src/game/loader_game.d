module game.loader_game;

import game.loader;
import game.game;
import common.common;
import game.clientengine;
import common.scene;
import gui.gui;
import gui.widget;
import gui.container;
import game.gui.gameview;
import game.gui.gameframe;
import genlevel = levelgen.generator;
import utils.configfile;
import utils.log;

class GameLoader : Loader {
    private Log log;
    private GameFrame mGui;
    /+private+/ ConfigNode mConfig;

    //xxx allmost everything was moved to GameFrame

    this(ConfigNode config, GameFrame mgui) {
        log = registerLog("GameLoader");
        mConfig = config;
        mGui = mgui;
        registerChunk(&mGui.loadConfig);
        registerChunk(&mGui.initGameEngine);
        registerChunk(&mGui.initClientEngine);
        registerChunk(&mGui.initializeGameGui);
    }

    override void unload() {
        mGui.unloadGui();
        mGui.unloadGame();
        super.unload();
    }

    override void finished() {
        super.finished();
        log("Done");
    }
}
