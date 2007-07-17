module game.gui.gameview;

import framework.font;
import framework.framework;
import common.common;
import common.scene;
import game.animation;
import game.gamepublic;
import game.clientengine;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import utils.rect2;
import utils.time;
import utils.vector2;

import std.string : format;

//arrrrgh
class GuiAnimator : Widget {
    private {
        Animator mAnimator;
    }

    this() {
        mAnimator = new Animator();
        scene.add(mAnimator);
    }

    override Vector2i layoutSizeRequest() {
        return mAnimator.size;
    }

    void animation(Animation ani) {
        mAnimator.setNextAnimation(ani, true);
        needResize(true);
    }
}

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Container, TeamMemberControlCallback {
    void delegate() onTeamChange;

    private {
        ClientGameEngine mEngine;
        GameLogicPublic mLogic;
        TeamMemberControl mController;
        Container mGuiFrame;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2i dirKeyState_lu = {0, 0};  //left/up
        Vector2i dirKeyState_rd = {0, 0};  //right/down

        //for worm-name drawing
        ViewMember[] mAllMembers;
        ViewMember[TeamMember] mEngineMemberToOurs;

        ViewTeam[Team] mTeams;

        //arrow which points on currently active worm (goes away when he moves)
        GuiAnimator mArrow;
        //marker for targets of homing weapons
        GuiAnimator mPointed;
        //xxx find better way to make this disappear
        TeamMember mPointedFor;

        Time mArrowDelta;

        Time mLastTime, mCurrentTime;

        struct AnimateMoveWidget {
            Widget widget;
        }

        class ViewTeam {
            Team team;
            Color color;
            PerTeamAnim animations;
            Font font;
            ViewMember[] members;

            this(Team t) {
                bool res = parseColor(cTeamColors[t.color], color);
                //if fails, adjust either arseColor or cTeamColors...
                assert(res, "internal error: unparseable team color");
                //xxx maybe don't load them all separately, but use this.color
                font = globals.framework.fontManager.loadFont("wormfont_"
                    ~ cTeamColors[t.color]);
                animations = mEngine.getTeamAnimations(t);

                foreach (m; t.getMembers()) {
                    auto member = new ViewMember(this, m);
                    members ~= member;
                    mAllMembers ~= member;
                    mEngineMemberToOurs[m] = member;
                }
            }
        }

        //per-member class
        class ViewMember {
            TeamMember member; //from the "engine"
            ViewTeam team;

            ulong clientGraphic = cInvalidUID;
            ClientGraphic cachedCG;

            bool guiIsActive;

            //you might wonder why these labels aren't just drawn directly
            //instead we use the GUI... well but there's no reason
            //it's just plain stupid :D
            GuiLabel wormName;
            GuiLabel wormPoints;

            //animation of lifepower-countdown
            //int health_from, health_to;
            int health_cur;

            this(ViewTeam parent, TeamMember m) {
                member = m;
                team = parent;
                wormName = new GuiLabel();
                wormName.font = team.font;
                wormName.text = m.name;
                wormName.border = Vector2i(3);
                wormPoints = new GuiLabel();
                wormPoints.font = wormName.font;
                wormPoints.border = wormName.border;
            }

            void simulate() {
                auto ncg = member.getGraphic();
                //aw, there's the bug that the game is ahead of the graphic
                //events; so findClientGraphic will return null for new graphics
                //"!cachedCG || " hacks this out
                if (!cachedCG || ncg != clientGraphic) {
                    cachedCG = mEngine.findClientGraphic(ncg);
                    clientGraphic = ncg;
                }
                bool shouldactive = cachedCG && cachedCG.active;
                if (shouldactive != guiIsActive) {
                    if (!shouldactive) {
                        //hide GUI
                        wormName.remove();
                        wormPoints.remove();
                    } else {
                        //show GUI
                        this.outer.addChild(wormName);
                        this.outer.addChild(wormPoints);
                    }
                    guiIsActive = shouldactive;
                }
                if (guiIsActive) {
                    //update state
                    if (health_cur != member.health) {
                        health_cur = member.health;
                        wormPoints.text = format("%s", health_cur);
                    }
                    //update positions...
                    assert(cachedCG !is null);
                    Vector2i pos;
                    pos.x = cachedCG.pos.x + cachedCG.size.x/2;
                    pos.y = cachedCG.pos.y;

                    void mooh(Widget w) {
                        Vector2i sz = w.size;
                        Rect2i booh = void;
                        pos.y -= sz.y;
                        booh.p1 = pos;
                        booh.p1.x -= sz.x/2; //center
                        booh.p2 = booh.p1 + sz;
                        w.manualRelayout(booh);
                    }
                    mooh(wormPoints);
                    mooh(wormName);
                }
            }
        }
    }

    private void doSim() {
        mLastTime = mCurrentTime;
        mCurrentTime = mEngine.engineTime.current;

        foreach (m; mAllMembers) {
            m.simulate();
        }
    }

    //at least if child is one of the worm labels, don't relayout the whole GUI
    //just allocate the child to the requested size; but it still seems to be
    //a bit stupid...
    //of course breaks layouting of other elements, but there are none
    override protected void requestedRelayout(Widget child) {
        if (!child) {
            super.requestedRelayout(null);
            return;
        }
        //just readjust the size / position is fixed
        auto size = child.layoutSizeRequest();
        auto bounds = child.containedBounds();
        bounds.p2 = bounds.p1 + size;
        child.manualRelayout(bounds);
    }

    //block out automatic layouting of labels etc.
    //could be dangerous if my code in container.d/widget.d assumes ungood stuff
    protected override void layoutSizeAllocation() {
        //mooh
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(ClientGameEngine engine) {
        mArrowDelta = timeSecs(5);

        mEngine = engine;
        scene.add(mEngine.scene);

        //hacky?
        mLogic = mEngine.logic;
        mController = mEngine.controller;

        //load the teams and also the members
        foreach (Team t; mEngine.logic.getTeams()) {
            ViewTeam vt = new ViewTeam(t);
            mTeams[t] = vt;
        }

        mController.setTeamMemberControlCallback(this);
    }

    override Vector2i layoutSizeRequest() {
        return mEngine.scene.size;
    }

    override void onRelayout() {
    }

    // --- start TeamMemberControlCallback

    void controlMemberChanged() {
        //currently needed for weapon update
        if (onTeamChange) {
            onTeamChange();
        }
    }

    void controlWalkStateChanged() {
    }

    void controlWeaponModeChanged() {
    }

    // --- end TeamMemberControlCallback

    private bool handleDirKey(char[] bind, bool up) {
        int v = up ? 0 : 1;
        switch (bind) {
            case "left":
                dirKeyState_lu.x = v;
                break;
            case "right":
                dirKeyState_rd.x = v;
                break;
            case "up":
                dirKeyState_lu.y = v;
                break;
            case "down":
                dirKeyState_rd.y = v;
                break;
            default:
                return false;
        }

        auto movementVec = dirKeyState_rd-dirKeyState_lu;
        mController.setMovement(movementVec);

        return true;
    }

    override protected bool onKeyDown(char[] bind, KeyInfo info) {
        switch (bind) {
            case "selectworm": {
                mController.selectNextMember();
                return true;
            }
            case "pointy": {
                mController.weaponSetTarget(mousePos);
                return true;
            }
            default:
        }

        if (handleDirKey(bind, false))
            return true;

        switch (bind) {
            case "jump": {
                mController.jump(JumpMode.normal);
                return true;
            }
            case "jetpack": {
                mController.jetpack(mController.walkState()
                    != WalkState.jetpackFly);
                return true;
            }
            case "fire": {
                mController.weaponFire(1.0f);
                return true;
            }
            default:

        }
        //nothing found
        return false;
    }

    override protected bool onKeyUp(char[] bind, KeyInfo info) {
        if (handleDirKey(bind, true))
            return true;
        return false;
    }

    override protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }

    override void simulate(Time curTime, Time deltaT) {
        super.simulate(curTime, deltaT);
        doSim();
    }
}
/+
private class WormNames {

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