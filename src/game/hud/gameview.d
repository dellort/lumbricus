module game.hud.gameview;

import common.common;
import framework.font;
import framework.framework;
import framework.i18n;
import framework.commandline;
import framework.timesource;
import common.scene;
import game.animation;
import game.gamepublic;
import game.game;
import game.clientengine;
import game.sequence;
import game.controller;
import game.hud.camera;
import game.weapon.weapon;
import game.hud.teaminfo;
import game.gfxset;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import gui.tablecontainer;
import utils.configfile;
import utils.rect2;
import utils.time;
import utils.math;
import utils.misc;
import utils.vector2;
import utils.interpolate;

import str = utils.string;
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
        arrow.animation = canChangeWorm ? theme.change : theme.arrow;
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
        auto sprite = member.member.control.sprite; //lololol
        Sequence graphic = sprite.graphic;
        bool guiIsActive = !!graphic;
        if (sprite.isUnderWater()) //no labels when underwater
            guiIsActive = false;
        if (!guiIsActive) {
            removeGUI();
        } else if (guiIsActive) {
            assert(graphic !is null);
            //xxx hurf hurf
            Sequence ag = graphic;
            assert (!!ag, "not attached to a worm?");
            Sequence su = ag;
            assert(!!su);
            //Animation ani = ag.animation;
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
            bounds += ag.interpolated_position();

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
                    getControlledMember.control.lastAction()) < cArrowDelta;
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

            if (member.member.control.isDrowning()) {
                showLabels = false;
            }

            //(.value() isn't necessarily changing all the time)
            pos.y -= moveLabels.value();

            //that weapon label
            auto amember = owner.mGame.control.getControlledMember();
            bool weapon_visible = (amember is member.member)
                && amember.control.displayWeaponIcon();

            setWVisible(weaponIcon, weapon_visible);
            setArrowAnim(member.member.team.allowSelect());

            if (weapon_visible) {
                //NOTE: wwp animates the appearance/disappearance of
                // the weapon label; when it disappears, it shrinks and
                // moves towards the worm; we don't do that (yet?)
                //for now, only animate the left/right change of the
                //worm

                weaponIcon.image = amember.control.currentWeapon.icon;

                //possibly fix the animation
                //get where worm looks too
                bool faceLeft;
                if (su) {
                    faceLeft = angleLeftRight(su.rotation_angle, true,
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

            //flash label color to white for active worm
            void flash(bool on) {
                Font f = on ? member.owner.font_flash : member.owner.font;
                wormName.font = f;
                wormTeam.font = f;
                wormPoints.font = f;
            }
            flash(tlv && isActiveWorm
                && cast(int)(owner.mGame.clientTime.current.secsf*2)%2 == 0);

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

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Container {
    //these are all evil hacks and should go away
    void delegate() onTeamChange;
    void delegate() onKeyHelp;
    void delegate() onToggleWeaponWindow;
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
        //AnimationGraphic mCurCamObject;
        Time mLastCamChange;
        const cCamChangeDelay = timeSecs(1.2);
        TeamMember mLastActiveMember; //hack to detect worm activation
        Time mActivateTime;
        Vector2i mLastCamBorder;
        Time[2] mCBLastInc;
        const cMaxBorderSpeed = 350.0f;

        float mZoomChange = 1.0f, mCurZoom = 1.0f;

        //key state for LEFT/RIGHT and UP/DOWN
        Vector2i dirKeyState_lu = {0, 0};  //left/up
        Vector2i dirKeyState_rd = {0, 0};  //right/down

        //key binding identifier to game engine command (wormbinds map_commands)
        char[][char[]] mKeybindToCommand;
        //wormbinds.conf/map_commands
        ConfigNode mCommandMap;

        //for worm-name drawing
        ViewMember[] mAllMembers;
        ViewMember[TeamMember] mEngineMemberToOurs;

        GUITeamMemberSettings mTeamGUISettings;
        int mCycleLabels = 2;

        CommandLine mCmd;
        CommandBucket mCmds;

        ViewMember activeWorm;
        ViewMember lastActiveWorm;

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
        bool mCursorVisible = true;
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
    private void showDrown(TeamMemberInfo inf, int lost, Vector2i pos) {
        MoveLabel ml;
        auto lbl = inf.owner.createLabel();
        lbl.text = myformat("{}", lost);
        addChild(lbl);
        ml.label = lbl;
        ml.from = pos;
        ml.to = Vector2i(pos.x, mGame.engine.waterOffset);
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

        if (lastActiveWorm !is activeWorm) {
            lastActiveWorm = activeWorm;
            if (onTeamChange)
                onTeamChange();
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

    private void doMemberDrown(TeamMember member, int lost, Vector2i at) {
        showDrown(mGame.allMembers[member], lost, at);
    }

    override bool canHaveFocus() {
        return true;
    }
    override bool greedyFocus() {
        return true;
    }

    this(GameInfo game) {
        mGame = game;

        readd_graphics();

        mGame.engine.callbacks.memberDrown ~= &doMemberDrown;

        mCamera = new Camera(mGame.clientTime);

        //load the teams and also the members
        foreach (TeamInfo t; game.teams) {
            foreach (TeamMemberInfo m; t.members) {
                ViewMember vt = new ViewMember(this, m);
                mAllMembers ~= vt;
                mEngineMemberToOurs[m.member] = vt;
            }
        }

        //all keybinding stuff

        ConfigNode wormbindings = loadConfig("wormbinds");
        mCommandMap = wormbindings.getSubNode("map_commands");

        bindings = new KeyBindings();
        bindings.loadFrom(wormbindings.getSubNode("binds"));

        //categories...
        foreach (ConfigNode cat; mCommandMap) {
            //commands...
            foreach (ConfigNode cmd; cat) {
                mKeybindToCommand[cmd.name] = cmd.value;
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
        //xxx these should be in gameframe.d
        mCmds.register(Command("keybindings_help", &cmdShowKeybinds, "-", []));
        mCmds.register(Command("toggle_weaponwindow", &cmdToggleWeaponWnd, "-",
            []));
        mCmds.register(Command("toggle_scroll", &cmdToggleScroll, "-", []));
        mCmds.bind(mCmd);
    }

    void readd_graphics() {
        SceneObject labels = new DrawLabels();
        labels.zorder = GameZOrder.Names;
        mGame.cengine.scene.add(labels);
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

    private void cmdShowKeybinds(MyBox[] args, Output write) {
        if (onKeyHelp)
            onKeyHelp();
    }

    private void cmdToggleWeaponWnd(MyBox[] args, Output write) {
        if (onToggleWeaponWindow)
            onToggleWeaponWindow();
    }

    private void cmdToggleScroll(MyBox[] args, Output write) {
        //hacky: when in mouse-follow mode, right-click shows the weapon window
        //  (which will end mouse-follow mode)
        if (mCamera.control.mouseFollow())
            onToggleWeaponWindow();
        else
            mCamera.control.mouseScrollToggle();
    }

    //should be moved elsewhere etc.
    //this dialog should be game-independent anyway
    Widget createKeybindingsHelp() {
        Translator tr_cat = localeRoot.bindNamespace("wormbinds_categories");
        Translator tr_ids = localeRoot.bindNamespace("wormbinds_ids");
        auto table = new TableContainer(2, 0, Vector2i(20, 0));
        table.styles.addClass("keybind_help_table");
        //category...
        foreach (ConfigNode cat; mCommandMap) {
            auto head = new Label();
            head.text = tr_cat(cat.name);
            head.styles.addClass("keybind_help_header");
            table.addRow();
            table.add(head, 0, table.height-1, 2, 1);
            //command...
            foreach (ConfigNode cmd; cat) {
                char[] id = cmd.name;
                auto caption = new Label();
                caption.text = tr_ids(id);
                caption.styles.addClass("keybind_help_caption");
                auto bind = new Label();
                bind.text = globals.translateBind(this.bindings, id);
                bind.styles.addClass("keybind_help_bind");
                table.addRow();
                table.add(caption, 0, table.height-1);
                table.add(bind, 1, table.height-1);
            }
        }
        return table;
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
        return mGame.engine.level.worldSize;
    }

    //find a WeaponClass of the weapon named "name" in the current team's
    //weapon-set (or return null)
    private WeaponClass findWeapon(char[] name) {
        return mGame.engine.gfx.findWeaponClass(name, true);
    }

    //takes a binding string from KeyBindings and replaces params
    //  %d -> true if key was pressed, false if released
    //  %mx, %my -> mouse position
    //also, will not trigger an up event for commands without %d param
    private char[] processBinding(char[] bind, bool isUp) {
        //no up/down parameter, and key was released -> no event
        if (str.find(bind, "%d") < 0 && isUp)
            return null;
        bind = str.replace(bind, "%d", myformat("{}", !isUp));
        bind = str.replace(bind, "%mx", myformat("{}", mousePos.x));
        bind = str.replace(bind, "%my", myformat("{}", mousePos.y));
        return bind;
    }
    override protected void onKeyEvent(KeyInfo ki) {
        if (ki.isDown() || ki.isUp()) {
            char[] bind = findBind(ki);
            if (auto pcmd = bind in mKeybindToCommand) {
                bind = processBinding(*pcmd, ki.isUp);
            }
            if (!bind.length)
                return;
            //if not processed locally, send
            if (!mCmd.execute(bind, true))
                executeServerCommand(bind);
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

        //mouse stuff at last?
        //if (mouseOverState)
        mCursorVisible = mGame.engine.renderOnMouse(c, mousePos);

        //hmpf
        (cast(GameEngine)mGame.engine).debug_draw(c);
    }

    override MouseCursor mouseCursor() {
        return mCursorVisible ? MouseCursor.Standard : MouseCursor.None;
    }

    override bool doesCover() {
        return !mGame.cengine.needBackclear();
    }

    //camera priority of objects, from high to low:
    //  5 moving active worm (or super sheep, but not bazooka etc.)
    //  4 something fired by the active worm's weapon (including offspring)
    //  3 weapon offspring fired by other worms
    //  -- not anymore -- 2 other worms
    //  1 other objects (like crates)
    //  0 (not moving) active worm
    //(active means we control the worm)
    //for objects with same priority, the camera tries to focus on the object
    //that moved last
    //xxx: camera should use game objects instead of graphic stuff
    void sim_camera() {
        Time now = mGame.clientTime.current;

        Sequence cur;
        TeamMember member = mGame.control.getControlledMember();
        if (member) {
            cur = member.control.controlledSprite.graphic;
        }

        if (cur) {
            Vector2f velocity = cur.velocity;
            Vector2i position = cur.interpolated_position();
            //the following calculates the optimum camera border based
            //  on the speed of the tracked object
            if (true) {
                //calculate velocity multiplier, so an object at cMaxBorderSpeed
                //  would be exactly centered
                Vector2f optMult = toVector2f(mCamera.control.size/2
                    - Camera.cCameraBorder) / cMaxBorderSpeed;

                //border increases by velocity, component-wise
                auto camBorder = Camera.cCameraBorder
                    + toVector2i(velocity.abs ^ optMult);
                //always leave a small area at screen center
                camBorder.clipAbsEntries(mCamera.control.size/2 - Vector2i(50));

                //Now the funny part: we don't want to update the border too
                //  often if an object is flying towards it, or the camera
                //  would look jerky; so I chose to increase the border
                //  immediately, and allow decreasing it only after a 1s
                //  delay (component-wise again)
                for (int i = 0; i < 2; i++) {
                    if (camBorder[i] >= mLastCamBorder[i]) {
                        mLastCamBorder[i] = camBorder[i];
                        mCBLastInc[i] = now;
                    } else if ((now - mCBLastInc[i]).msecs > 1000) {
                        mLastCamBorder[i] = camBorder[i];
                    }
                }
            } else {
                mLastCamBorder = Camera.cCameraBorder;
            }

            mCamera.updateCameraTarget(position,
                mLastCamBorder);
        } else {
            mCamera.noFollow();
        }

        mGame.cengine.setViewArea(mCamera.visibleArea);
    }
}
