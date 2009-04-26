module game.hud.gameview;

import common.common;
import framework.font;
import framework.framework;
import framework.commandline;
import framework.timesource;
import common.scene;
import game.animation;
import game.gamepublic;
import game.clientengine;
import game.sequence;
import game.hud.camera;
import game.weapon.weapon;
import game.hud.teaminfo;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import utils.rect2;
import utils.time;
import utils.math;
import utils.misc;
import utils.vector2;
import utils.interpolate;

import str = stdx.string;
import math = tango.math.Math;

//arrrrgh
class GuiAnimator : Widget {
    private {
        Animator mAnimator;
    }

    this(TimeSourcePublic ts) {
        mAnimator = new Animator(ts);
        setLayout(WidgetLayout.Aligned(-1, -1));
    }

    override protected void onDraw(Canvas c) {
        mAnimator.pos = size/2;
        mAnimator.draw(c);
    }

    override Vector2i layoutSizeRequest() {
        return mAnimator.bounds.size;
    }

    void animation(Animation ani) {
        if (ani !is mAnimator.animation) {
            mAnimator.setAnimation(ani);
            needResize(true);
        }
    }

    void setPositionCentered(Vector2i newPos) {
        setAddToPos(newPos - mAnimator.bounds.size/2);
    }
}

const Time cArrowDelta = timeSecs(5);
//time and length (in pixels) the health damage indicator will move upwards
const Time cHealthHintTime = timeMsecs(1000);
const int cHealthHintDistance = 75;
//time before the label disappears
const Time cHealthHintWait = timeMsecs(500);
//same as above for the worm labels when they're shown/hidden for active worms
const Time cLabelsMoveTimeUp = timeMsecs(300); //moving up
const Time cLabelsMoveTimeDown = timeMsecs(1000); //and down
const int cLabelsMoveDistance = 200;
const float cDrownLabelSpeed = 50; //pixels/sec
//time swap left/right position of weapon icon
const Time cWeaponIconMoveTime = timeMsecs(300);
//time to zoom out
const Time cZoomTime = timeMsecs(500);
//min/max zooming level
const float cZoomMin = 0.6f;
const float cZoomMax = 1.0f;

//per-member class
private class ViewMember {
    GameView owner;
    TeamMemberInfo member; //from the "engine"

    //you might wonder why these labels aren't just drawn directly
    //instead we use the GUI... well but there's no reason
    //it's just plain stupid :D
    Label wormTeam;
    Label wormName;
    Label wormPoints; //oh, it used to be named "points"
    //for the alternative weapon display
    Label weaponIcon;

    InterpolateExp2!(float, 4.0f) moveWeaponIcon;

    //arrow which points on currently active worm (goes away when he moves)
    //(there's only one per GUI, but keeping it here is simpler)
    GuiAnimator arrow;

    InterpolateLinear!(int) moveLabels;
    //bool beingActive; //last active state to detect state change

    //label which displays how much health was lost
    //starts from real health label, moves up, and disappears
    Label healthHint;

    InterpolateLinear!(int) moveHealth;

    int health_cur = int.max;
    int lastHealthHintTarget = int.max;

    private {
        bool mArrowState;
        bool mDrowning;
        Vector2i mLastDrownPos;
    }

    this(GameView a_owner, TeamMemberInfo m) {
        owner = a_owner;
        auto ts = owner.mGame.clientTime;
        moveLabels.currentTimeDg = &ts.current;
        moveHealth.currentTimeDg = &ts.current;
        moveWeaponIcon.currentTimeDg = &ts.current;
        member = m;
        wormTeam = m.owner.createLabel();
        wormName = m.owner.createLabel();
        wormName.text = m.member.name();
        wormPoints = m.owner.createLabel();
        healthHint = m.owner.createLabel();
        weaponIcon = m.owner.createLabel();
        weaponIcon.text = "";
        arrow = new GuiAnimator(ts);
    }

    void setArrowAnim(bool canChangeWorm) {
        auto theme = member.owner.theme;
        arrow.animation = canChangeWorm ? theme.change.get : theme.arrow.get;
        mArrowState = canChangeWorm;
    }

    void removeGUI() {
        wormTeam.remove();
        wormName.remove();
        wormPoints.remove();
        healthHint.remove();
        arrow.remove();
        weaponIcon.remove();
    }

