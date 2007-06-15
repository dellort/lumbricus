module game.clientengine;

import game.gobject;
import game.physic;
import game.baseengine;
import game.scene;
import game.game;
import game.water;
import game.sky;
import utils.mylist;
import utils.time;

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine : BaseGameEngine {
    private GameEngine mEngine;

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private Scene mScene;

    private GameWater mGameWater;
    private GameSky mGameSky;

    this(GameEngine engine) {
        mEngine = engine;

        mScene = new Scene();
        mScene.size = mEngine.scene.size;

        mGameWater = new GameWater(this, mEngine, mScene, "blue");
        mGameSky = new GameSky(this, mEngine, mScene);

        detailLevel = 0;
    }

    Scene scene() {
        return mScene;
    }

    public uint detailLevel() {
        return mDetailLevel;
    }
    //the higher the less detail (wtf), wraps around if set too high
    public void detailLevel(uint level) {
        level = level % 7;
        mDetailLevel = level;
        bool clouds = true, skyDebris = true, skyBackdrop = true, skyTex = true;
        bool water = true, gui = true;
        if (level >= 1) skyDebris = false;
        if (level >= 2) skyBackdrop = false;
        if (level >= 3) skyTex = false;
        if (level >= 4) clouds = false;
        if (level >= 5) water = false;
        if (level >= 6) gui = false;
        mGameWater.simpleMode = !water;
        mGameSky.enableClouds = clouds;
        mGameSky.enableDebris = skyDebris;
        mGameSky.enableSkyBackdrop = skyBackdrop;
        mGameSky.enableSkyTex = skyTex;
        enableSpiffyGui = gui;
    }
}
