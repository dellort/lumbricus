module game.clientengine;

import framework.framework;
import framework.font;
import framework.resset;
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
import utils.random : random;
import std.math : PI, pow;

enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    Landscape,
    LevelWater,  //water before the level, but behind drowning objects
    Objects,
    TargetCross,
    Names, //what
    Clouds,
    FrontWater,
}


class ClientAnimationGraphic : Animator {
    AnimationGraphic mInfo;
    int last_set_ts = -1;

    this(AnimationGraphic info) {
        zorder = GameZOrder.Objects;
        mInfo = info;
        timeSource = mInfo.owner.timebase;
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
        zorder = GameZOrder.TargetCross;
        mInfo = info;
    }

    override void draw(Canvas c) {
        if (mInfo.removed) {
            removeThis();
            return;
        }
        c.drawLine(mInfo.p1, mInfo.p2, mInfo.color);
    }
}

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
    }
}

class TargetCrossImpl : SceneObject {
    private {
        TargetCross mInfo;
        Vector2f mDir; //normalized weapon direction
        Animator mTarget;
        float mTargetOffset;
        float mRotationOffset;
        GfxSet mGfx;
        TimeSource timebase;
    }

    this(TargetCross info, GfxSet gfx) {
        zorder = GameZOrder.TargetCross;
        mGfx = gfx;
        mInfo = info;
        timebase = mInfo.owner.timebase;
        mTarget = new Animator();
        mTarget.timeSource = timebase;
        mTarget.setAnimation(mInfo.theme.aim.get);
        reset();
    }

    void doDraw(Canvas canvas, Vector2i pos) {
        auto tcs = mGfx.targetCross;
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
        mTargetOffset = mGfx.targetCross.targetDist -
            mGfx.targetCross.targetStartDist;
        mRotationOffset = PI*2;
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
        mTarget.pos = pos + toVector2i(mDir
            * (mGfx.targetCross.targetDist - mTargetOffset));
        mTarget.params.p1 = cast(int)((angle + mRotationOffset)*180/PI);

        //target cross animation
        //xxx reset on weapon change
        if (mTargetOffset > 0.25f) {
            auto deltaT = timebase.difference.secsf;
            auto decrease = (pow(mGfx.targetCross.targetDegrade,
                deltaT*1000.0f));
            mTargetOffset *= decrease;
            mRotationOffset *= decrease;
        }

        mTarget.draw(c);
        doDraw(c, pos);
    }
}

//creates shockwave-animation for an explosion (like in wwp)
//currently creates no particles, but could in the future
class ExplosionGfxImpl : SceneObjectCentered {
    private {
        ExplosionGfx mInfo;
        Animator mShockwave1, mShockwave2, mComicText;
        int mDiameter;
        GfxSet mGfx;
    }

    this(ExplosionGfx info, GfxSet gfx) {
        zorder = GameZOrder.TargetCross;
        mGfx = gfx;
        mInfo = info;
        mShockwave1 = new Animator();
        mShockwave2 = new Animator();
        mComicText = new Animator();
        auto p = mInfo.pos;
        mShockwave1.pos = p;
        mShockwave2.pos = p;
        mComicText.pos = p;
        mShockwave1.timeSource = mInfo.owner.timebase;
        mShockwave2.timeSource = mInfo.owner.timebase;
        mComicText.timeSource = mInfo.owner.timebase;

        setDiameter(mInfo.diameter);
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
            t = random(-1,3);
        } else if (d < mGfx.expl.sizeTreshold[3]) {
            //big, always with text
            s = 2;
            t = random(0,4);
        } else {
            //huge, always text
            s = 3;
            t = random(0,4);
        }
        Time st = mInfo.start;
        if (s >= 0) {
            mShockwave1.setAnimation2(mGfx.expl.shockwave1[s].get, st);
            mShockwave2.setAnimation2(mGfx.expl.shockwave2[s].get, st);
        }
        if (t >= 0) {
            mComicText.setAnimation2(mGfx.expl.comicText[t].get, st);
        }
    }

    override void draw(Canvas c) {
        //self-remove after all animations are finished
        if ((mShockwave1.hasFinished && mShockwave2.hasFinished &&
            mComicText.hasFinished) || mInfo.removed)
        {
            removeThis();
            //uh, how strange (but it wasn't my idea ;D)
            mInfo.remove();
        }
        mShockwave1.draw(c);
        mShockwave2.draw(c);
        mComicText.draw(c);
    }

    override Rect2i bounds() {
        return Rect2i.Empty();
    }
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine {
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

    this(GameEnginePublic engine, GfxSet a_gfx) {
        mEngine = engine;
        gfx = a_gfx;
        resources = gfx.resources;

        mEngineTime = new TimeSource();
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

        detailLevel = 0;

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
            } else if (auto tc = cast(TargetCross)g) {
                add(new TargetCrossImpl(tc, gfx));
            } else if (auto eg = cast(ExplosionGfx)g) {
                add(new ExplosionGfxImpl(eg, gfx));
            } else {
                assert (false, "unknown type: "~g.toString());
            }
        }

        server_graphics_last_checked_frame
            = server_graphics.last_objects_frame;
    }

    bool oldpause; //hack, so you can pause the music independent from the game

    void doFrame() {
        //lol pause state
        auto ispaused = mEngine.paused();
        engineTime.paused = ispaused;
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
            auto shake = Vector2f.fromPolar(1.0f, random()*PI*2)
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
}