    //use these with the label stuff
    void setWPos(Widget w, Vector2i pos) {
        w.setAddToPos(pos);
    }
    void setWVisible(Widget w, bool visible) {
        if (!visible) {
            //ensure invisibility
            w.remove();
            return;
        }
        //ensure visibility
        if (!w.parent()) {
            owner.addChild(w);
        }
    }

    void simulate() {
        auto graphic = member.member.getGraphic();
        bool guiIsActive = !!graphic;
        if (!guiIsActive) {
            removeGUI();
            //whatever
            if (mDrowning) {
                mDrowning = false;
                owner.showDrown(member, mLastDrownPos);
            }
        } else if (guiIsActive) {
            assert(graphic !is null);
            //xxx hurf hurf
            auto ag = cast(AnimationGraphic)graphic;
            assert (!!ag, "not attached to a worm?");
            Animation ani = ag.animation;
            Rect2i bounds;
            /+
            //assert (!!ani, "should be there because it is active");
            if (!ani) { //???
                bounds.p1 = Vector2i(0,0);
                bounds.p2 = Vector2i(1,1);
            }
            +/
            //ughh
            const d = 30;
            bounds = Rect2i(-d, -d, d, d);
            bounds += ag.pos;

            if (health_cur != member.currentHealth) {
                health_cur = member.currentHealth;
                wormPoints.text = myformat("{}", health_cur);
            }

            //labels are positioned above pos
            auto pos = bounds.center;
            pos.y -= bounds.size.y/2;

            bool isActiveWorm = this is owner.activeWorm;

            //whether labels should move up or down
            //initiate movement into this direction if not yet
            bool doMoveDown;

            if (isActiveWorm) {
                auto currentTime = owner.mGame.serverTime.current;
                bool didmove = (currentTime - owner.mGame.control.
                    getControlledMember.lastAction()) < cArrowDelta;
                doMoveDown = !didmove;
            } else {
                //move labels down, but arrow is invisible
                doMoveDown = true;
            }

            //if the moving direction isn't correct, reverse it
            if (doMoveDown != (moveLabels.target <= moveLabels.start)) {
                if (doMoveDown) {
                    //make labels visible & move down
                    moveLabels.setParams(cLabelsMoveTimeDown,
                        cLabelsMoveDistance, 0);
                } else {
                    //move up
                    moveLabels.setParams(cLabelsMoveTimeUp,
                        0, cLabelsMoveDistance);
                }
            }

            bool showLabels = true;

            if (!moveLabels.inProgress() && !doMoveDown) {
                showLabels = !isActiveWorm;
            }

            if (member.member.wormState == WormAniState.drowning) {
                showLabels = false;
                mDrowning = true;
                mLastDrownPos = pos;
            }

            //(.value() isn't necessarily changing all the time)
            pos.y -= moveLabels.value();

            //that weapon label
            auto amember = owner.mGame.control.getControlledMember();
            bool weapon_visible = (amember is member.member)
                && amember.displayWeaponIcon();

            setWVisible(weaponIcon, weapon_visible);
            setArrowAnim(member.member.team.allowSelect());

            if (weapon_visible) {
                //NOTE: wwp animates the appearance/disappearance of
                // the weapon label; when it disappears, it shrinks and
                // moves towards the worm; we don't do that (yet?)
                //for now, only animate the left/right change of the
                //worm

                weaponIcon.image = amember.getCurrentWeapon.icon.get;

                //possibly fix the animation
                //get where worm looks too
                bool faceLeft;
                if (ag.more) {
                    SequenceUpdate sd = ag.more;
                    faceLeft = angleLeftRight(sd.rotation_angle, true,
                        false);
                }
                if (!moveWeaponIcon.initialized) {
                    //rather a cheap trick to distinguish initialization
                    //from not-animating state
                    moveWeaponIcon.init(Time.Null, faceLeft ? 1 : 0,
                        faceLeft ? 0 : 1);
                }
                bool rtol = moveWeaponIcon.start
                    > moveWeaponIcon.target;
                if (rtol != faceLeft) {
                    if (moveWeaponIcon.inProgress()) {
                        //change direction (works because
                        //interpolation function is symmetric)
                        moveWeaponIcon.setParams(moveWeaponIcon.target,
                            moveWeaponIcon.start);
                    } else {
                        moveWeaponIcon.init(cWeaponIconMoveTime,
                            faceLeft ? 1 : 0, faceLeft ? 0 : 1);
                    }
                }

                //set the position
                float wip = moveWeaponIcon.value();
                auto npos = placeRelative(Rect2i(weaponIcon.size()),
                    bounds, Vector2i(0, -1), wip, 0.5f);
                npos += bounds.p1;
                setWPos(weaponIcon, npos);
            } else {
                moveWeaponIcon.reset();
            }

            //add rectangle under pos variable, return the rect's position
            Vector2i addThing(Vector2i size) {
                pos.y -= size.y;
                //pos.y -= 1; //some spacing, but it looks ugly
                auto p = pos;
                p.x -= size.x/2; //center
                return p;
            }

            void mooh(bool vis, Widget w) {
                setWVisible(w, vis);
                if (vis)
                    setWPos(w, addThing(w.requestSize));
            }
            auto tlv = showLabels && !weapon_visible;
            mooh(tlv && owner.mTeamGUISettings.showPoints, wormPoints);
            mooh(tlv && owner.mTeamGUISettings.showName, wormName);
            mooh(tlv && owner.mTeamGUISettings.showTeam, wormTeam);
            //label already placed, but adjust position for arrow
            if (weapon_visible) {
                pos.y -= weaponIcon.size.y;
            }
            mooh(showLabels && isActiveWorm, arrow);

            //for healthHint
            //I simply trigger it when the health value changes, and
            //when currently no label is displayed
            //the label is only removed as soon as the health value is
            //constant again
            //slight duplication of the logic in gameframes
            if (moveHealth.currentTime >= moveHealth.endTime
                + cHealthHintWait)
            {
                //ensure it's removed
                healthHint.remove();
                //probably start a new animation
                auto target = member.currentHealth;
                auto diff =  member.member.currentHealth() - target;
                //compare target and realHealth to see if health is
                //really changing (diff can still be != 0 if not)
                if (diff < 0 && target != lastHealthHintTarget
                    && target != member.realHealth())
                {
                    //start (only for damages, not upgrades => "< 0")
                    moveHealth.init(cHealthHintTime, 0,
                        cHealthHintDistance);
                    healthHint.text = myformat("{}", -diff);
                    owner.addChild(healthHint);
                    //this is to avoid restarting the label animation
                    //several times when counting down takes longer than
                    //to display the fill health damage hint animation
                    lastHealthHintTarget = target;
                }
            }
            if (healthHint.parent()) {
                //pos is leftover from above, move and center it
                pos.y -= moveHealth.value();
                setWPos(healthHint, pos-healthHint.size.X/2);
            }
        }
    } // simulate
} //ViewMember

