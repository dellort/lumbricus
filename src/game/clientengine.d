module game.clientengine;

import framework.framework;
import framework.font;
import game.gobject;
import game.physic;
import game.scene;
import game.game;
import game.water;
import game.sky;
import game.controller;
import game.common;
import game.visual;
import game.animation;
import game.resources;
import levelgen.level;
import utils.mylist;
import utils.time;
import utils.misc;
import utils.vector2;

struct PerTeamAnim {
    AnimationResource arrow;
    AnimationResource pointed;
}

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    BackWaterWaves1,   //water behind the level
    BackWaterWaves2,
    Level,
    FrontLowerWater,  //water before the level
    Objects,
    Names, //controller.d/WormNameDrawer
    FrontUpperWater,
    FrontWaterWaves1,
    FrontWaterWaves2,
    FrontWaterWaves3,
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine : GameObject /+ temporary hack *g* +/ {
    private GameEngine mEngine;

    //stuff cached/received/duplicated from the engine
    //(remind that mEngine might disappear because of networking)
    int waterOffset;
    float windSpeed;
    Level level;
    Vector2i levelOffset, worldSize;
    int downLine; //used to be: gamelevel.offset.y+gamelevel.size.y

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private Scene mScene;

    private Time lastTime;

    private GameWater mGameWater;
    private GameSky mGameSky;

    private WormNameDrawer mDrawer;
    private LevelDrawer mLevelDrawer;

    //indexed by team color
    private PerTeamAnim[] mTeamAnims;

    this(GameEngine engine) {
        //wuahaha
        super(engine, true);
        mEngine = engine;

        level = mEngine.level;
        levelOffset = mEngine.levelOffset;
        worldSize = mEngine.worldSize;
        downLine = mEngine.gamelevel.offset.y+mEngine.gamelevel.size.y;

        mScene = new Scene();
        mScene.size = mEngine.scene.size;

        globals.resources.loadAnimations(globals.loadConfig("teamanims"));
        mTeamAnims.length = cTeamColors.length;
        foreach (int n, char[] color; cTeamColors) {
            mTeamAnims[n].arrow = globals.resources.anims("darrow_" ~ color);
            mTeamAnims[n].pointed = globals.resources.anims("pointed_" ~ color);
        }

        mGameWater = new GameWater(this, mScene, "blue");
        mGameSky = new GameSky(this, mScene);

        //draws the worm names
        mDrawer = new WormNameDrawer(mEngine.controller, mTeamAnims);
        mDrawer.setScene(mScene, GameZOrder.Names);

        //actual level
        mLevelDrawer = new LevelDrawer(this);
        mLevelDrawer.setScene(mScene, GameZOrder.Level);

        detailLevel = 0;

        //else you'll get a quite big deltaT on start
        lastTime = timeCurrentTime();
    }

    void doFrame() {
        auto currentTime = timeCurrentTime();
        float deltaT = (currentTime - lastTime).msecs/1000.0f;

        //hm
        waterOffset = mEngine.waterOffset;
        windSpeed = mEngine.windSpeed;

        //call simulate(deltaT);
        mGameWater.simulate(deltaT);
        mGameSky.simulate(deltaT);

        lastTime = currentTime;
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
        //more debug stuff...
        foreach (GameObject go; game.mEngine.mObjects) {
            /+if (cast(Worm)go) {
                auto w = cast(Worm)go;
                auto p = Vector2f.fromPolar(40, w.angle) + w.physics.pos;
                c.drawCircle(toVector2i(p), 5, Color(1,0,1));
            }+/
        }
    }

    this(ClientGameEngine game) {
        this.game = game;
    }
}

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

    void setScene(Scene s, int z) {
        super.setScene(s, z);
        mArrow.setScene(s, z);
        mPointed.setScene(s, z);
    }

    private void showArrow(TeamMember cur) {
        if (cur.worm) {
            Animator curGr = cur.worm.graphic;
            if (!mArrow.active || mArrowCol != cur.team.teamColor) {
                mArrow.setAnimation(mTeamAnims[cur.team.teamColor].arrow.get());
                mArrow.active = true;
                mArrowCol = cur.team.teamColor;
            }
            //2 pixels Y spacing
            mArrow.pos = curGr.pos + curGr.size.X/2 - mArrow.size.X/2
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
        if (mController.current && mController.engine.currentTime
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
                if (!w.worm || !w.worm.graphic.active)
                    continue;

                char[] text = str.format("%s (%s)", w.name,
                    w.worm.physics.lifepowerInt);

                auto wp = w.worm.graphic.pos;
                auto sz = w.worm.graphic.size;
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