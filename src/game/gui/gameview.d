module game.gui.gameview;

import common.common;
import framework.font;
import framework.framework;
import common.scene;
import game.animation;
import game.gamepublic;
import game.clientengine;
import game.sequence;
import game.gui.camera;
import game.weapon.weapon;
import game.gui.teaminfo;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import utils.rect2;
import utils.time;
import utils.math;
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
        mAnimator.setAnimation(ani);
        needResize(true);
    }

    void setPositionCentered(Vector2i newPos) {
        setAddToPos(newPos - mAnimator.bounds.size/2);
    }
}

//this is a try to get rid of the code duplication (although it's too late)
//it's rather trivial, but annoying
//when started, it interpolates from one value to another in a given time span
//T must be a scalar, like float or int
//timesource is currently fixed to that animation stuff
//all fields are read-only (in gameframe I have some code for changing "targets")
struct InterpolateLinearTime(T) {
    Time startTime, duration;
    T start;
    T target;

    static Time currentTime() {
        return globals.gameTimeAnimations.current();
    }

    void init(Time a_duration, T a_start, T a_target) {
        startTime = currentTime();
        duration = a_duration;
        start = a_start;
        target = a_target;
    }

    //start so that it behaves like with init(), but value() is already at
    //a_value (which means the startTime is adjusted so that it fits)
    //xxx would be simpler if there was a speed value rather than the
    //  start/target/time values
    void initBetween(Time a_duration, T a_start, T a_value, T a_target) {
        init(a_duration, a_start, a_target);
        float progress = cast(float)(a_value - a_start) / (a_target - a_start);
        startTime -= a_duration * progress;
    }

    T value() {
        auto d = currentTime() - startTime;
        if (d >= duration) {
            return target;
        }
        //have to scale it without knowing what datatype it is
        return start + cast(T)((target - start)
            * (cast(float)d.msecs / duration.msecs));
    }

    Time endTime() {
        return startTime + duration;
    }

    //return if the value is still changing (false when this is uninitialized)
    bool inProgress() {
        return currentTime() < endTime;
    }
}

//interpolate according to a mapping function
struct InterpolateFnTime(T) {
    Time startTime, duration;
    T start;
    T target;
    //the mapping function; inp is the time scaled to 0..1; the result is 0..1
    //and will be scaled to start..target
    float delegate(float inp) fn;

    static Time currentTime() {
        return timeCurrentTime();//globals.gameTimeAnimations.current();
    }

    void init(Time a_duration, T a_start, T a_target) {
        startTime = currentTime();
        duration = a_duration;
        start = a_start;
        target = a_target;
        assert(!!fn, "function not set");
    }

    T value() {
        if (!fn)
            return start;
        auto d = currentTime() - startTime;
        if (d >= duration) {
            return target;
        }
        //have to scale it without knowing what datatype it is
        return start + cast(T)((target - start)
            * fn(cast(float)d.msecs / duration.msecs));
    }

    Time endTime() {
        return startTime + duration;
    }


    //return if the value is still changing (false when this is uninitialized)
    bool inProgress() {
        return currentTime() < startTime + duration;
    }

    //set everything to init except fn
    void reset() {
        startTime = duration = Time.init;
        start = target = T.init;
    }
}

