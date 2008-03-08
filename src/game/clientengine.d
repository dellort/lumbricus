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
import game.sequence;
import game.levelgen.level;
import game.levelgen.landscape;
import game.levelgen.renderer;
import utils.mylist;
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

class ClientGraphic : Graphic {
    private mixin ListNodeMixin node;
    //if handler is null, this means it has been removed
    GraphicsHandler handler;

    //subclass must call init() after it has run its constructor
    this(GraphicsHandler a_owner) {
        handler = a_owner;
    }

    Scene container() {
        return handler ? handler.zScenes[zorder()] : null;
    }

    bool active() {
        return !!handler;
    }

    //stupid enforced constructor order...
    protected void init() {
        container().add(graphic);
        handler.mGraphics.insert_tail(this);
    }

    //NOTE: due to some stupidity, objects can never be added to the scene again
    //you must recreate them
    void remove() {
        if (!handler)
            return;
        handler.mGraphics.remove(this);
        container().remove(graphic);
        handler = null;
    }

    abstract SceneObject graphic();

    //called per frame
    //can be overridden, by default does nothing
    void simulate(float deltaT) {
    }

    //this is my new, slightly retarded way of maintaining a zorder
    //the function must always return the same zorder value for the same
    //instance
    //I'll keep this hack as long as I get sick of it and move the zorder thing
    //back to common.scene zorder
    int zorder() {
        return GameZOrder.Objects;
    }
}

class ClientLineGraphic : ClientGraphic, LineGraphic {
    Vector2i mP1, mP2;
    Color mColor;
    Draw mDraw;

    class Draw : SceneObject {
        override void draw(Canvas c) {
            c.drawLine(mP1, mP2, mColor);
        }
    }

    this(GraphicsHandler handler) {
        super(handler);
        mDraw = new Draw();
        init();
    }

    void setPos(Vector2i p1, Vector2i p2) {
        mP1 = p1;
        mP2 = p2;
    }
    void setColor(Color c) {
        mColor = c;
    }

    SceneObject graphic() {
        return mDraw;
    }

    Rect2i bounds() {
        //doesn't make a lot of sense, but meh
        auto rc = Rect2i(mP1, mP2);
        rc.normalize();
        return rc;
    }
}

class LandscapeGraphicImpl : ClientGraphic, LandscapeGraphic {
    LevelLandscape mSource;
    LandscapeBitmap mBitmap;
    bool mBitmapIsShared;
    Vector2i mPos;
    LandscapeDrawer mRender;

    this(GraphicsHandler handler, LevelLandscape from, LandscapeBitmap shared) {
        //NOTE: simply can set shared to null to test the not-shared case
        //shared = null;
        super(handler);
        mSource = from;
        mBitmap = shared;
        mBitmapIsShared = mBitmap !is null;
        if (!mBitmapIsShared) {
            mBitmap = new LandscapeBitmap(mSource.landscape);
        }
        mRender = new LandscapeDrawer();
        mRender.bitmap = mBitmap.image();
        mRender.bitmap.enableCaching(false);
        init();
    }

    SceneObject graphic() {
        return mRender;
    }

    void setPos(Vector2i p) {
        mPos = p;
    }

    void damage(Vector2i pos, int radius) {
        if (mBitmapIsShared)
            return;
        //NOTE: clipping should have been done by the caller already, and the
        // blastHole function also does clip; so don't care
        //xxx but this method call is still duplicated from glevel.d
        mBitmap.blastHole(pos, radius, cBlastBorder);
    }

    void insert(Vector2i pos, Resource!(Surface) bitmap) {
        if (mBitmapIsShared)
            return;
        Surface bmp = bitmap.get();
        //whatever the size param is for
        //the metadata-handling is hardcoded, which is a shame
        //currently overwrite everything except SolidHard pixels
        //xxx also duplicated from glevel.d argh
        mBitmap.drawBitmap(pos, bmp, bmp.size, ~Lexel.SolidHard, 0,
            Lexel.SolidSoft);
    }

    //all hail to inner classes
    private class LandscapeDrawer : SceneObject {
        Surface bitmap;

        void draw(Canvas c) {
            c.draw(bitmap, mPos);
        }
    }

    override int zorder() {
        return GameZOrder.Landscape;
    }

