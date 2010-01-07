module game.hud.gameview;

import common.common;
import framework.font;
import framework.framework;
import framework.i18n;
import framework.commandline;
import framework.timesource;
import common.animation;
import common.scene;
import game.glue;
import game.game;
import game.clientengine;
import game.sequence;
import game.controller;
import game.hud.camera;
import game.weapon.weapon;
import game.hud.teaminfo;
import game.gfxset;
import game.worm; //for a hack
import gui.renderbox;
import gui.rendertext;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import gui.tablecontainer;
import physics.world;
import utils.configfile;
import utils.rect2;
import utils.time;
import utils.math;
import utils.misc;
import utils.vector2;
import utils.interpolate;

import str = utils.string;
import math = tango.math.Math;

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

//just for the weapon image
class BorderImage : SceneObjectCentered {
    Surface image;
    BoxProperties border;

    override void draw(Canvas c) {
        auto s = image.size/2;
        auto b = Vector2i(border.borderWidth);
        drawBox(c, pos-s-b, image.size+b*2, border);
        c.draw(image, pos-s);
    }

    Vector2i size() {
        return image.size + Vector2i(border.borderWidth)*2;
    }
}

//per-member class
private class ViewMember : SceneObject {
    GameView owner;
    TeamMember member; //from the "engine"

    FormattedText wormTeam, wormName, wormPoints;

    InterpolateExp2!(float, 4.0f) moveWeaponIcon;

    InterpolateLinear!(int) moveLabels;

    //label which displays how much health was lost
    //starts from real health label, moves up, and disappears
    FormattedText healthHint;

    BorderImage weaponIcon;

    InterpolateLinear!(int) moveHealth;

    int lastHealthHintTarget = int.max;

    this(GameView a_owner, TeamMember m) {
        owner = a_owner;
        auto ts = owner.mGame.clientTime;
        moveLabels.currentTimeDg = &ts.current;
        moveHealth.currentTimeDg = &ts.current;
        moveWeaponIcon.currentTimeDg = &ts.current;
        member = m;
        TeamTheme theme = team.color;
        wormTeam = theme.textCreate();
        wormTeam.setLiteral(team.name());
        wormName = theme.textCreate();
        wormName.setLiteral(member.name());
        wormPoints = theme.textCreate();
        healthHint = theme.textCreate();
        weaponIcon = new BorderImage;
        weaponIcon.border = GfxSet.textWormBorderStyle();

        owner.mLabels.add(this);
    }

    Team team() {
        return member.team;
    }

    bool isControlled() {
        TeamMember controlled = owner.mGame.control.getControlledMember();
        return controlled is member;
    }

