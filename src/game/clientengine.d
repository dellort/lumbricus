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

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    Level,
    LevelWater,  //water before the level, but behind drowning objects
    Objects,
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

    private TimeSource mEngineTime;

    private GameWater mGameWater;
    private GameSky mGameSky;

    //private WormNameDrawer mDrawer;
    private LevelDrawer mLevelDrawer;

    //indexed by team color
    private PerTeamAnim[] mTeamAnims;

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
            ConfigNode colsNode = taCfg.getSubNode("darrow");
            mTeamAnims[n].arrow = globals.resources.resource!(AnimationResource)
                (colsNode.getPathValue(color));
            colsNode = taCfg.getSubNode("pointed");
            mTeamAnims[n].pointed = globals.resources.resource!
                (AnimationResource)(colsNode.getPathValue(color));
            colsNode = taCfg.getSubNode("change");
            mTeamAnims[n].change = globals.resources.resource!
                (AnimationResource)(colsNode.getPathValue(color));
            colsNode = taCfg.getSubNode("cursor");
            mTeamAnims[n].cursor = globals.resources.resource!
                (AnimationResource)(colsNode.getPathValue(color));
            colsNode = taCfg.getSubNode("click");
            mTeamAnims[n].click = globals.resources.resource!
                (AnimationResource)(colsNode.getPathValue(color));
            colsNode = taCfg.getSubNode("aim");
            mTeamAnims[n].aim = globals.resources.resource!
                (AnimationResource)(colsNode.getPathValue(color));
        }

        mGameWater = new GameWater(this, "blue");
        mZScenes[GameZOrder.BackWater].add(mGameWater.scenes[GameWater.Z.back]);
        mZScenes[GameZOrder.LevelWater].add(mGameWater.scenes[GameWater.Z.level]);
        mZScenes[GameZOrder.FrontWater].add(mGameWater.scenes[GameWater.Z.front]);

        mGameSky = new GameSky(this);
        mZScenes[GameZOrder.Background].add(mGameSky.scenes[GameSky.Z.back]);
        mZScenes[GameZOrder.BackLayer].add(mGameSky.scenes[GameSky.Z.debris]);
        mZScenes[GameZOrder.Objects].add(mGameSky.scenes[GameSky.Z.clouds]);

        //draws the worm names
        //mDrawer = new WormNameDrawer(mEngine.controller, mTeamAnims);
        //mDrawer.setScene(mScene, GameZOrder.Names);

        //actual level
        mLevelDrawer = new LevelDrawer(this);
        mZScenes[GameZOrder.Level].add(mLevelDrawer);

        detailLevel = 0;

        //preload all needed animations
        //xxx add loading bar
        globals.resources.preloadUsed(null);

        //else you'll get a quite big deltaT on start
        mEngineTime = new TimeSource(&gFramework.getCurrentTime);
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

    void resize(Vector2i s) {
        mScene.rect = Rect2i(mScene.rect.p1, mScene.rect.p1 + s);
        Rect2i rc = Rect2i(Vector2i(0), s);
        foreach (Scene e; mZScenes) {
            e.rect = rc;
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
}

class LevelDrawer : SceneObject {
    ClientGameEngine game;
    Texture levelTexture;

    void draw(Canvas c) {
        if (!levelTexture) {
            levelTexture = game.mEngine.gamelevel.image.createTexture();
            levelTexture.setCaching(false);
        }
        c.draw(levelTexture, game.mEngine.gamelevel.offset);
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

    this(ClientGameEngine game) {
        this.game = game;
    }
}

/+
private class WormNameDrawer : SceneObject {
    private GameController mController;
    private Font[Team] mWormFont;
    private int mFontHeight;
    private Animator mArrow;
    private Animator mPointed;
    private Time mArrowDelta;
    private int mArrowCol = -1, mPointCol = -1;
    private PerTeamAnim[] mTeamAnims;

    this(GameController controller, PerTeamAnim[] teamAnims) {
        mController = controller;
        mTeamAnims = teamAnims;

        //create team fonts (expects teams are already loaded)
        foreach (Team t; controller.teams) {
            auto font = globals.framework.fontManager.loadFont("wormfont_"
                ~ cTeamColors[t.teamColor]);
            mWormFont[t] = font;
            //assume all fonts are same height but... anyway
            mFontHeight = max(mFontHeight, font.textSize("").y);
        }

        mArrow = new Animator();
        mArrowDelta = timeSecs(5);

        mPointed = new Animator();
    }

    const cYDist = 3;   //distance label/worm-graphic
    const cYBorder = 2; //thickness of label box

    //upper border of the label relative to the worm's Y coordinate
    int labelsYOffset() {
        return cYDist+cYBorder*2+mFontHeight;
    }

    private void showArrow(TeamMember cur) {
        if (cur.worm) {
            //xxx currently don't have worm animations available
            auto wpos = toVector2i(cur.worm.physics.pos);
            auto wsize = Vector2i(0);
            if (!mArrow.active || mArrowCol != cur.team.teamColor) {
                mArrow.setAnimation(mTeamAnims[cur.team.teamColor].arrow.get());
                mArrow.active = true;
                mArrowCol = cur.team.teamColor;
            }
            //2 pixels Y spacing
            mArrow.pos = wpos + wsize.X/2 - mArrow.size.X/2
                - mArrow.size.Y /*- Vector2i(0, mDrawer.labelsYOffset + 2)*/;
        }
    }
    private void hideArrow() {
        mArrow.active = false;
    }

    private void showPoint(TeamMember cur) {
        if (!mPointed.active || mPointCol != cur.team.teamColor) {
            mPointed.setAnimation(mTeamAnims[cur.team.teamColor].pointed.get());
            mPointed.active = true;
            mPointCol = cur.team.teamColor;
        }
        mPointed.pos = toVector2i(cur.team.currentTarget) - mPointed.size/2;
    }

    private void hidePoint() {
        mPointed.active = false;
    }

    void draw(Canvas canvas) {
        if (mController.current && mController.engine.gameTime.current
            - mController.currentLastAction > mArrowDelta)
        {
            showArrow(mController.current);
        } else {
            hideArrow();
        }
        if (mController.current && mController.current.team &&
            mController.current.team.targetIsSet)
        {
            showPoint(mController.current);
        } else {
            hidePoint();
        }
        //xxx: add code to i.e. move the worm-name labels

        foreach (Team t; mController.teams) {
            auto pfont = t in mWormFont;
            if (!pfont)
                continue;
            Font font = *pfont;
            foreach (TeamMember w; t) {
                if (!w.worm || w.worm.isDead)
                    continue;

                char[] text = str.format("%s (%s)", w.name,
                    w.worm.physics.lifepowerInt);

                //xxx haven't worm graphic available
                auto wp = toVector2i(w.worm.physics.pos)-Vector2i(30,30);
                auto sz = Vector2i(6, 60); //w.worm.graphic.size;
                //draw 3 pixels above, centered
                auto tsz = font.textSize(text);
                tsz.y = mFontHeight; //hicks
                auto pos = wp+Vector2i(sz.x/2 - tsz.x/2, -tsz.y - cYDist);

                auto border = Vector2i(4, cYBorder);
                //auto b = getBox(tsz+border*2, Color(1,1,1), Color(0,0,0));
                //canvas.draw(b, pos-border);
                //if (mController.mEngine.enableSpiffyGui)

                    drawBox(canvas, pos-border, tsz+border*2);
                font.drawText(canvas, pos, text);
            }
        }
    }
}
+/