    Rect2i bounds() {
        return Rect2i(mBitmap.size()) + mPos;
    }
}

class TargetCrossImpl : ClientGraphic, TargetCross {
    private {
        Sequence mAttach;
        float mLoad = 0.0f;
        Vector2f mDir; //normalized weapon direction
        Animator mTarget;
        Scene mContainer; //(0,0) positioned to worm center
        float mTargetOffset;
    }

    class DrawWeaponLoad : SceneObject {
        void draw(Canvas canvas) {
            auto tcs = handler.gfx.targetCross;
            auto start = tcs.loadStart + tcs.radStart;
            auto abs_end = tcs.loadEnd - tcs.radEnd;
            auto scale = abs_end - start;
            auto end = start + cast(int)(scale*mLoad);
            auto cur = start + 1; //omit first circle => invisible at mLoad=0
            float oldn = 0;
            int stip;
            while (cur <= end) {
                auto n = (1.0f*(cur-start)/scale);
                if ((stip % tcs.stipple)==0)
                    oldn = n;
                auto col = tcs.colorStart + (tcs.colorEnd-tcs.colorStart)*oldn;
                auto rad = cast(int)(tcs.radStart+(tcs.radEnd-tcs.radStart)*n);
                canvas.drawFilledCircle(toVector2i(mDir*cur), rad, col);
                cur += tcs.add;
                stip++;
            }
        }
    }

    this(GraphicsHandler handler, TeamTheme team) {
        super(handler);
        mContainer = new Scene();
        mTarget = new Animator();
        mTarget.setAnimation(team.aim.get);
        mContainer.add(mTarget);
        mContainer.add(new DrawWeaponLoad());
        reset();
        init();
    }

    SceneObject graphic() {
        return mContainer;
    }

    //NOTE: I was a bit careless about the "attaching" thing
    // it doesn't work correctly if the attached object is created before the
    // attach-to object
    void attach(Sequence dest) {
        mAttach = dest;
    }

    //reset animation, called after this becomes .active again
    void reset() {
        mTargetOffset = handler.gfx.targetCross.targetDist -
            handler.gfx.targetCross.targetStartDist;
    }

    override void simulate(float deltaT) {
        if (!mAttach)
            return;
        SequenceUpdate infos;
        mAttach.getInfos(infos);
        mContainer.pos = infos.position;
        auto angle = fullAngleFromSideAngle(infos.rotation_angle,
            infos.pointto_angle);
        mDir = Vector2f.fromPolar(1.0f, angle);
        mTarget.pos = toVector2i(mDir
            * (handler.gfx.targetCross.targetDist - mTargetOffset));
        mTarget.params.p1 = cast(int)(angle*180/PI);

        bool nactive = mAttach.readyflag;
        if (mTarget.active != nactive) {
            mTarget.active = nactive;
            if (nactive)
                reset();
        }

        //target cross animation
        //xxx reset on weapon change
        if (mTargetOffset > 0.25f)
            mTargetOffset *= (pow(handler.gfx.targetCross.targetDegrade,
                deltaT*1000.0f));
    }

    void setLoad(float load) {
        mLoad = load;
    }

    Rect2i bounds() {
        return Rect2i.Empty();
    }

    override int zorder() {
        return GameZOrder.TargetCross;
    }
}

class GraphicsHandler : GameEngineGraphics {
    private List!(ClientGraphic) mGraphics;

    //of course this is unclean, sucks, etc.
    Scene[GameZOrder.max+1] zScenes;
    Scene allScene;
    GfxSet gfx;

    this(GfxSet a_gfx) {
        mGraphics = new typeof(mGraphics)(ClientGraphic.node.getListNodeOffset());
        allScene = new Scene();
        foreach (ref s; zScenes) {
            s = new Scene();
            allScene.add(s);
        }
        gfx = a_gfx;
    }

    //call simulate() for all objects
    void simulate(float deltaT) {
        foreach (g; mGraphics) {
            g.simulate(deltaT);
        }
    }

