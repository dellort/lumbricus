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
import game.gfxset;
import game.glevel;
import game.sequence;
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

enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    Landscape,
    LevelWater,  //water before the level, but behind drowning objects
    Objects,
    Crosshair,
    Names, //what
    Clouds,
    FrontWater,
}


class ClientAnimationGraphic : Animator {
    AnimationGraphic mInfo;
    int last_set_ts = -1;

    this(AnimationGraphic info) {
        super(info.owner.timebase);
        zorder = GameZOrder.Objects;
        mInfo = info;
    }

    override void draw(Canvas c) {
        if (mInfo.removed) {
            removeThis();
            return;
        }
        pos = mInfo.pos;
        params = mInfo.params;
        if (mInfo.set_timestamp != last_set_ts) {
            setAnimation2(mInfo.animation, mInfo.animation_start);
            last_set_ts = mInfo.set_timestamp;
        }
        super.draw(c);
    }
}

class ClientLineGraphic : SceneObject {
    LineGraphic mInfo;

    this(LineGraphic info) {
        zorder = GameZOrder.Crosshair;
        mInfo = info;
    }

    override void draw(Canvas c) {
        if (mInfo.removed) {
            removeThis();
            return;
        }
        Surface tex = mInfo.texture.get();
        if (tex) {
            c.drawTexLine(mInfo.p1, mInfo.p2, tex, mInfo.texoffset,
                mInfo.color);
        } else {
            c.drawLine(mInfo.p1, mInfo.p2, mInfo.color, mInfo.width);
        }
    }
}

//version = DebugShowLandscape;

class LandscapeGraphicImpl : SceneObject {
    LandscapeGraphic mInfo;
    Surface bitmap;

    this(LandscapeGraphic info) {
        mInfo = info;
        zorder = GameZOrder.Landscape;
        bitmap = info.shared.image();
        bitmap.enableCaching(false);
    }

    void draw(Canvas c) {
        if (mInfo.removed) {
            removeThis();
            return;
        }
        c.draw(bitmap, mInfo.pos);
        version (DebugShowLandscape)
            c.drawRect(Rect2i.Span(mInfo.pos, bitmap.size), Color(1, 0, 0));
    }
}

class CrosshairImpl : SceneObject {
    private {
        Crosshair mInfo;
        Vector2f mDir; //normalized weapon direction
        Animator mTarget;
        float mTargetOffset;
        GfxSet mGfx;
        TimeSourcePublic timebase;
        InterpolateExp!(float, 4.25f) mInterp;
    }

