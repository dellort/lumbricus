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
import game.sequence;
import levelgen.level;
import utils.mylist;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.perf;
import utils.configfile;
import utils.random : random;
import std.math : PI;

class GfxInfos {
    ResourceSet resources;

    //indexed by team color
    PerTeamAnim[] teamAnims;

    Color waterColor;

    void load() {
        teamAnims.length = cTeamColors.length;
        foreach (int n, char[] color; cTeamColors) {
            auto cur = &teamAnims[n];

            Resource!(Animation) loadanim(char[] node) {
                return resources.resource!(Animation)(node ~ "_" ~ color);
            }

            cur.arrow = loadanim("darrow");
            cur.pointed = loadanim("pointed");
            cur.change = loadanim("change");
            cur.cursor = loadanim("point");
            cur.click = loadanim("click");
            cur.aim = loadanim("aim");
        }
    }
}

struct PerTeamAnim {
    Resource!(Animation) arrow;
    Resource!(Animation) pointed;
    Resource!(Animation) change;
    Resource!(Animation) cursor;
    Resource!(Animation) click;
    Resource!(Animation) aim;
}

class ClientGraphic : Graphic {
    private mixin ListNodeMixin node;
    GraphicsHandler handler;

    //subclass must call init() after it has run its constructor
    this(GraphicsHandler a_owner) {
        handler = a_owner;
    }

    //stupid enforced constructor order...
    protected void init() {
        handler.objectScene.add(graphic);
        handler.mGraphics.insert_tail(this);
    }

    void remove() {
        handler.mGraphics.remove(this);
        handler.objectScene.remove(graphic);
    }

    abstract SceneObject graphic();
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
    }

    protected void init() {
        mDraw = new Draw();
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

class GraphicsHandler : GameEngineGraphics {
    private List!(ClientGraphic) mGraphics;

    Scene objectScene;

    this() {
        mGraphics = new typeof(mGraphics)(ClientGraphic.node.getListNodeOffset());
        objectScene = new Scene();
    }

    Sequence createSequence(SequenceObject type) {
        assert(!!type);
        return type.instantiate(this); //yay factory
    }
    LineGraphic createLine() {
        return new ClientLineGraphic(this);
    }
}

enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    Level,
    LevelWater,  //water before the level, but behind drowning objects
    Objects,
    Clouds,
    Names, //controller.d/WormNameDrawer
    FrontWater,
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine {
    private GameEnginePublic mEngine;

    ResourceSet resources;
    GfxInfos gfx;
    GraphicsHandler graphics;

    //stuff cached/received/duplicated from the engine
    //(remind that mEngine might disappear because of networking)
    int waterOffset;
    float windSpeed;
    Vector2i levelOffset, worldSize;
    int downLine; //used to be: gamelevel.offset.y+gamelevel.size.y

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

    //private WormNameDrawer mDrawer;
    private LevelDrawer mLevelDrawer;

    private PerfTimer mGameDrawTime;

    //needed by gameview.d (where all this stuff is drawn)
    //you can move it around if you want
    PerTeamAnim getTeamAnimations(Team t) {
        return gfx.teamAnims[t.color];
    }

    this(GameEnginePublic engine, GfxInfos a_gfx, GraphicsHandler foo) {
        mEngine = engine;
        gfx = a_gfx;
        resources = gfx.resources;
        graphics = foo;

        mGameDrawTime = globals.newTimer("game_draw_time");

        //xxx make value transfers generic
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        worldSize = mEngine.worldSize;
        downLine = mEngine.gamelevel.offset.y+mEngine.gamelevel.size.y;

        mScene = new Scene();

        //attention: be sure to keep the order
        //never remove or reinsert items frm the mScene
        foreach(inout Scene s; mZScenes) {
            s = new Scene();
            mScene.add(s);
        }

        resize(worldSize);

        mZScenes[GameZOrder.Objects].add(graphics.objectScene);

        mGameWater = new GameWater(this);
        mZScenes[GameZOrder.BackWater].add(mGameWater.scenes[GameWater.Z.back]);
        mZScenes[GameZOrder.LevelWater].add(mGameWater.scenes[GameWater.Z.level]);
        mZScenes[GameZOrder.FrontWater].add(mGameWater.scenes[GameWater.Z.front]);

        mGameSky = new GameSky(this);
        mZScenes[GameZOrder.Background].add(mGameSky.scenes[GameSky.Z.back]);
        mZScenes[GameZOrder.BackLayer].add(mGameSky.scenes[GameSky.Z.debris]);
        mZScenes[GameZOrder.Clouds].add(mGameSky.scenes[GameSky.Z.clouds]);

        //actual level
        mLevelDrawer = new LevelDrawer();
        mZScenes[GameZOrder.Level].add(mLevelDrawer);

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
        mZScenes[GameZOrder.Objects].rect = mSceneRect + mShakeOffset;
        mZScenes[GameZOrder.Level].rect = mSceneRect + mShakeOffset;

        //hm
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        //call simulate(deltaT);
        mGameWater.simulate(deltaT);
        mGameSky.simulate(deltaT);
    }

    Scene scene() {
        return mScene;
    }

    void draw(Canvas canvas) {
        mGameDrawTime.start();
        mScene.draw(canvas);
        mGameDrawTime.stop();
    }

    void resize(Vector2i s) {
        mScene.rect = Rect2i(mScene.rect.p1, mScene.rect.p1 + s);
        mSceneRect = Rect2i(Vector2i(0), s);
        foreach (Scene e; mZScenes) {
            e.rect = mSceneRect;
        }
        graphics.objectScene.rect = mSceneRect;
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

    //all hail to inner classes
    private class LevelDrawer : SceneObject {
        Texture levelTexture;

        void draw(Canvas c) {
            if (!levelTexture) {
                levelTexture = mEngine.gamelevel.image.createTexture();
                levelTexture.enableCaching(false);
            }
            c.draw(levelTexture, mEngine.gamelevel.offset);
            /+
            //debug code to test collision detection
            Vector2i dir; int pixelcount;
            auto pos = game.tmp;
            auto npos = toVector2f(pos);
            auto testr = 10;
            if (game.gamelevel.physics.collide(npos, testr)) {
                c.drawCircle(pos, testr, Color(0,1,0));
                c.drawCircle(toVector2i(npos), testr, Color(1,1,0));
            }
            +/
            /+
            //xxx draw debug stuff for physics!
            foreach (PhysicObject o; game.mEngine.physicworld.mObjects) {
                //auto angle = o.rotation;
                auto angle2 = o.ground_angle;
                auto angle = o.lookey;
                c.drawCircle(toVector2i(o.pos), cast(int)o.posp.radius, Color(1,1,1));
                auto p = Vector2f.fromPolar(40, angle) + o.pos;
                c.drawCircle(toVector2i(p), 5, Color(1,1,0));
                p = Vector2f.fromPolar(50, angle2) + o.pos;
                c.drawCircle(toVector2i(p), 5, Color(1,0,1));
            }
            +/
            //more debug stuff...
            //foreach (GameObject go; game.mEngine.mObjects) {
                /+if (cast(Worm)go) {
                    auto w = cast(Worm)go;
                    auto p = Vector2f.fromPolar(40, w.angle) + w.physics.pos;
                    c.drawCircle(toVector2i(p), 5, Color(1,0,1));
                }+/
            //}
        }
    }
}