    Sequence createSequence(SequenceObject type) {
        assert(!!type);
        return type.instantiate(this); //yay factory
    }
    LineGraphic createLine() {
        return new ClientLineGraphic(this);
    }
    TargetCross createTargetCross(TeamTheme team) {
        return new TargetCrossImpl(this, team);
    }
    LandscapeGraphic createLandscape(LevelLandscape from,
        LandscapeBitmap shared)
    {
        return new LandscapeGraphicImpl(this, from, shared);
    }
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine {
    private GameEnginePublic mEngine;

    ResourceSet resources;
    GfxSet gfx;
    GraphicsHandler graphics;

    //stuff cached/received/duplicated from the engine
    //(remind that mEngine might disappear because of networking)
    int waterOffset;
    float windSpeed;
    Vector2i levelOffset, worldSize;

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private Scene mScene;
    private Scene[GameZOrder.max+1] mZScenes;

    //normal position of the scenes nested in mScene
    private Rect2i mSceneRect;

    private TimeSource mEngineTime;

    private GameWater mGameWater;
    private GameSky mGameSky;

    //when shaking, the current offset
    private Vector2i mShakeOffset;
    //time after which a new shake offset is computed (to make shaking framerate
    //  independent), in ms
    const cShakeIntervalMs = 100;
    private Time mLastShake;

    private PerfTimer mGameDrawTime;

    this(GameEnginePublic engine, GfxSet a_gfx, GraphicsHandler foo) {
        mEngine = engine;
        gfx = a_gfx;
        resources = gfx.resources;
        graphics = foo;

        mGameDrawTime = globals.newTimer("game_draw_time");

        //xxx make value transfers generic
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        worldSize = mEngine.worldSize;

        mScene = graphics.allScene;

        //attention: be sure to keep the order
        //never remove or reinsert items frm the mScene
        foreach(int i, inout Scene s; mZScenes) {
            s = graphics.zScenes[i];
        }

        mSceneRect = Rect2i(Vector2i(0), worldSize);

        mGameWater = new GameWater(this);
        mZScenes[GameZOrder.BackWater].add(mGameWater.scenes[GameWater.Z.back]);
        mZScenes[GameZOrder.LevelWater].add(mGameWater.scenes[GameWater.Z.level]);
        mZScenes[GameZOrder.FrontWater].add(mGameWater.scenes[GameWater.Z.front]);

        mGameSky = new GameSky(this);
        mZScenes[GameZOrder.Background].add(mGameSky.scenes[GameSky.Z.back]);
        mZScenes[GameZOrder.BackLayer].add(mGameSky.scenes[GameSky.Z.debris]);
        mZScenes[GameZOrder.Clouds].add(mGameSky.scenes[GameSky.Z.clouds]);

        detailLevel = 0;

        //else you'll get a quite big deltaT on start
        mEngineTime = new TimeSource();
        mEngineTime.paused = true;
    }

    //actually start the game (called after resources were preloaded)
    void start() {
        mEngineTime.paused = false;
    }

    bool gameEnded() {
        return mEngine.logic.currentRoundState == RoundState.end;
    }

    TimeSourcePublic engineTime() {
        return mEngineTime;
    }

    GameEnginePublic engine() {
        return mEngine;
    }

    //hacky?
    GameLogicPublic logic() {
        return mEngine.logic;
    }
    TeamMemberControl controller() {
        return logic.getControl();
    }

    void kill() {
        //xxx is this necessary? previously implemented by GameObject
    }

    void doFrame() {
        mEngineTime.update();

        float deltaT = mEngineTime.difference.secsf;

        if ((mEngineTime.current - mLastShake).msecs >= cShakeIntervalMs) {
            //something similar is being done in physics.d
            //the point of not using the physic's value is to reduce client-
            //  server communication a bit

            //100f? I don't know what it means, but it works (kind of)
            auto shake = Vector2f.fromPolar(1.0f, random()*PI*2)
                * (mEngine.earthQuakeStrength()/100f);
            mShakeOffset = toVector2i(shake);

            mLastShake = mEngineTime.current;
        }

        //only these are shaked on an earth quake
        mZScenes[GameZOrder.Objects].pos = mSceneRect.p1 + mShakeOffset;
        mZScenes[GameZOrder.Landscape].pos = mSceneRect.p1 + mShakeOffset;

        //hm
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        //call simulate(deltaT);
        mGameWater.simulate(deltaT);
        mGameSky.simulate(deltaT);

        graphics.simulate(deltaT);
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