    this(Crosshair info, GfxSet gfx) {
        zorder = GameZOrder.Crosshair;
        mGfx = gfx;
        mInfo = info;
        timebase = mInfo.owner.timebase;
        mTarget = new Animator(timebase);
        mTarget.setAnimation(mInfo.theme.aim.get);
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
        auto pos = infos.position;
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

//creates shockwave-animation for an explosion (like in wwp)
//currently creates no particles, but could in the future
class ExplosionGfxImpl : SceneObjectCentered {
    private {
        Animator mShockwave1, mShockwave2, mComicText;
        int mDiameter;
        GfxSet mGfx;
    }

    this(TimeSourcePublic ts, GfxSet gfx, Vector2i a_pos, int diameter) {
        zorder = GameZOrder.Crosshair;
        mGfx = gfx;
        mShockwave1 = new Animator(ts);
        mShockwave2 = new Animator(ts);
        mComicText = new Animator(ts);
        auto p = a_pos;
        mShockwave1.pos = p;
        mShockwave2.pos = p;
        mComicText.pos = p;
        //mShockwave1.timeSource = mInfo.owner.timebase;
        //mShockwave2.timeSource = mInfo.owner.timebase;
        //mComicText.timeSource = mInfo.owner.timebase;

        setDiameter(diameter);
    }

    //selects animations matching diameter
    //diameter tresholds are read from gfxset config file
    void setDiameter(int d) {
        int s = -1, t = -1;
        if (d < mGfx.expl.sizeTreshold[0]) {
            //below treshold, no animation
            //xxx catch this case in engine to avoid network traffic
        } else if (d < mGfx.expl.sizeTreshold[1]) {
            //tiny explosion without text
            s = 0;
        } else if (d < mGfx.expl.sizeTreshold[2]) {
            //medium-sized, may have small text
            s = 1;
            t = rngShared.next(-1,3);
        } else if (d < mGfx.expl.sizeTreshold[3]) {
            //big, always with text
            s = 2;
            t = rngShared.next(0,4);
        } else {
            //huge, always text
            s = 3;
            t = rngShared.next(0,4);
        }
        if (s >= 0) {
            mShockwave1.setAnimation(mGfx.expl.shockwave1[s].get);
            mShockwave2.setAnimation(mGfx.expl.shockwave2[s].get);
        }
        if (t >= 0) {
            mComicText.setAnimation(mGfx.expl.comicText[t].get);
        }
    }

    override void draw(Canvas c) {
        //self-remove after all animations are finished
        if ((mShockwave1.hasFinished && mShockwave2.hasFinished &&
            mComicText.hasFinished))
        {
            removeThis();
        }
        mShockwave1.draw(c);
        mShockwave2.draw(c);
        mComicText.draw(c);
    }
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine : GameEngineCallback {
    private GameEnginePublic mEngine;

    ResourceSet resources;
    GfxSet gfx;
    GameEngineGraphics server_graphics;
    ulong server_graphics_last_checked_frame;

    private Music mMusic;

    //stuff cached/received/duplicated from the engine
    //(remind that mEngine might disappear because of networking)
    int waterOffset;
    float windSpeed;
    //worldCenter: don't really know what it is, used for camera start position
    Vector2i worldSize, worldCenter;

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private Scene mScene;

    //normal position of the scenes nested in mScene
    private Rect2i mSceneRect;

    private TimeSource mEngineTime;

    private GameWater mGameWater;
    private GameSky mGameSky;

    //when shaking, the current offset
    private Vector2i mShakeOffset;
    //time after which a new shake offset is computed (to make shaking framerate
    //  independent), in ms
    const cShakeIntervalMs = 50;
    private Time mLastShake;

    private PerfTimer mGameDrawTime;

    this(GameEnginePublic engine) {
        mEngine = engine;
        gfx = engine.gfx;
        resources = gfx.resources;

        mEngine.addCallback(this);

        mEngineTime = new TimeSource("ClientEngine");
        mEngineTime.paused = true;

        mGameDrawTime = globals.newTimer("game_draw_time");

        //xxx make value transfers generic
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        worldSize = mEngine.worldSize;
        worldCenter = mEngine.worldCenter;

        mScene = new Scene();

        mSceneRect = Rect2i(Vector2i(0), worldSize);

        readd_graphics();

        initSound();
    }

    //actually start the game (called after resources were preloaded)
    void start() {
        mEngineTime.paused = false;
    }

    void readd_graphics() {
        mScene.clear();

        //xxx
        mGameWater = new GameWater(this);
        mGameSky = new GameSky(this);

        detailLevel = 0;

        server_graphics = engine.getGraphics();
        server_graphics_last_checked_frame = 0;
        //in case the game is reloaded
        updateGraphics();
    }

    TimeSourcePublic engineTime() {
        return mEngineTime;
    }

    GameEnginePublic engine() {
        return mEngine;
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
    private void updateGraphics() {
        void add(SceneObject s) {
            scene.add(s);
        }

        assert (server_graphics.last_objects_frame
            >= server_graphics_last_checked_frame);

        if (server_graphics.last_objects_frame
            == server_graphics_last_checked_frame)
        {
            return;
        }

        foreach (Graphic g; server_graphics.objects) {
            if (g.removed)
                continue;
            //already has been added
            if (g.frame_added <= server_graphics_last_checked_frame)
                continue;
            //urghs, but interface methods (like .createAnimation()) can't be
            //used when loading from a saved game
            if (auto ani = cast(AnimationGraphic)g) {
                add(new ClientAnimationGraphic(ani));
            } else if (auto line = cast(LineGraphic)g) {
                add(new ClientLineGraphic(line));
            } else if (auto land = cast(LandscapeGraphic)g) {
                add(new LandscapeGraphicImpl(land));
            } else if (auto tc = cast(Crosshair)g) {
                add(new CrosshairImpl(tc, gfx));
            } else {
                assert (false, "unknown type: "~g.toString());
            }
        }

        server_graphics_last_checked_frame
            = server_graphics.last_objects_frame;
    }

    //-- interface GameEngineCallback

    void damage(Vector2i pos, int radius, bool explode) {
        if (explode) {
            scene.add(new ExplosionGfxImpl(engineTime, gfx, pos, radius*2));
        }
    }

    //not interested, see gameframe.d
    void showMessage(LocalizedMessage msg) {
    }
    void weaponsChanged(Team t) {
    }

    //-- end interface

    bool oldpause; //hack, so you can pause the music independent from the game

    void doFrame() {
        //lol pause state
        auto ispaused = mEngine.paused();
        mEngineTime.paused = ispaused;
        mEngineTime.update();

        if (mMusic) {
            if (oldpause != ispaused)
                mMusic.paused = ispaused;
            oldpause = ispaused;
        }

        updateGraphics();

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
        mScene.pos = mSceneRect.p1 + mShakeOffset;

        //hm
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        mGameWater.simulate();
        mGameSky.simulate();
    }

    Scene scene() {
        return mScene;
    }

    void draw(Canvas canvas) {
        mGameDrawTime.start();
        mScene.draw(canvas);
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
