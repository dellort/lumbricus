module game.clientengine;

import framework.framework;
import framework.font;
import common.resset;
import framework.sound;
import utils.timesource;
import common.scene;
import common.common;
import game.core;
import game.water;
import game.sky;
import game.temp : GameZOrder;
import game.game;
import game.particles;
import utils.list2;
import utils.time;
import utils.math;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.perf;
import utils.configfile;
import utils.random : rngShared;
import utils.interpolate;
import tango.math.Math : PI, pow;


//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine {
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private {
        GameEngine mEngine;
        Source mMusic;

        uint mDetailLevel;

        GameWater mGameWater;
        GameSky mGameSky;

        //when shaking, the current offset
        Vector2i mShakeOffset;
        //time after which a new shake offset is computed (to make shaking
        //  framerate independent), in ms
        const cShakeIntervalMs = 50;
        Time mLastShake;

        PerfTimer mGameDrawTime;
        bool mPaused;
    }

    this(GameCore engine) {
        mEngine = GameEngine.fromCore(engine);

        //newTimer resets time every second to calculate average times
        //mGameDrawTime = globals.newTimer("game_draw_time");
        mGameDrawTime = new PerfTimer(true);

        initSound();

        mEngine.getRenderTime = &do_getRenderTime;

        //xxx
        mGameWater = new GameWater(mEngine);
        mGameSky = new GameSky(mEngine);

        detailLevel = 0;
    }

    GameCore engine() {
        return mEngine;
    }

    void kill() {
        mMusic.stop();
    }

    private void initSound() {
        auto mus = engine.resources.get!(Sample)("game");
        mMusic = mus.createSource();
        mMusic.looping = true;
        mMusic.play();
    }

    void fadeoutMusic(Time t) {
        mMusic.stop(t);
    }

    bool paused() {
        return mPaused;
    }
    void paused(bool p) {
        mPaused = p;
    }

    bool oldpause; //hack, so you can pause the music independent from the game

    void doFrame() {
        if (mMusic) {
            if (oldpause != mPaused)
                mMusic.paused = mPaused;
            oldpause = mPaused;
        }

        //bail out here if game is paused??

        Time curtime = mEngine.interpolateTime.current;
        if ((curtime - mLastShake).msecs >= cShakeIntervalMs) {
            //something similar is being done in earthquake.d
            //the point of not using the physic's value is to reduce client-
            //  server communication a bit

            //100f? I don't know what it means, but it works (kind of)
            auto shake = Vector2f.fromPolar(1.0f, rngShared.nextDouble()*PI*2)
                * (mEngine.earthQuakeStrength()/100f);
            mShakeOffset = toVector2i(shake);

            mLastShake = curtime;
        }

        mGameWater.simulate();
        mGameSky.simulate();
    }

    Scene scene() {
        return mEngine.scene;
    }

    void draw(Canvas canvas) {
        mGameDrawTime.start();
        canvas.pushState();
        canvas.translate(mShakeOffset);
        mEngine.scene.draw(canvas);
        canvas.popState();
        mGameDrawTime.stop();
    }

    Time do_getRenderTime() {
        return mGameDrawTime.time();
    }

    public uint detailLevel() {
        return mDetailLevel;
    }
    //the higher the less detail (wtf), wraps around if set too high
    public void detailLevel(uint level) {
        level = level % 8;
        mDetailLevel = level;
        bool clouds = true, skyDebris = true, skyBackdrop = true, skyTex = true,
             water = true, gui = true, particles = true;
        if (level >= 1) skyDebris = false;
        if (level >= 2) skyBackdrop = false;
        if (level >= 3) skyTex = false;
        if (level >= 4) clouds = false;
        if (level >= 5) water = false;
        if (level >= 6) gui = false;
        if (level >= 7) particles = false;
        mGameWater.simpleMode = !water;
        mGameSky.enableClouds = clouds;
        mGameSky.enableDebris = skyDebris;
        mGameSky.enableSkyBackdrop = skyBackdrop;
        mGameSky.enableSkyTex = skyTex;
        enableSpiffyGui = gui;
        mEngine.particleWorld.enabled = particles;
    }

    //if this returns true, the one who calls .draw() will not clear the
    //background => return true if we overpaint everything anyway
    public bool needBackclear() {
        return !mGameSky.enableSkyTex;
    }
}
