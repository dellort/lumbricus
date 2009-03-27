module game.hud.gameview;

import common.common;
import framework.font;
import framework.framework;
import framework.commandline;
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

import str = stdx.string;
import math = tango.math.Math;

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
//time to zoom out
const Time cZoomTime = timeMsecs(500);
//min/max zooming level
const float cZoomMin = 0.6f;
const float cZoomMax = 1.0f;

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
        ClientGameEngine mEngine;
        GameLogicPublic mLogic;
        ClientControl mController;
        GameInfo mGame;
        Container mGuiFrame;

        Camera mCamera;

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
                    //xxx hurf hurf
                    auto ag = cast(AnimationGraphic)graphic;
                    assert (!!ag, "not attached to a worm?");
                    Animation ani = ag.animation;
                    lastKnownPosition = ag.pos;
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

                    //activate camera if it should and wasn't yet
                    if (!cameraActivated && member.member.active()) {
                        cameraActivated = true;
                        mCamera.setCameraFocus(this);
                    }

                    //labels are positioned above pos
                    auto pos = bounds.center;
                    pos.y -= bounds.size.y/2;

                    bool isActiveWorm = this is activeWorm;

                    //whether labels should move up or down
                    //initiate movement into this direction if not yet
                    bool doMoveDown;

                    if (isActiveWorm) {
                        auto currentTime = mEngine.engineTime.current();
                        bool didmove = (currentTime - mController.
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
                    auto amember = mController.getControlledMember();
                    bool weapon_visible = (amember is member.member)
                        && amember.displayWeaponIcon();

                    setWVisible(weaponIcon, weapon_visible);

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
                            bounds, Vector2i(0, -1), wip, 0.5f);
                        npos += bounds.p1;
                        setWPos(weaponIcon, npos);
                    } else {
                        moveWeaponIcon.reset();
                        moveWeaponIcon.start = moveWeaponIcon.target = 0;
                    }

                    void mooh(bool vis, Widget w) {
                        setWVisible(w, vis);
                        if (!vis)
                            return;
                        Vector2i sz = w.requestSize;
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
                            healthHint.text = myformat("{}", -diff);
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
        mCamera.doFrame();
        mCamera.paused = mEngine.engineTime.paused();

        activeWorm = null;
        if (auto am = mController.getControlledMember()) {
            auto pam = am in mEngineMemberToOurs;
            activeWorm = pam ? *pam : null;
        }

        foreach (m; mAllMembers) {
            m.simulate();
        }
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(GameInfo game) {
        mEngine = game.cengine;
        mGame = game;

        mCamera = new Camera();

        //hacky?
        mLogic = game.logic;
        mController = game.control;

        //load the teams and also the members
        foreach (TeamInfo t; game.teams) {
            foreach (TeamMemberInfo m; t.members) {
                ViewMember vt = new ViewMember(m);
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
        if (!mEngine)
            return;
        int c = args[0].unboxMaybe!(int)(-1);
        mEngine.detailLevel = c >= 0 ? c : mEngine.detailLevel + 1;
        write.writefln("set detailLevel to {}", mEngine.detailLevel);
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
        return mEngine.worldSize;
    }

    //find a WeaponClass of the weapon named "name" in the current team's
    //weapon-set (or return null)
    private WeaponHandle findWeapon(char[] name) {
        auto cm = mController.getControlledMember();
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
            mController.executeCommand(bind);
    }*/

    private void executeServerCommand(char[] cmd) {
        mController.executeCommand(cmd);
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
            * globals.gameTimeAnimations.difference.secsf;
        mCurZoom = clampRangeC(mCurZoom+zc, cZoomMin, cZoomMax);
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
