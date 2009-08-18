module game.clientengine;

import framework.framework;
import framework.font;
import common.resset;
import framework.timesource;
import common.scene;
import common.common;
import common.visual;
import game.water;
import game.sky;
import game.animation;
import game.gamepublic;
import game.game;
import game.gfxset;
import game.glevel;
import game.sequence;
import game.particles;
import game.weapon.types;
import game.weapon.weapon;
import game.levelgen.level;
import game.levelgen.landscape;
import game.levelgen.renderer;
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



//------------------------------ Graphics ---------------------------------


class CrosshairGraphicImpl : SceneObject {
    private {
        CrosshairGraphic mInfo;
        Vector2f mDir; //normalized weapon direction
        Animator mTarget;
        float mTargetOffset;
        GfxSet mGfx;
        TimeSourcePublic timebase;
        InterpolateExp!(float, 4.25f) mInterp;
    }

    this(CrosshairGraphic info, GfxSet gfx) {
        zorder = GameZOrder.Crosshair;
        mGfx = gfx;
        mInfo = info;
        timebase = mInfo.owner.timebase;
        mTarget = new Animator(timebase);
        mTarget.setAnimation(mInfo.theme.aim);
        mInterp.currentTimeDg = &timebase.current;
        mInterp.init(mGfx.crosshair.animDur, 1, 0);
        mTargetOffset = mGfx.crosshair.targetDist -
            mGfx.crosshair.targetStartDist;
        reset();
    }

    void doDraw(Canvas canvas, Vector2i pos) {
        auto tcs = mGfx.crosshair;
        auto start = tcs.loadStart + tcs.radStart;
        auto abs_end = tcs.loadEnd - tcs.radEnd;
        auto scale = abs_end - start;
        auto end = start + cast(int)(scale*mInfo.load);
        auto rstart = start + 1; //omit first circle => invisible at mLoad=0
        float oldn = 0;
        int stip;
        auto cur = end;
        //NOTE: when firing, the load-colors look like they were animated;
        //  actually that's because the stipple-offset is changing when the
        //  mLoad value changes => stipple pattern moves with mLoad and the
        //  color look like they were changing
        while (cur >= rstart) {
            auto n = (1.0f*(cur-start)/scale);
            if ((stip % tcs.stipple)==0)
                oldn = n;
            auto col = tcs.colorStart + (tcs.colorEnd-tcs.colorStart)*oldn;
            auto rad = cast(int)(tcs.radStart+(tcs.radEnd-tcs.radStart)*n);
            canvas.drawFilledCircle(pos + toVector2i(mDir*cur), rad, col);
            cur -= tcs.add;
            stip++;
        }
    }

    //reset animation, called after this becomes .active again
    void reset() {
        mInterp.restart();
    }

    override void draw(Canvas c) {
        if (!mInfo.attach)
            return;
        if (mInfo.removed) {
            removeThis();
            return;
        }

        //NOTE: in this case, the readyflag is true, if the weapon is already
        // fully rotated into the target direction
        bool nactive = true; //mAttach.readyflag;
        if (mTarget.active != nactive) {
            mTarget.active = nactive;
            if (nactive)
                reset();
        }

        if (mInfo.doreset) {
            mInfo.doreset = false;
            reset();
        }

        auto infos = cast(WormSequenceUpdate)mInfo.attach;
        assert(!!infos,"Can only attach a target cross to worm sprites");
        auto pos = toVector2i(infos.position);
        auto angle = fullAngleFromSideAngle(infos.rotation_angle,
            infos.pointto_angle);
        mDir = Vector2f.fromPolar(1.0f, angle);
        //target cross animation
        //xxx reset on weapon change
        mTarget.pos = pos + toVector2i(mDir * (mGfx.crosshair.targetDist
            - mTargetOffset*mInterp.value));
        mTarget.params.p1 = cast(int)((angle + 2*PI*mInterp.value)*180/PI);

        mTarget.draw(c);
        doDraw(c, pos);
    }
}

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
    GameEngineGraphics server_graphics;

    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private {
        GameEngine mEngine;
        Music mMusic;

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
        TimeSource mParticleTime;

        class DrawParticles : SceneObject {
            override void draw(Canvas canvas) {
                //update state
                //engine.windSpeed is -1..1, don't ask me why
                mParticles.windSpeed = mEngine.windSpeed()*150f;
                mParticles.waterLine = mEngine.waterOffset();
                mParticleTime.paused = mEngineTime.paused;
                mParticleTime.update();
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
        cb.newGraphic ~= &doNewGraphic;
        cb.nukeSplatEffect ~= &nukeSplatEffect;

        //why not use mEngineTime? because higher/non-fixed framerate
        mParticleTime = new TimeSource("particles");
        mParticles = new ParticleWorld(mParticleTime);
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

        server_graphics = engine.getGraphics();
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
        mMusic = resources.get!(Music)("game");
        mMusic.play();
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
        foreach (Graphic g; server_graphics.objects) {
            engine.callbacks.newGraphic(g);
        }
    }

    private void doNewGraphic(Graphic g) {
        if (auto tc = cast(CrosshairGraphic)g) {
            scene.add(new CrosshairGraphicImpl(tc, gfx));
        } else if (auto txt = cast(TextGraphic)g) {
            //leave it to gameview.d (which adds its own newGraphic callback)
        } else {
            assert (false, "unknown type: "~g.toString());
        }
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

    //if this returns true, the one who calls .draw() will not clear the
    //background => return true if we overpaint everything anyway
    public bool needBackclear() {
        return !mGameSky.enableSkyTex;
    }

    void setSlowDown(float sd) {
        mEngineTime.slowDown = sd;
    }
}