private class GameLabel : Label {
    TextGraphic txt;

    this(TextGraphic a_txt) {
        setLayout(WidgetLayout.Aligned(-1, -1));
        styles.addClass("game-label");
        font = gFramework.fontManager.loadFont("gamelabel");
        txt = a_txt;
    }

    override void simulate() {
        text = txt.text;
        //there's also utils.math.placeRelative(), which was supposed to do this
        auto p = - toVector2f(size) ^ txt.attach;
        setAddToPos(txt.pos + toVector2i(p));
    }
}

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Container {
    void delegate() onTeamChange;
    // :(
    void delegate(char[] category) onSelectCategory;

    //for setSettings()
    struct GUITeamMemberSettings {
        bool showTeam = false;
        bool showName = true;
        bool showPoints = true;
    }

    private {
        GameInfo mGame;
        Container mGuiFrame;

        Camera mCamera;
        int mCurCamPriority;
        AnimationGraphic mCurCamObject;
        Time mLastCamChange;
        const cCamChangeDelay = timeSecs(1.2);

        float mZoomChange = 1.0f, mCurZoom = 1.0f;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2i dirKeyState_lu = {0, 0};  //left/up
        Vector2i dirKeyState_rd = {0, 0};  //right/down

        //for worm-name drawing
        ViewMember[] mAllMembers;
        ViewMember[TeamMember] mEngineMemberToOurs;

        GUITeamMemberSettings mTeamGUISettings;
        int mCycleLabels = 2;

        CommandLine mCmd;
        CommandBucket mCmds;

        ViewMember activeWorm;

        enum MoveLabelEffect {
            move,   //straight
            bubble, //like in water
        }

        struct MoveLabel {
            MoveLabelEffect effect;
            Widget label;
            Time start;
            float speed; //pixels/second
            Vector2i from, to;
        }

        MoveLabel[] mMoveLabels;
    } //private

    /+void updateGUI() {
        foreach (m; mAllMembers) {
            m.updateGUI();
        }
    }+/

    void setGUITeamMemberSettings(GUITeamMemberSettings s) {
        mTeamGUISettings = s;
        //updateGUI();
    }

    int nameLabelLevel() {
        return mCycleLabels;
    }
    void nameLabelLevel(int x) {
        mCycleLabels = x % 4;
        auto t = mCycleLabels;
        GUITeamMemberSettings s; //what a stupid type name
        s.showPoints = t >= 1;
        s.showName = t >= 2;
        s.showTeam = t >= 3;
        setGUITeamMemberSettings(s);
    }

    //member inf drowned at pos (pos is on the ground)
    private void showDrown(TeamMemberInfo inf, Vector2i pos) {
        MoveLabel ml;
        auto lbl = inf.owner.createLabel();
        lbl.text = myformat("{}", inf.currentHealth);
        addChild(lbl);
        ml.label = lbl;
        ml.from = pos;
        ml.to = Vector2i(pos.x, mGame.cengine.waterOffset);
        ml.start = mGame.clientTime.current;
        ml.effect = MoveLabelEffect.bubble;
        ml.speed = cDrownLabelSpeed;
        mMoveLabels ~= ml;
    }

    private void doSim() {
        mCamera.doFrame();

        activeWorm = null;
        if (auto am = mGame.control.getControlledMember()) {
            auto pam = am in mEngineMemberToOurs;
            activeWorm = pam ? *pam : null;
        }

        foreach (m; mAllMembers) {
            m.simulate();
        }

        int i = 0;
        while (i < mMoveLabels.length) {
            MoveLabel cur = mMoveLabels[i];
            auto now = mGame.clientTime.current;

            auto dir = toVector2f(cur.to) - toVector2f(cur.from);
            auto px = (now-cur.start).secsf * cur.speed;
            auto move = px * dir.normal;

            if (move.length >= dir.length) {
                cur.label.remove();
                mMoveLabels = mMoveLabels[0..i] ~ mMoveLabels[i+1..$];
                continue;
            }
            i++;

            if (cur.effect == MoveLabelEffect.bubble) {
                const cPxArc = 50; //so many sinus curves over a pixel distance
                const cArcAmp = 10; //amplitude of sinus curve
                auto idx = px / cPxArc * math.PI * 2;
                move.x += math.sin(idx) * cArcAmp;
            }

            cur.label.setAddToPos(cur.from + toVector2i(move));
        }
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(GameInfo game) {
        mGame = game;

        mGame.engine.callbacks.newGraphic ~= &doNewGraphic;
        foreach (g; mGame.engine.getGraphics().objects) {
            doNewGraphic(g);
        }

        SceneObject labels = new DrawLabels();
        labels.zorder = GameZOrder.Names;
        mGame.cengine.scene.add(labels);

        mCamera = new Camera(mGame.clientTime);

        //load the teams and also the members
        foreach (TeamInfo t; game.teams) {
            foreach (TeamMemberInfo m; t.members) {
                ViewMember vt = new ViewMember(this, m);
                mAllMembers ~= vt;
                mEngineMemberToOurs[m.member] = vt;
            }
        }

        //xxx currently, there's no way to run these commands from the console
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();
        mCmds.register(Command("category", &cmdCategory, "-",
            ["text:catname"]));
        mCmds.register(Command("zoom", &cmdZoom, "-", ["bool:is_down"]));
        mCmds.register(Command("cyclenamelabels", &cmdNames, "worm name labels",
            ["int?:how much to show (if not given: cycle)"]));
        mCmds.register(Command("detail", &cmdDetail,
            "switch detail level", ["int?:detail level (if not given: cycle)"]));
        mCmds.register(Command("cameradisable", &cmdCameraDisable,
            "disable game camera", ["bool?:disable"]));
        mCmds.register(Command("move", &cmdMove, "-", ["text:key",
            "bool:down"]));
        mCmds.bind(mCmd);
    }

    private void cmdCategory(MyBox[] args, Output write) {
        char[] catname = args[0].unbox!(char[]);
        if (onSelectCategory)
            onSelectCategory(catname);
    }

    private void cmdZoom(MyBox[] args, Output write) {
        bool isDown = args[0].unbox!(bool);
        mZoomChange = isDown?-1:1;
    }

    private void cmdNames(MyBox[] args, Output write) {
        auto c = args[0].unboxMaybe!(int)(nameLabelLevel + 1);
        nameLabelLevel = c;
        write.writefln("set nameLabelLevel to {}", nameLabelLevel);
    }

    private void cmdDetail(MyBox[] args, Output write) {
        if (!mGame.cengine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        mGame.cengine.detailLevel = c >= 0 ? c : mGame.cengine.detailLevel + 1;
        write.writefln("set detailLevel to {}", mGame.cengine.detailLevel);
    }

    private void cmdCameraDisable(MyBox[] args, Output write) {
        enableCamera = !args[0].unboxMaybe!(bool)(enableCamera);
        write.writefln("set camera enable: {}", enableCamera);
    }

    private Vector2i handleDirKey(char[] key, bool up) {
        int v = up ? 0 : 1;
        switch (key) {
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
                //xxx reset on invalid key; is this kosher?
                return Vector2i(0);
        }

        return dirKeyState_rd-dirKeyState_lu;
    }

    private void cmdMove(MyBox[] args, Output write) {
        char[] key = args[0].unbox!(char[]);
        bool isDown = args[1].unbox!(bool);
        //translate the keyboard-based command into a state-based movement
        //command, needed because the commands are directly generated by the
        //binding stuff and are incompatible
        //can't do this in GameControl, because handling the dirKeyState in
        //presence of snapshotting etc. would be nasty
        auto movement = handleDirKey(key, !isDown);
        executeServerCommand(myformat("move {} {}", movement.x, movement.y));
    }

    private void doNewGraphic(Effect g) {
        if (auto txt = cast(TextGraphic)g) {
            addChild(new GameLabel(txt));
        }
    }

    Camera camera() {
        return mCamera;
    }
    void enableCamera(bool set) {
        mCamera.enable = set;
    }
    bool enableCamera() {
        return mCamera.enable;
    }
    void resetCamera() {
        mCamera.reset();
    }

    override Vector2i layoutSizeRequest() {
        return mGame.cengine.worldSize;
    }

    //find a WeaponClass of the weapon named "name" in the current team's
    //weapon-set (or return null)
    private WeaponClass findWeapon(char[] name) {
        auto cm = mGame.control.getControlledMember();
        if (!cm)
            return null;
        WeaponList weapons = cm.team.getWeapons();
        foreach (w; weapons) {
            if (w.type.name == name) {
                return w.available ? w.type : null;
            }
        }
        return null;
    }

    //takes a binding string from KeyBindings and replaces params
    //  %d -> true if key was pressed, false if released
    //  %mx, %my -> mouse position
    //also, will not trigger an up event for commands without %d param
    private char[] processBinding(char[] bind, bool isUp) {
        //no up/down parameter, and key was released -> no event
        if (str.find(bind, "%d") < 0 && isUp)
            return null;
        bind = str.replace(bind, "%d", str.toString(!isUp));
        bind = str.replace(bind, "%mx", str.toString(mousePos.x));
        bind = str.replace(bind, "%my", str.toString(mousePos.y));
        return bind;
    }
    override protected void onKeyEvent(KeyInfo ki) {
        auto bind = processBinding(findBind(ki), ki.isUp);
        if ((ki.isDown || ki.isUp()) && bind) {
            //if not processed locally, send
            if (!mCmd.execute(bind, true))
                executeServerCommand(bind);
            return;
        }
    }
    /*protected void onMouseMove(MouseInfo mouse) {
        auto bind = processBinding("set_target %mx %my", false);
        if (gFramework.getKeyState(Keycode.MOUSE_LEFT))
            mGame.control.executeCommand(bind);
    }*/

    private void executeServerCommand(char[] cmd) {
        mGame.control.executeCommand(cmd);
    }

    //grrr
    override bool onTestMouse(Vector2i pos) {
        return true;
    }

    float zoomLevel() {
        return mCurZoom;
    }

    override void simulate() {
        float zc = mZoomChange*(cZoomMax-cZoomMin)/cZoomTime.secsf
            * mGame.clientTime.difference.secsf;
        mCurZoom = clampRangeC(mCurZoom+zc, cZoomMin, cZoomMax);
        super.simulate();
        sim_camera();
        doSim();
    }

    //NOTE: there's the following problem: labels (stupidly) are GUI elements
    //      and thus are drawn separately from the game engine, so here's this
    //      (stupid) hack to fix the zorder of the labels
    private class DrawLabels : SceneObject {
        override void draw(Canvas canvas) {
            this.outer.doDraw(canvas);
        }
    }

    private void doDraw(Canvas c) {
        //call onDraw of the super class, not ours (wow this works)
        //this means all labels are drawn, but not the ClientEngine
        super.onDraw(c);
    }

    override void onDraw(Canvas c) {
        //no super.onDraw(c);, it's called through DrawLabels
        mGame.cengine.draw(c);
    }

    override bool doesCover() {
        return !mGame.cengine.needBackclear();
    }

    //camera priority of objects, from high to low:
    //  5 moving active worm (or super sheep, but not bazooka etc.)
    //  4 something fired by the active worm's weapon (including offspring)
    //  3 weapon offspring fired by other worms
    //  2 other worms
    //  1 other objects (like crates)
    //  0 (not moving) active worm
    //(active means we control the worm)
    //for objects with same priority, the camera tries to focus on the object
    //that moved last
    void sim_camera() {
        GameEngineGraphics graphics = mGame.engine.getGraphics();
        TeamMember active_member = mGame.control.getControlledMember();
        Team active_team;
        AnimationGraphic active_member_gr;
        if (active_member) {
            active_team = active_member.team;
            active_member_gr =
                cast(AnimationGraphic)active_member.getControlledGraphic();
        }
        Time now = graphics.timebase.current();

        int priority(AnimationGraphic gr) {
            //hmm
            bool moving = (now - gr.last_position_change).msecs < 200;
            //priorization as mentioned above
            if (!moving)
                return 0;
            if (gr is active_member_gr)
                return 5;
            if (active_team && gr.owner_team is active_team)
                return 4;
            if (gr.owner_team) {
                if (auto member = gr.owner_team.getActiveMember()) {
                    if (member.getGraphic() is gr)
                        return 2;
                }
                return 3;
            }
            return 1;
        }

        int best_priority;
        AnimationGraphic best_object;

        foreach (Graphic gr; graphics.objects) {
            if (auto ani_gr = cast(AnimationGraphic)gr) {
                int pri = priority(ani_gr);
                if (pri > best_priority) {
                    best_object = ani_gr;
                    best_priority = pri;
                } else if (pri == best_priority && best_object) {
                    if (ani_gr.last_position_change >
                        best_object.last_position_change)
                    {
                        best_object = ani_gr;
                    }
                }
            }
        }

        //if there's nothing else, focus on unmoving active worm
        if (!best_object) {
            best_object = active_member_gr;
        }

        void updateCurObj() {
            mCurCamObject = best_object;
            mCurCamPriority = best_priority;
            mLastCamChange = now;
        }

        if (best_object !is mCurCamObject) {
            //want to change focus
            //  to higher priority -> immediate
            //  to lower priority -> with delay cCamChangeDelay
            if (best_priority > mCurCamPriority
                || now - mLastCamChange > cCamChangeDelay)
            {
                updateCurObj();
            }
        } else if (mCurCamObject) {
            //focus unchanged
            //make sure the focused object does not immediately lose focus
            //  when it stops moving
            mLastCamChange = max(mLastCamChange,
                mCurCamObject.last_position_change);
        }

        if (mCurCamObject) {
            mCamera.updateCameraTarget(mCurCamObject.pos);
        } else {
            mCamera.noFollow();
        }
    }
}
