module game.clientengine;

import framework.font;
import game.gobject;
import game.physic;
import game.baseengine;
import game.scene;
import game.game;
import game.water;
import game.sky;
import game.controller;
import game.common;
import game.visual;
import game.animation;
import game.resources;
import utils.mylist;
import utils.time;
import utils.misc;
import utils.vector2;

struct PerTeamAnim {
    AnimationResource arrow;
    AnimationResource pointed;
}

//client-side game engine, manages all stuff that does not affect gameplay,
//but needs access to the game and is drawn into the game scene
class ClientGameEngine : BaseGameEngine {
    private GameEngine mEngine;

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    private Scene mScene;

    private GameWater mGameWater;
    private GameSky mGameSky;

    private WormNameDrawer mDrawer;

    //indexed by team color
    private PerTeamAnim[] mTeamAnims;

    this(GameEngine engine) {
        mEngine = engine;

        mScene = new Scene();
        mScene.size = mEngine.scene.size;

        globals.resources.loadAnimations(globals.loadConfig("teamanims"));
        mTeamAnims.length = cTeamColors.length;
        foreach (int n, char[] color; cTeamColors) {
            mTeamAnims[n].arrow = globals.resources.anims("darrow_" ~ color);
            mTeamAnims[n].pointed = globals.resources.anims("pointed_" ~ color);
        }

        mGameWater = new GameWater(this, mEngine, mScene, "blue");
        mGameSky = new GameSky(this, mEngine, mScene);

        //draws the worm names
        mDrawer = new WormNameDrawer(mEngine.controller, mTeamAnims);
        mDrawer.setScene(mScene, GameZOrder.Names);

        detailLevel = 0;
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
