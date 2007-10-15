module game.clientengine;

import framework.framework;
import framework.font;
import framework.timesource;
import common.scene;
import common.common;
import common.visual;
import game.water;
import game.sky;
import game.animation;
import game.gamepublic;
import levelgen.level;
import utils.mylist;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.configfile;
import utils.random : random;
import std.math : PI;

struct PerTeamAnim {
    AnimationResource arrow;
    AnimationResource pointed;
    AnimationResource change;
    AnimationResource cursor;
    AnimationResource click;
    AnimationResource aim;
}

//synced with game.ServerGraphicLocalImpl
class ClientGraphic : Animator {
    private mixin ListNodeMixin node;
    long uid = -1;

    Vector2f velocity;
    Vector2f fpos; //float here, "network" uses int, and that's ok

    //called manually from ClientEngine
    void simulate(float deltaT) {
        fpos += velocity * deltaT;
        size = currentAnimation ? currentAnimation.size : Vector2i(0, 0);
        pos = toVector2i(fpos) - size/2;
    }

    void sync(GraphicEvent* bla) {
        assert(uid == bla.uid);
        if (bla.setevent.do_set_ani) {
            auto ani = bla.setevent.set_animation;
            setNextAnimation(ani ? ani.get() : null, bla.setevent.set_force);
        }
        size = currentAnimation ? currentAnimation.size : Vector2i(0, 0);
        pos = bla.setevent.pos - size/2;
        fpos = toVector2f(bla.setevent.pos);
        velocity = bla.setevent.dir;
        animationState.setParams(bla.setevent.p1, bla.setevent.p2);
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

    private List!(ClientGraphic) mGraphics;

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

    //indexed by team color
    private PerTeamAnim[] mTeamAnims;

    //needed by gameview.d (where all this stuff is drawn)
    //you can move it around if you want
    PerTeamAnim getTeamAnimations(Team t) {
        return mTeamAnims[t.color];
    }

    //inefficient because O(n)
    //return null if invalid id
    ClientGraphic findClientGraphic(long id) {
        foreach (ClientGraphic g; mGraphics) {
            if (g.uid == id)
                return g;
        }
        return null;
    }

    this(GameEnginePublic engine) {
        mEngine = engine;

        mGraphics = new typeof(mGraphics)(ClientGraphic.node.getListNodeOffset());

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

        ConfigNode taCfg = globals.loadConfig("teamanims");
        globals.resources.loadResources(taCfg);
        mTeamAnims.length = cTeamColors.length;
        foreach (int n, char[] color; cTeamColors) {
            auto cur = &mTeamAnims[n];

            AnimationResource loadanim(char[] node) {
                return globals.resources.resource!(AnimationResource)
                    (taCfg.getSubNode(node).getPathValue(color));
            }

            cur.arrow = loadanim("darrow");
            cur.pointed = loadanim("pointed");
            cur.change = loadanim("change");
            cur.cursor = loadanim("cursor");
            cur.click = loadanim("click");
            cur.aim = loadanim("aim");
        }

        mGameWater = new GameWater(this, "blue");
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
        mEngineTime = new TimeSource(&gFramework.getCurrentTime);
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

        auto grascene = mZScenes[GameZOrder.Objects];

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

        //haha, update before next "network" sync
        foreach (ClientGraphic gra; mGraphics) {
            gra.simulate(deltaT);
        }

        //never mind...
        ClientGraphic cur_c = mGraphics.head;
        GraphicEvent* cur_s = mEngine.currentEvents;
        mEngine.clearEvents();
        //sync client and server
        while (cur_c && cur_s) {
            if (cur_c.uid == cur_s.uid) {
                if (cur_s.type == GraphicEventType.Remove) {
                    //kill kill kill
                    ClientGraphic kill = cur_c;
                    cur_c = mGraphics.next(cur_c);
                    grascene.remove(kill);
                    mGraphics.remove(kill);
                    kill.active = false;
                } else if (cur_s.type == GraphicEventType.Change) {
                    //sync up...
                    cur_c.sync(cur_s);
                }
                cur_s = cur_s.next;
                //only if there are no more events for this uid/object
                //and if not killed cur_c = mGraphics.next(cur_c);
            } else {
                //try to find where they sync up (both lists ordered)
                if (cur_c.uid > cur_s.uid) {
                    cur_s = cur_s.next;
                } else {
                    cur_c = mGraphics.next(cur_c);
                }
            }
        }
        //the rest of the events must be add commands
        while (cur_s) {
            assert(cur_s.type == GraphicEventType.Add);

            auto ng = new ClientGraphic();
            ng.uid = cur_s.uid;
            mGraphics.insert_tail(ng);
            grascene.add(ng);
            ng.sync(cur_s);

            cur_s = cur_s.next;
        }
    }

    Scene scene() {
        return mScene;
    }

    void draw(Canvas canvas) {
        mScene.draw(canvas);
    }

    void resize(Vector2i s) {
        mScene.rect = Rect2i(mScene.rect.p1, mScene.rect.p1 + s);
        mSceneRect = Rect2i(Vector2i(0), s);
        foreach (Scene e; mZScenes) {
            e.rect = mSceneRect;
        }
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

    //all hail to inner classes
    private class LevelDrawer : SceneObject {
        Texture levelTexture;

        void draw(Canvas c) {
            if (!levelTexture) {
                levelTexture = mEngine.gamelevel.image.createTexture();
                levelTexture.setCaching(false);
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