//sc, result = [0,1] -> [0,1], exponential-like curve
//a, r = where to cut off the curve
float interpolateExponential(float sc, float a = 4.0f, float r = 2.0f) {
    //to stay within [0,1], substract the not reached difference to 0
    float s(float sc) { return 1.0f - (math.exp(sc * -a) - sc * math.exp(-a)); }
    return s(sc*r)/s(r);
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
//time swap left/right position of weapon icon
const Time cWeaponIconMoveTime = timeMsecs(300);

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Container, TeamMemberControlCallback {
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

        GUITeamMemberSettings mTeamGUISettings;
        int mCycleLabels = 2;

        ViewMember activeWorm;

        //per-member class
        class ViewMember : CameraObject {
            TeamMemberInfo member; //from the "engine"

            //you might wonder why these labels aren't just drawn directly
            //instead we use the GUI... well but there's no reason
            //it's just plain stupid :D
            Label wormTeam;
            Label wormName;
            Label wormPoints; //oh, it used to be named "points"
            //for the alternative weapon display
            Label weaponIcon;

            InterpolateFnTime!(float) moveWeaponIcon;

            //arrow which points on currently active worm (goes away when he moves)
            //(there's only one per GUI, but keeping it here is simpler)
            GuiAnimator arrow;

            InterpolateLinearTime!(int) moveLabels;
            //bool beingActive; //last active state to detect state change

            //label which displays how much health was lost
            //starts from real health label, moves up, and disappears
            Label healthHint;

            InterpolateLinearTime!(int) moveHealth;

            int health_cur = int.max;
            int lastHealthHintTarget = int.max;

            bool cameraActivated;
            Vector2i lastKnownPosition;

            this(TeamMemberInfo m) {
                member = m;
                wormTeam = m.owner.createLabel();
                wormName = m.owner.createLabel();
                wormName.text = m.member.name();
                wormPoints = m.owner.createLabel();
                healthHint = m.owner.createLabel();
                weaponIcon = m.owner.createLabel();
                weaponIcon.text = "";
                arrow = new GuiAnimator();
                arrow.animation = member.owner.theme.arrow.get;
                moveWeaponIcon.fn = &interpolate2Exp;
                //get rid of nan
                moveWeaponIcon.start = moveWeaponIcon.target = 0;
            }

            //looks like this:   | 0.0 slow ... fast 0.5 fast ... slow 1.0 |
            float interpolate2Exp(float inp) {
                auto dir = inp < 0.5f;
                inp = dir ? 0.5f - inp : inp - 0.5f;
                auto res = interpolateExponential(inp) / 2;
                return dir ? 0.5f - res : res + 0.5f;
            }

            Vector2i getCameraPosition() {
                return lastKnownPosition;
            }
            bool isCameraAlive() {
                cameraActivated &= member.member.active();
                return cameraActivated;
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
                    this.outer.addChild(w);
                }
            }

            void simulate() {
                auto graphic = member.member.getGraphic();
                bool guiIsActive = !!graphic;
                if (!guiIsActive) {
                    removeGUI();
                } else if (guiIsActive) {
                    assert(graphic !is null);
                    lastKnownPosition = graphic.bounds.center;

                    if (health_cur != member.currentHealth) {
                        health_cur = member.currentHealth;
                        wormPoints.text = format("%s", health_cur);
                    }

                    //activate camera if it should and wasn't yet
                    if (!cameraActivated && member.member.active()) {
                        cameraActivated = true;
                        mCamera.setCameraFocus(this);
                    }

                    //labels are positioned above pos
                    auto pos = graphic.bounds.center;
                    pos.y -= graphic.bounds.size.y/2;

                    bool isActiveWorm = this is activeWorm;

                    //whether labels should move up or down
                    //initiate movement into this direction if not yet
                    bool doMoveDown;

                    if (isActiveWorm) {
                        auto currentTime = mEngine.engineTime.current();
                        bool didmove = (currentTime
                            - mController.currentLastAction()) < cArrowDelta;
                        doMoveDown = !didmove;
                    } else {
                        //move labels down, but arrow is invisible
                        doMoveDown = true;
                    }

                    //if the moving direction isn't correct, reverse it
                    if (doMoveDown != (moveLabels.target <= moveLabels.start)) {
                        if (doMoveDown) {
                            //make labels visible & move down
                            moveLabels.initBetween(cLabelsMoveTimeDown,
                                cLabelsMoveDistance, moveLabels.value, 0);
                        } else {
                            //move up
                            moveLabels.initBetween(cLabelsMoveTimeUp,
                                0, moveLabels.value, cLabelsMoveDistance);
                        }
                    }

                    bool showLabels = true;

                    if (!moveLabels.inProgress() && !doMoveDown) {
                        showLabels = !isActiveWorm;
                    }

                    //(.value() isn't necessarily changing all the time)
                    pos.y -= moveLabels.value();

                    //that weapon label
                    auto amember = mController.getActiveMember();
                    bool weapon_visible = (amember is member.member)
                        && mController.displayWeaponIcon();

                    setWVisible(weaponIcon, weapon_visible);

                    if (weapon_visible) {
                        //NOTE: wwp animates the appearance/disappearance of
                        // the weapon label; when it disappears, it shrinks and
                        // moves towards the worm; we don't do that (yet?)
                        //for now, only animate the left/right change of the
                        //worm

                        weaponIcon.image = mController.currentWeapon.icon.get;

                        //possibly fix the animation
                        //get where worm looks too
                        bool faceLeft;
                        if (auto se = cast(Sequence)graphic) {
                            SequenceUpdate sd;
                            se.getInfos(sd);
                            faceLeft = angleLeftRight(sd.rotation_angle, true,
                                false);
                        }
                        if (moveWeaponIcon.start == moveWeaponIcon.target) {
                            //rather a cheap trick to distinguish initialization
                            //from not-animating state
                            moveWeaponIcon.start = faceLeft ? 1 : 0;
                            moveWeaponIcon.target = faceLeft ? 0 : 1;
                            moveWeaponIcon.duration = Time.Null;
                        } else {
                            bool rtol = moveWeaponIcon.start
                                > moveWeaponIcon.target;
                            if (rtol != faceLeft) {
                                if (moveWeaponIcon.inProgress()) {
                                    //change direction (works because
                                    //interpolation function is symmetric)
                                    swap(moveWeaponIcon.start,
                                        moveWeaponIcon.target);
                                    auto cur = moveWeaponIcon.currentTime;
                                    auto diff = cur
                                        - moveWeaponIcon.startTime;
                                    diff = moveWeaponIcon.duration - diff;
                                    moveWeaponIcon.startTime = cur - diff;
                                } else {
                                    moveWeaponIcon.init(cWeaponIconMoveTime,
                                        faceLeft ? 1 : 0, faceLeft ? 0 : 1);
                                }
                            }
                        }

                        //set the position
                        float wip = moveWeaponIcon.value();
                        auto npos = placeRelative(Rect2i(weaponIcon.size()),
                            graphic.bounds, Vector2i(0, -1), wip, 0.5f);
                        npos += graphic.bounds.p1;
                        setWPos(weaponIcon, npos);
                    } else {
                        moveWeaponIcon.reset();
                        moveWeaponIcon.start = moveWeaponIcon.target = 0;
                    }

                    void mooh(bool vis, Widget w) {
                        setWVisible(w, vis);
                        if (!vis)
                            return;
                        Vector2i sz = w.size;
                        pos.y -= sz.y;
                        //pos.y -= 1; //some spacing, but it looks ugly
                        auto p = pos;
                        p.x -= sz.x/2; //center
                        setWPos(w, p);
                    }
                    auto tlv = showLabels && !weapon_visible;
                    mooh(tlv && mTeamGUISettings.showPoints, wormPoints);
                    mooh(tlv && mTeamGUISettings.showName, wormName);
                    mooh(tlv && mTeamGUISettings.showTeam, wormTeam);
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
                            healthHint.text = format("%s", -diff);
                            this.outer.addChild(healthHint);
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

    private void doSim() {
        mCamera.paused = mEngine.engineTime.paused();

        foreach (m; mAllMembers) {
            m.simulate();
        }

        activeWorm = null;
        if (auto am = mController.getActiveMember()) {
            auto pam = am in mEngineMemberToOurs;
            activeWorm = pam ? *pam : null;
        }
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(ClientGameEngine engine, Camera cam, GameInfo game) {
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

        bool isPrefix(char[] s, char[] prefix) {
            return s.length >= prefix.length && s[0..prefix.length] == prefix;
        }

        //try if it's a wapon shortcut
        //(oh lol, kind of unclean?)
        const cWShortcut = "weapon_";
        if (isPrefix(bind, cWShortcut)) {
            auto wcname = bind[cWShortcut.length..$];
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

        //I see a pattern...
        const cCShortcut = "category_";
        if (isPrefix(bind, cCShortcut)) {
            auto cname = bind[cCShortcut.length..$];
            if (onSelectCategory)
                onSelectCategory(cname);
        }

        //nothing found
        return false;
    }

    override protected void onKeyEvent(KeyInfo ki) {
        auto bind = findBind(ki);
        if (ki.isDown && onKeyDown(bind, ki)) {
            return;
        } else if (ki.isUp) {
            handleDirKey(bind, true);
        }
    }

    //grrr
    override bool onTestMouse(Vector2i pos) {
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