    override void draw(Canvas canvas) {
        auto sprite = member.control.sprite; //lololol
        Sequence graphic = sprite.graphic;

        if (!graphic) {
            removeThis();
            //show the drown label
            if (sprite.isUnderWater()) {
                int lost = member.currentHealth - member.health();
                owner.memberDrown(member, lost, toVector2i(sprite.physics.pos));
            }
            return;
        }

        if (sprite.isUnderWater()) //no labels when underwater
            return;

        //ughh, needs correct bounding box
        const d = 30;
        Rect2i bounds = Rect2i(-d, -d, d, d);
        bounds += graphic.interpolated_position();

        wormPoints.setTextFmt(false, "{}", member.currentHealth);

        //labels are positioned above pos
        Vector2i pos = bounds.center;
        pos.y -= bounds.size.y/2;

        //add rectangle under pos variable, return the rect's position
        //center_pos = centered drawing (animations)
        Vector2i addThing(Vector2i size, bool center_pos = false) {
            pos.y -= size.y;
            //pos.y -= 1; //some spacing, but it looks ugly
            auto p = pos;
            if (!center_pos) {
                p.x -= size.x/2;
            } else {
                p.y += size.y/2;
            }
            return p;
        }

        void addLabel(FormattedText txt) {
            txt.draw(canvas, addThing(txt.size));
        }
        void addAnimation(Animation ani) {
            AnimationParams p;
            Time t = owner.mGame.clientTime.current;
            ani.draw(canvas, addThing(ani.bounds.size, true), p, t);
        }


        bool isActiveWorm = this is owner.activeWorm;

        //whether labels should move up or down
        //initiate movement into this direction if not yet
        bool doMoveDown = true;

        if (isActiveWorm) {
            auto currentTime = owner.mGame.serverTime.current;
            bool didmove = (currentTime - owner.mGame.control.
                getControlledMember.control.lastAction()) < cArrowDelta;
            doMoveDown = !didmove;
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

        //(.value() isn't necessarily changing all the time)
        pos.y -= moveLabels.value();

        auto health_hint_pos = pos;

        bool showLabels = true;

        if (!moveLabels.inProgress() && !doMoveDown) {
            showLabels = !isActiveWorm;
        }

        //xxx there's some bug that makes Worm.actualWeapon() and
        //  WormControl.currentWeapon return different Weapons, which looks
        //  confusing (weapon icon and weapon as displayed by Sequence will be
        //  different); that can be easily fixed as soon as the weapon control
        //  code in Worm gets merged into WormControl; but for now it's a
        //  damn clusterfuck, and I use this hack to make it look right
        auto worm = cast(WormSprite)sprite;
        WeaponClass wicon;
        if (worm)
            wicon = worm.displayedWeapon();

/+
        //show a weapon icon when the worm graphic wants to show a weapon,
        //  but fails to select an animation; happens when:
        //   a) we are in weapon state, but have no animation
        //   b) main weapon is busy, but secondary is ready
        //      (meaning worm animation is showing primary weapon)
        bool weapon_icon_visible = isControlled()
            && graphic.weapon.length && !graphic.weapon_ok
            && member.control.currentWeapon;
+/
        bool weapon_icon_visible = wicon && !graphic.weapon_ok;

        if (weapon_icon_visible) {
            //NOTE: wwp animates the appearance/disappearance of
            // the weapon label; when it disappears, it shrinks and
            // moves towards the worm; we don't do that (yet?)
            //for now, only animate the left/right change of the
            //worm

            //possibly fix the animation
            //get where worm looks too
            bool faceLeft = angleLeftRight(graphic.rotation_angle, true, false);
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

            Surface icon = wicon.icon;
            assert(!!icon);
            float wip = moveWeaponIcon.value();
            auto npos = placeRelative(Rect2i(icon.size()),
                bounds, Vector2i(0, -1), wip, 0.5f);
            npos += bounds.p1;
            //lolwut? I know I wrote this code, but *shrug*
            weaponIcon.image = icon;
            weaponIcon.pos = npos + weaponIcon.size/2;
            weaponIcon.draw(canvas);
            //so that the arrow animation is at the right place
            addThing(weaponIcon.size);
        } else {
            moveWeaponIcon.reset();
        }

        auto tlv = showLabels && !weapon_icon_visible;
        if (tlv) {
            //flash label color to white for active worm
            bool flash_on = (isActiveWorm
                && cast(int)(owner.mGame.clientTime.current.secsf*2)%2 == 0);
            Font f = flash_on ? team.color.font_flash : team.color.font;
            wormName.font = f;
            wormTeam.font = f;
            wormPoints.font = f;

            if (owner.mTeamGUISettings.showPoints)
                addLabel(wormPoints);
            if (owner.mTeamGUISettings.showName)
                addLabel(wormName);
            if (owner.mTeamGUISettings.showTeam)
                addLabel(wormTeam);
        }

        if (showLabels && isActiveWorm) {
            auto theme = team.color;
            auto ani = team.allowSelect() ? theme.change : theme.arrow;
            addAnimation(ani);
        }

        //for healthHint
        //I simply trigger it when the health value changes, and
        //when currently no label is displayed
        //the label is only removed as soon as the health value is
        //constant again
        //slight duplication of the logic in gameframes
        if (moveHealth.currentTime >= moveHealth.endTime
            + cHealthHintWait)
        {
            //probably start a new animation
            auto target = member.currentHealth();
            auto diff = member.healthTarget() - target;
            //compare target and realHealth to see if health is
            //really changing (diff can still be != 0 if not)
            if (diff < 0 && target != lastHealthHintTarget) {
                //start (only for damages, not upgrades => "< 0")
                moveHealth.init(cHealthHintTime, 0,
                    cHealthHintDistance);
                healthHint.setTextFmt(false, "{}", -diff);
                //this is to avoid restarting the label animation several times
                //  when counting down takes longer than to display the full
                //  health damage hint animation
                lastHealthHintTarget = target;
            }
        }
        if (moveHealth.inProgress()) {
            pos = health_hint_pos;
            pos.y -= moveHealth.value();
            canvas.pushState();
            canvas.setBlend(Color(1, 1, 1, 1.0f - moveHealth.fvalue()));
            addLabel(healthHint);
            canvas.popState();
        }
    }
} //ViewMember

enum MoveLabelEffect {
    move,   //straight
    bubble, //like in water
}

class DrownLabel : SceneObject {
    private {
        GameInfo mGame;
        MoveLabelEffect mEffect;
        FormattedText mTxt;
        Time mStart;
        float mSpeed; //pixels/second
        Vector2i mFrom, mTo;
    }

    //member inf drowned at pos (pos is on the ground)
    this(GameInfo a_game, TeamMember m, int lost, Vector2i pos) {
        mGame = a_game;
        mTxt = m.team.color.textCreate();
        mTxt.setTextFmt(false, "{}", lost);
        mFrom = pos;
        mTo = Vector2i(pos.x, mGame.engine.waterOffset);
        mStart = mGame.clientTime.current;
        mEffect = MoveLabelEffect.bubble;
        mSpeed = cDrownLabelSpeed;
    }

