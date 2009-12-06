module game.clientengine;

import framework.framework;
import framework.font;
import common.resset;
import framework.sound;
import framework.timesource;
import common.scene;
import common.common;
import game.water;
import game.sky;
import game.temp : GameZOrder;
import game.game;
import game.gfxset;
import game.glue;
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




//------------------------------ Effects ---------------------------------


class NukeSplatEffectImpl : SceneObject {
    static float nukeFlash(float A)(float x) {
        if (x < A)
            return interpExponential!(6.0f)(x/A);
        else
            return interpExponential2!(4.5f)((1.0f-x)/(1.0f-A));
    }

    private {
        InterpolateFnTime!(float, nukeFlash!(0.01f)) mInterp;
    }

    this() {
        zorder = GameZOrder.Splat;
        mInterp.init(timeMsecs(3500), 0, 1.0f);
    }

    override void draw(Canvas c) {
        if (!mInterp.inProgress()) {
            removeThis();
            return;
        }
        c.drawFilledRect(c.visibleArea(),
            Color(1.0f, 1.0f, 1.0f, mInterp.value()));
    }
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine : GameEngineCallback {
    ResourceSet resources;
    GfxSet gfx;

    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private {
        GameEngine mEngine;
        Source mMusic;

        uint mDetailLevel;

        Scene mLocalScene;
        SceneZMix mUberScene;

        //normal position of the scenes nested in mScene
        Rect2i mSceneRect;

        TimeSource mEngineTime;

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

        ParticleWorld mParticles;
        bool mEnableParticles = true;

        class DrawParticles : SceneObject {
            override void draw(Canvas canvas) {
                if (!mEnableParticles)
                    return;
                //update state
                //engine.windSpeed is -1..1, don't ask me why
                mParticles.windSpeed = mEngine.windSpeed()*150f;
                mParticles.waterLine = mEngine.waterOffset();
                mParticles.paused = mEngineTime.paused;
                //simulate & draw
                mParticles.draw(canvas);
            }
        }
    }

    this(GameEngine engine) {
        mEngine = engine;
        gfx = engine.gfx;
        resources = gfx.resources;

        mEngineTime = new TimeSource("ClientEngine");
        mEngineTime.paused = true;

        mGameDrawTime = globals.newTimer("game_draw_time");

        mLocalScene = new Scene();
        mUberScene = new SceneZMix();

        mSceneRect = mEngine.level.worldBounds;

        initSound();

        auto cb = mEngine.callbacks();
        cb.nukeSplatEffect ~= &nukeSplatEffect;

        //why not use mEngineTime? because higher/non-fixed framerate
        mParticles = new ParticleWorld();
        cb.particleEngine = mParticles;

        readd_graphics();
    }

    //actually start the game (called after resources were preloaded)
    void start() {
        mEngineTime.paused = false;
    }

    void readd_graphics() {
        mUberScene.clear();
        mLocalScene.clear();
        mUberScene.add(mLocalScene);

        mUberScene.add(mEngine.scene);
        mUberScene.add(mEngine.callbacks.scene);

        //xxx
        mGameWater = new GameWater(this);
        mGameSky = new GameSky(this);

        SceneObject particles = new DrawParticles();
        particles.zorder = GameZOrder.Particles;
        mLocalScene.add(particles);

        detailLevel = 0;

        createGraphics();
    }

    TimeSourcePublic engineTime() {
        return mEngineTime;
    }

    GameEngine engine() {
        return mEngine;
    }

    ParticleWorld particles() {
        return mParticles;
    }

    void kill() {
        mMusic.stop();
    }

    private void initSound() {
        auto mus = resources.get!(Sample)("game");
        mMusic = mus.createSource();
        mMusic.looping = true;
        mMusic.play();
    }

    void fadeoutMusic(Time t) {
        mMusic.stop(t);
    }

    //synchronize graphics list
    //graphics currently are removed lazily using the "removed" flag
    private void createGraphics() {
        //this case is when:
        // 1. creating a new game; the game engine is created first, and during
        //    initialization, the engine might want to create new graphics, but
        //    the client engine isn't here yet and can't listen to the callbacks
        // 2. loading from savegames
        // 3. resuming snapshots
        //but maybe this should be moved to gemashell.d
        // - lol nothing here anymore
    }

    private void nukeSplatEffect() {
        scene.add(new NukeSplatEffectImpl());
    }

    bool paused() {
        return mPaused;
    }
    void paused(bool p) {
        mPaused = p;
    }

    bool oldpause; //hack, so you can pause the music independent from the game

    void doFrame() {
        //lol pause state
        mEngineTime.paused = mPaused;
        mEngineTime.update();

        if (mMusic) {
            if (oldpause != mPaused)
                mMusic.paused = mPaused;
            oldpause = mPaused;
        }

        //bail out here if game is paused??

        if ((mEngineTime.current - mLastShake).msecs >= cShakeIntervalMs) {
            //something similar is being done in earthquake.d
            //the point of not using the physic's value is to reduce client-
            //  server communication a bit

            //100f? I don't know what it means, but it works (kind of)
            auto shake = Vector2f.fromPolar(1.0f, rngShared.nextDouble()*PI*2)
                * (mEngine.earthQuakeStrength()/100f);
            mShakeOffset = toVector2i(shake);

            mLastShake = mEngineTime.current;
        }

        //only these are shaked on an earth quake
        //...used to shake only Objects and Landscape, but now it's ok too
        mUberScene.pos = mSceneRect.p1 + mShakeOffset;

        mGameWater.simulate();
        mGameSky.simulate();
    }

    Scene scene() {
        return mLocalScene;
    }

    void setViewArea(Rect2i rc) {
        mParticles.setViewArea(rc);
    }

    void draw(Canvas canvas) {
        mGameDrawTime.start();
        mUberScene.draw(canvas);
        mGameDrawTime.stop();
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
        mEnableParticles = particles;
        //set particle count to 0 to disable particle system
        if (mEnableParticles != (mParticles.particleCount() > 0)) {
            if (mEnableParticles) {
                mParticles.reinit();
            } else {
                mParticles.reinit(0);
            }
        }
    }

    //if this returns true, the one who calls .draw() will not clear the
    //background => return true if we overpaint everything anyway
    public bool needBackclear() {
        return !mGameSky.enableSkyTex;
    }

    void setSlowDown(float sd) {
        mEngineTime.slowDown = sd;
    }
}
