module game.gui.gameview;

import framework.font;
import framework.framework;
import common.scene;
import game.animation;
import game.gamepublic;
import game.clientengine;
import game.gui.camera;
import game.weapon.weapon;
import game.gui.teaminfo;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import utils.rect2;
import utils.time;
import utils.misc;
import utils.vector2;

import std.string : format;

//arrrrgh
class GuiAnimator : Widget {
    private {
        Animator mAnimator;
    }

    this() {
        mAnimator = new Animator();
    }

    override protected void onDraw(Canvas c) {
        mAnimator.pos = size/2;
        mAnimator.draw(c);
    }

    override Vector2i layoutSizeRequest() {
        return mAnimator.bounds.size;
    }

    void animation(Animation ani) {
        mAnimator.setAnimation(ani);
        needResize(true);
    }

    void setPositionCentered(Vector2i newPos) {
        adjustPosition(newPos - mAnimator.bounds.size/2);
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
        GameInfo mGame;
        Container mGuiFrame;

        Camera mCamera;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2i dirKeyState_lu = {0, 0};  //left/up
        Vector2i dirKeyState_rd = {0, 0};  //right/down

        //for worm-name drawing
        ViewMember[] mAllMembers;
        ViewMember[TeamMember] mEngineMemberToOurs;

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

        //per-member class
        class ViewMember : CameraObject {
            TeamMemberInfo member; //from the "engine"

            bool guiIsActive;

            //you might wonder why these labels aren't just drawn directly
            //instead we use the GUI... well but there's no reason
            //it's just plain stupid :D
            Label wormName;
            Label wormPoints;

            //animation of lifepower-countdown
            //int health_from, health_to;
            int health_cur;

            Vector2i forArrow;
            Vector2i lastKnownPosition;
            bool cameraActivated;

            this(TeamMemberInfo m) {
                member = m;
                wormName = m.owner.createLabel();
                wormName.text = m.member.name();
                wormPoints = m.owner.createLabel();
            }

            Vector2i getCameraPosition() {
                return lastKnownPosition;
            }
            bool isCameraAlive() {
                cameraActivated &= member.member.active();
                return cameraActivated;
            }

            void simulate() {
                auto graphic = member.member.getGraphic();
                bool shouldactive = !!graphic;
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
                    lastKnownPosition = graphic.bounds.p1;

                    //update state
                    if (health_cur != member.currentHealth()) {
                        health_cur = member.currentHealth();
                        wormPoints.text = format("%s", health_cur);
                    }
                    //update positions...
                    assert(graphic !is null);
                    auto pos = graphic.bounds.center;
                    pos.y -= graphic.bounds.size.y/2;

                    void mooh(Widget w) {
                        Vector2i sz = w.size;
                        Rect2i booh = void;
                        pos.y -= sz.y;
                        auto p = pos;
                        p.x -= sz.x/2; //center
                        w.adjustPosition(p);
                    }
                    mooh(wormPoints);
                    mooh(wormName);
                    forArrow = pos;

                    //activate camera if it should and wasn't yet
                    if (!cameraActivated && member.member.active()) {
                        cameraActivated = true;
                        mCamera.setCameraFocus(this);
                    }
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

        TeamMember cur = mController.getActiveMember();

        if (cur &&
            mCurrentTime - mController.currentLastAction() > mArrowDelta)
        {
            //make sure the arrow is active
            ViewMember vm = mEngineMemberToOurs[cur];
            if (!mArrow.parent) {
                mArrow.animation = vm.member.owner.theme.arrow.get;
                addChild(mArrow);
            }
            Vector2i pos = vm.forArrow;
            pos.y -= mArrow.size.y;
            pos.x -= mArrow.size.x/2;
            mArrow.adjustPosition(pos);
        } else {
            mArrow.remove();
        }

        bool p_active = (mPointedFor is cur) && !!cur;
        if (!mPointed.parent && p_active) {
            addChild(mPointed);
        }
        if (!p_active) {
            mPointedFor = null;
            mPointed.remove;
        }
    }

    //at least if child is one of the worm labels, don't relayout the whole GUI
    //just allocate the child to the requested size; but it still seems to be
    //a bit stupid...
    //of course breaks layouting of other elements, but there are none
    override protected void requestedRelayout(Widget child) {
        //just readjust the size / position is fixed
        auto size = child.layoutCachedContainerSizeRequest();
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

    this(ClientGameEngine engine, Camera cam, GameInfo game) {
        mArrowDelta = timeSecs(5);
        mArrow = new GuiAnimator();
        mPointed = new GuiAnimator();

        mEngine = engine;
        mGame = game;

        mCamera = cam;

        //hacky?
        mLogic = mEngine.logic;
        mController = mEngine.controller;

        //load the teams and also the members
        foreach (TeamInfo t; game.teams) {
            foreach (TeamMemberInfo m; t.members) {
                ViewMember vt = new ViewMember(m);
                mAllMembers ~= vt;
                mEngineMemberToOurs[m.member] = vt;
            }
        }

        mController.setTeamMemberControlCallback(this);
    }

    override Vector2i layoutSizeRequest() {
        return mEngine.worldSize;
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
            //oh hi I'm wrong here
            case "fire":
                doFire(!up);
                return true;
            default:
                return false;
        }

        auto movementVec = dirKeyState_rd-dirKeyState_lu;
        mController.setMovement(movementVec);

        return true;
    }

    //find a WeaponClass of the weapon named "name" in the current team's
    //weapon-set (or return null)
    private WeaponClass findWeapon(char[] name) {
        auto team = mController.getActiveTeam();
        if (!team)
            return null;
        WeaponList weapons = team.getWeapons();
        foreach (w; weapons) {
            if (w.type.name == name) {
                return w.available ? w.type : null;
            }
        }
        return null;
    }

    //fire current weapon
    private void doFire(bool is_down) {
        mController.weaponFire(is_down);
    }

    private bool onKeyDown(char[] bind, KeyInfo info) {
        switch (bind) {
            case "selectworm": {
                mController.selectNextMember();
                return true;
            }
            case "pointy": {
                mController.weaponSetTarget(mousePos);
                auto cur = mController.getActiveMember();
                if (cur && mController.currentWeapon &&
                    mController.currentWeapon.fireMode.point != PointMode.none)
                {
                    mPointedFor = cur;
                    switch (mController.currentWeapon.fireMode.point) {
                        case PointMode.instant:
                            mPointed.animation = mEngineMemberToOurs[cur].member
                                .owner.theme.click.get;
                            break;
                        default:
                            mPointed.animation = mEngineMemberToOurs[cur].member
                                .owner.theme.pointed.get;
                    }
                    mPointed.setPositionCentered(mousePos);
                }
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
            default:

        }

        //try if it's a wapon shortcut
        //(oh lol, kind of unclean?)
        const cWShortcut = "weapon_";
        auto len = cWShortcut.length;
        if (bind.length >= len && bind[0..len] == cWShortcut) {
            auto wcname = bind[len..$];
            if (mController.currentWeapon &&
                mController.currentWeapon.name == wcname)
            {
                //already selected, fire (possibly again)
                doFire(true);
            } else {
                //draw the weapon
                //xxx what about instant fire?
                //    would have to wait until weapon ready
                WeaponClass c = findWeapon(wcname);
                mController.weaponDraw(c);
            }
        }

        //nothing found
        return false;
    }

    override protected bool onKeyEvent(KeyInfo ki) {
        auto bind = findBind(ki);
        if (ki.isDown && onKeyDown(bind, ki)) {
            return true;
        } else if (ki.isUp) {
            if (handleDirKey(bind, true))
                return true;
        }
        return super.onKeyEvent(ki);
    }

    override protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }

    //grrr
    override bool testMouse(Vector2i pos) {
        return true;
    }

    override void simulate() {
        super.simulate();
        doSim();
    }

    override void onDraw(Canvas c) {
        mEngine.draw(c);
        super.onDraw(c);
    }

    override bool doesCover() {
        return !mEngine.needBackclear();
    }
}