    override void draw(Canvas c) {
        auto now = mGame.clientTime.current;

        auto dir = toVector2f(mTo) - toVector2f(mFrom);
        auto px = (now-mStart).secsf * mSpeed;
        auto move = px * dir.normal;

        if (move.length >= dir.length) {
            removeThis();
            return;
        }

        if (mEffect == MoveLabelEffect.bubble) {
            const cPxArc = 50; //so many sinus curves over a pixel distance
            const cArcAmp = 10; //amplitude of sinus curve
            auto idx = px / cPxArc * math.PI * 2;
            move.x += math.sin(idx) * cArcAmp;
        }

        auto curpos = mFrom + toVector2i(move);

        mTxt.draw(c, curpos);
    }
}

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
class GameView : Widget {
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

        Scene mLabels;

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
        ViewMember[TeamMember] mEngineMemberToOurs;

        GUITeamMemberSettings mTeamGUISettings;
        int mCycleLabels = 2;

        CommandLine mCmd;
        CommandBucket mCmds;

        ViewMember activeWorm;
        ViewMember lastActiveWorm;

        bool mCursorVisible = true;
    } //private

    void setGUITeamMemberSettings(GUITeamMemberSettings s) {
        mTeamGUISettings = s;
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
    }

    void memberDrown(TeamMember member, int lost, Vector2i at) {
        mLabels.add(new DrownLabel(mGame, member, lost, at));
    }

    override bool greedyFocus() {
        return true;
    }

    this(GameInfo game) {
        mGame = game;
        mLabels = new Scene();
        mLabels.zorder = GameZOrder.Names;

        readd_graphics();

        mCamera = new Camera(mGame.clientTime);

        //load the teams and also the members
        foreach (Team t; game.engine.controller.teams) {
            foreach (TeamMember m; t.getMembers) {
                ViewMember vt = new ViewMember(this, m);
                mEngineMemberToOurs[m] = vt;
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

    private class LevelEndDrawer : SceneObject {
        Vertex2f[4] mQuad;
        const cIn = Color.Transparent;
        const cOut = Color(1.0, 0, 0, 0.5);
        bool mLeft, mRight;

        this(bool left, bool right) {
            mLeft = left;
            mRight = right;
            //horizontal gradient
            mQuad[0].c = cOut;
            mQuad[1].c = cIn;
            mQuad[2].c = cIn;
            mQuad[3].c = cOut;
        }
        override void draw(Canvas canvas) {
            if (canvas.features & DriverFeatures.transformedQuads) {
                if (mLeft) {
                    //left side
                    mQuad[0].p = Vector2f(0);
                    mQuad[1].p = Vector2f(30, 0);
                    mQuad[2].p = Vector2f(30, canvas.clientSize.y);
                    mQuad[3].p = Vector2f(0, canvas.clientSize.y);
                    canvas.drawQuad(null, mQuad);
                }
                if (mRight) {
                    //right side
                    mQuad[0].p = Vector2f(canvas.clientSize.x, 0);
                    mQuad[1].p = Vector2f(canvas.clientSize.x - 30, 0);
                    mQuad[2].p = Vector2f(canvas.clientSize.x - 30,
                        canvas.clientSize.y);
                    mQuad[3].p = Vector2f(canvas.clientSize.x, canvas.clientSize.y);
                    canvas.drawQuad(null, mQuad);
                }
            }
        }
    }

    void readd_graphics() {
        mGame.cengine.scene.add(mLabels);

        //xxx what a dirty hack...
        //check for a geometry collision outside the world area on the left
        //  and right. if it collides, there is a PlaneGeometry blocking access
        //  (and the level end warning is not drawn on that side)
        GeomContact tmp;
        Vector2i worldSize = mGame.engine.level.worldSize;
        bool left = !mGame.engine.physicworld.collideGeometry(
            Vector2f(-100, worldSize.y/2), 1, tmp);
        bool right = !mGame.engine.physicworld.collideGeometry(
            Vector2f(worldSize.x + 100, worldSize.y/2), 1, tmp);
        SceneObject levelend = new LevelEndDrawer(left, right);
        levelend.zorder = GameZOrder.RangeArrow;
        mGame.cengine.scene.add(levelend);
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
        scrollOverride = false;
        if (onToggleWeaponWindow)
            onToggleWeaponWindow();
    }

    //xxx for debugging, so you can force to show the cursor
    bool scrollOverride;
    private void cmdToggleScroll(MyBox[] args, Output write) {
        scrollOverride = !scrollOverride;
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

    override bool onTestMouse(Vector2i pos) {
        return true; //actually this is the default
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

    override void onDraw(Canvas c) {
        mGame.cengine.draw(c);

        //mouse stuff at last?
        //if (mouseOverState)
        if (activeWorm)
            mCursorVisible =
                activeWorm.member.control.renderOnMouse(c, mousePos);
        else
            mCursorVisible = true;

        mGame.engine.debug_draw(c);
    }

    //don't draw the default Widget focus marker if the game is focused
    override void onDrawFocus(Canvas c) {
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
