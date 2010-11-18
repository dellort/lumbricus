module game.hud.gameview;

import common.globalconsole;
import framework.font;
import framework.config;
import framework.drawing;
import framework.event;
import framework.surface;
import framework.globalsettings;
import framework.i18n;
import framework.main;
import framework.commandline;
import framework.keybindings;
import utils.timesource;
import common.animation;
import common.scene;
import game.game;
import game.input;
import game.sequence;
import game.sky;
import game.teamtheme;
import game.temp : GameZOrder;
import game.controller;
import game.hud.camera;
import game.weapon.weapon;
import game.hud.teaminfo;
import game.water;
import game.worm; //for a hack
import game.gfxset;  //for waterColor
import gui.global;
import gui.renderbox;
import gui.rendertext;
import gui.widget;
import gui.container;
import gui.label;
import gui.mousescroller;
import gui.tablecontainer;
import physics.all;
import utils.color;
import utils.configfile;
import utils.rect2;
import utils.strparser;
import utils.time;
import utils.timesource;
import utils.math;
import utils.misc;
import utils.perf;
import utils.vector2;
import utils.interpolate;

import str = utils.string;
import math = tango.math.Math;

import utils.random : rngShared;

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

private {
    SettingVar!(int) gTeamLabels, gDetailLevel;
}

const cTeamLabelCount = 4;
const cDetailLevelCount = 7;

static this() {
    gTeamLabels = gTeamLabels.Add("game.teamlabels", 2);
    settingMakeIntRange(gTeamLabels.setting, 0, cTeamLabelCount-1);
    gDetailLevel = gDetailLevel.Add("game.detaillevel", 0);
    settingMakeIntRange(gDetailLevel.setting, 0, cDetailLevelCount-1);
}

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
    int lastKnownHealth;  //what we know from the last updateHealth()

    this(GameView a_owner, TeamMember m) {
        owner = a_owner;
        auto ts = owner.mGame.engine.interpolateTime;
        moveLabels.currentTimeDg = &ts.current;
        moveHealth.currentTimeDg = &ts.current;
        moveWeaponIcon.currentTimeDg = &ts.current;
        member = m;
        lastKnownHealth = member.healthTarget(false);
        TeamTheme theme = team.color;
        wormTeam = theme.textCreate();
        wormTeam.setLiteral(team.name());
        wormName = theme.textCreate();
        wormName.setLiteral(member.name());
        wormPoints = theme.textCreate();
        healthHint = theme.textCreate();
        weaponIcon = new BorderImage;
        weaponIcon.border = WormLabels.textWormBorderStyle();

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
                int lost = lastKnownHealth - member.health();
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
            Time t = owner.mGame.engine.interpolateTime.current;
            ani.draw(canvas, addThing(ani.bounds.size, true), p, t);
        }


        bool isActiveWorm = this is owner.activeWorm;

        //whether labels should move up or down
        //initiate movement into this direction if not yet
        bool doMoveDown = true;

        if (isActiveWorm) {
            auto currentTime = owner.mGame.engine.gameTime.current;
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
        WeaponClass wicon = member.control.weaponForIcon();

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
        bool weapon_icon_visible = !!wicon;

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
            if (!icon)
                icon = gGuiResources.get!(Surface)("missing");
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
            auto t = owner.mGame.engine.interpolateTime.current;
            bool flash_on = (member.active && cast(int)(t.secsf*2)%2 == 0);
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
            auto diff = member.healthTarget(false) - lastKnownHealth;
            //compare target and realHealth to see if health is
            //really changing (diff can still be != 0 if not)
            if (diff < 0 && lastKnownHealth != lastHealthHintTarget) {
                //start (only for damages, not upgrades => "< 0")
                moveHealth.init(cHealthHintTime, 0,
                    cHealthHintDistance);
                healthHint.setTextFmt(false, "{}", -diff);
                //this is to avoid restarting the label animation several times
                //  when counting down takes longer than to display the full
                //  health damage hint animation
                lastHealthHintTarget = lastKnownHealth;
            }
        }
        if (moveHealth.inProgress()) {
            pos = health_hint_pos;
            pos.y -= moveHealth.value();
            canvas.pushState();
            canvas.setBlend(
                Color(1, 1, 1, math.sqrt(1.0f - moveHealth.fvalue())));
            addLabel(healthHint);
            canvas.popState();
        }
        //for damage label (health hint); using member.currentHealth()
        //  introduces one-frame bugs where hp is "lost"
        lastKnownHealth = member.healthTarget(false);
    }
} //ViewMember

enum MoveLabelEffect {
    move,   //straight
    bubble, //like in water
}

class DrownLabel : SceneObject {
    private {
        TimeSourcePublic mTS;
        MoveLabelEffect mEffect;
        FormattedText mTxt;
        Time mStart;
        float mSpeed; //pixels/second
        Vector2i mFrom, mTo;
        Color mWaterBlendColor;
        const cWaterBlendFactor = 0.6;
    }

    //member inf drowned at pos (pos is on the ground)
    this(GameInfo a_game, TeamMember m, int lost, Vector2i pos) {
        mTxt = m.team.color.textCreate();
        mTxt.setTextFmt(false, "{}", lost);
        mFrom = pos;
        auto rengine = GameEngine.fromCore(a_game.engine);
        mTo = Vector2i(pos.x, rengine.waterOffset);
        mTS = a_game.engine.interpolateTime;
        mStart = mTS.current;
        mEffect = MoveLabelEffect.bubble;
        mSpeed = cDrownLabelSpeed;

        GfxSet gfx = a_game.engine.singleton!(GfxSet)();
        mWaterBlendColor = gfx.waterColor * cWaterBlendFactor
            + Color(1) * (1.0f - cWaterBlendFactor);
    }

    override void draw(Canvas c) {
        auto now = mTS.current;

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

        //tint slightly with water color
        c.setBlend(mWaterBlendColor);
        mTxt.draw(c, curpos);
    }
}

//GameView is everything which is scrolled
//it displays the game directly and also handles input directly
//also draws worm labels
//and cooks coffee
class GameView : Widget {
    //these are all evil hacks and should go away
    //it's getting ridiculous arrgh
    void delegate() onTeamChange;
    void delegate() onKeyHelp;
    void delegate() onToggleWeaponWindow, onToggleScroll;
    void delegate() onToggleChat, onToggleScript;
    void delegate(char[] category) onSelectCategory;

    //what a stupid type name
    struct GUITeamMemberSettings {
        bool showTeam = false;
        bool showName = true;
        bool showPoints = true;
    }

    private {
        GameInfo mGame;
        Container mGuiFrame;

        Scene mLabels;

        //not synchronous to game, never paused, no ideas why we have this
        TimeSource mClientTime;

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

        MoveStateXY mCameraMovement;

        //key binding identifier to game engine command (wormbinds map_commands)
        char[][char[]] mKeybindToCommand;
        //wormbinds.conf/map_commands
        ConfigNode mCommandMap;

        //key currently held down (used for proper key-up notification)
        BindKey[] mKeyDown;
        //additional buffer for mKeyDown to simplify code
        BindKey[] mKeyDownBuffer;

        //for worm-name drawing
        ViewMember[TeamMember] mEngineMemberToOurs;

        GUITeamMemberSettings mTeamGUISettings;
        int mCycleLabels = 2;

        InputGroup mInput;

        ViewMember activeWorm;
        ViewMember lastActiveWorm;

        bool mCursorVisible = true;

        GameWater mGameWater;
        GameSky mGameSky;

        uint mDetailLevel;

        //when shaking, the current offset
        Vector2i mShakeOffset;
        //time after which a new shake offset is computed (to make shaking
        //  framerate independent), in ms
        const cShakeIntervalMs = 50;
        Time mLastShake;

        PerfTimer mGameDrawTime;
    } //private

    void addSubWidget(Widget w) {
        addChild(w);
    }

    private void updateTeamLabels() {
        uint x = gTeamLabels.get();
        auto t = x % cTeamLabelCount;
        mTeamGUISettings.showPoints = t >= 1;
        mTeamGUISettings.showName = t >= 2;
        mTeamGUISettings.showTeam = t >= 3;
    }

    private void updateDetailLevel() {
        uint level = gDetailLevel.get();
        //the higher the less detail (wtf), wraps around if set too high
        level = level % cDetailLevelCount;
        mDetailLevel = level;
        bool clouds = true, skyDebris = true, skyBackdrop = true, skyTex = true,
             water = true, particles = true;
        if (level >= 1) skyDebris = false;
        if (level >= 2) skyBackdrop = false;
        if (level >= 3) skyTex = false;
        if (level >= 4) clouds = false;
        if (level >= 5) water = false;
        if (level >= 6) particles = false;
        //relies that setters don't do anything if the same value is set
        mGameWater.simpleMode = !water;
        mGameSky.enableClouds = clouds;
        mGameSky.enableDebris = skyDebris;
        mGameSky.enableSkyBackdrop = skyBackdrop;
        mGameSky.enableSkyTex = skyTex;
        mGame.engine.particleWorld.enabled = particles;
    }

    private void doSim() {
        mClientTime.update();

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

        add_graphics();

        mClientTime = new TimeSource("clienttime");
        mCamera = new Camera(mClientTime);

        //load the teams and also the members
        foreach (Team t; game.controller.teams) {
            foreach (TeamMember m; t.members) {
                ViewMember vt = new ViewMember(this, m);
                mEngineMemberToOurs[m] = vt;
            }
        }

        //all keybinding stuff

        ConfigNode wormbindings = loadConfig("wormbinds.conf");
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

        //local input (not handled in the "server" game engine)
        //NOTE: some parts of the program uses the commandline stuff for
        //  keybinds (like gametask.d or toplevel.d), and this stuff here uses
        //  InputGroup. the separation doesn't really make sense; reasons why
        //  they are different are some "subtleties", random decisions, and
        //  legacy crap:
        //  - global key shortcuts vs. those which should only react to input
        //    directly going to GameView
        //  - InputGroup acting as simpler replacement for the commandline stuff
        //  - too lazy to rewrite it in a way that makes sense
        //  - durr hurr
        //also, some stuff should be in gameframe.d (or elsewhere)
        mInput = new InputGroup();
        mInput.add("category", &inpCategory);
        mInput.add("zoom", &inpZoom);
        mInput.add("cameradisable", &inpCameraDisable);
        mInput.add("move_camera", &inpMoveCamera);
        mInput.add("keybindings_help", &inpShowKeybinds);
        mInput.add("toggle_weaponwindow", &inpToggleWeaponWnd);
        mInput.add("toggle_scroll", &inpToggleScroll);
        mInput.add("toggle_chat", &inpToggleChat);
        mInput.add("toggle_script", &inpToggleScript);
        mInput.add("cmd", &inpCmd);

        //newTimer resets time every second to calculate average times
        //mGameDrawTime = globals.newTimer("game_draw_time");
        mGameDrawTime = new PerfTimer(true);

        mGame.engine.getRenderTime = &do_getRenderTime;

        updateTeamLabels();
        updateDetailLevel();
    }

    private Time do_getRenderTime() {
        return mGameDrawTime.time();
    }

    private void add_graphics() {
        mGame.engine.scene.add(mLabels);

        //xxx
        mGameWater = new GameWater(mGame.engine);
        mGameSky = new GameSky(mGame.engine);
    }

    //this is an atrocious hack for executing global commands only if the key
    //  shortcut input went to the game; otherwise the key shortcuts for
    //  teamlabels ("delete") would be globally catched, and you couldn't use
    //  them e.g. in a text edit field
    private bool inpCmd(char[] cmd) {
        executeGlobalCommand(cmd);
        return true;
    }

    private bool inpCategory(char[] catname) {
        if (onSelectCategory)
            onSelectCategory(catname);
        return true;
    }

    private bool inpZoom(char[] cmd) {
        bool isDown = tryFromStrDef(cmd, false);
        mZoomChange = isDown?-1:1;
        return true;
    }

    private bool inpCameraDisable(char[] cmd) {
        enableCamera = !tryFromStrDef(cmd, enableCamera);
        //gLog.warn("set camera enable: {}", enableCamera);
        return true;
    }

    private bool inpShowKeybinds() {
        if (onKeyHelp)
            onKeyHelp();
        return true;
    }

    private bool inpToggleWeaponWnd() {
        if (onToggleWeaponWindow)
            onToggleWeaponWindow();
        return true;
    }

    //xxx for debugging, so you can force to show the cursor
    private bool inpToggleScroll() {
        if (onToggleScroll)
            onToggleScroll();
        return true;
    }
    private bool inpToggleChat() {
        //xxx this is stupid, rethink handling of ingame commands
        if (onToggleChat)
            onToggleChat();
        return true;
    }
    private bool inpToggleScript() {
        //xxx this is stupid, rethink handling of ingame commands
        if (onToggleScript)
            onToggleScript();
        return true;
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
            if (cat.name == "invisible")
                continue;
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
                bind.text = translateBind(this.bindings, id);
                bind.styles.addClass("keybind_help_bind");
                table.addRow();
                table.add(caption, 0, table.height-1);
                table.add(bind, 1, table.height-1);
            }
        }
        return table;
    }

    private bool inpMoveCamera(char[] cmd) {
        mCameraMovement.handleCommand(cmd);
        mCamera.setAutoScroll(mCameraMovement.direction);
        return true;
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
        return mGame.engine.resources.get!(WeaponClass)(name, true);
    }

    override bool onKeyDown(KeyInfo ki) {
        //if repeated, consider as handled, but throw away anyway
        if (ki.isRepeated)
            return true;

        bool handled = doKeyEvent(ki);

        if (handled) {
            //xxx only some key bindings (as handled in doKeyEvent) actually
            //  want a key-up event; in this case one wouldn't need this
            BindKey key = BindKey.FromKeyInfo(ki);
            mKeyDown ~= key;
        }

        return handled;
    }
    override void onKeyUp(KeyInfo ki) {
        //doKeyEvent(ki);
        //explicitly check key state in case - this is needed because the key-up
        //  events can be inconsistent to the key bindings (e.g. consider the
        //  sequence left-down, ctrl-down, left-up, ctrl-up: we receive left-up
        //  with the ctrl modifier set, which doesn't match the normal left-key
        //  binding => code for left-up is never executed)
        //xxx maybe move this into simulate() (polling) and simplify the GUI
        //  code (possibly move all this into widget.d?)
        mKeyDownBuffer.length = 0;
        foreach (BindKey k; mKeyDown) {
            //still pressed?
            if (gFramework.getKeyState(k.code)
                && gFramework.getModifierSetState(k.mods))
            {
                //entry survives
                mKeyDownBuffer ~= k;
            } else {
                //synthesize key-up event
                KeyInfo nki;
                nki.code = k.code;
                nki.mods = k.mods;
                nki.isDown = false;
                doKeyEvent(nki);
            }
        }
        swap(mKeyDown, mKeyDownBuffer);
    }

    private bool doKeyEvent(KeyInfo ki) {
        BindKey key = BindKey.FromKeyInfo(ki);
        char[] bind = bindings.findBinding(key);

        //xxx is there a reason not to use the command directly?
        if (auto pcmd = bind in mKeybindToCommand) {
            bind = processBinding(*pcmd, ki);
        }

        return doInput(bind);
    }

    override void onMouseMove(MouseInfo mouse) {
        //if in use, this causes excessive traffic in network mode
        //but code that uses this is debug code anyway, and it doesn't matter
        KeyInfo ki;
        ki.isDown = true;
        ki.mods = gFramework.getModifierSet();
        char[40] buffer = void;
        doInput(processBinding("mouse_move %mx %my", ki, buffer));
    }

    //takes a binding string from KeyBindings and replaces params
    //  %d -> true if key was pressed, false if released
    //  %mx, %my -> mouse position
    //also, will not trigger an up event for commands without %d param
    //buffer can be memory of any size that will be used to reduce heap allocs
    private char[] processBinding(char[] bind, KeyInfo ki, char[] buffer = null)
    {
        bool isUp = !ki.isDown;
        //no up/down parameter, and key was released -> no event
        if (str.find(bind, "%d") < 0 && isUp)
            return null;
        auto txt = StrBuffer(buffer);
        txt.sink(bind);
        str.buffer_replace_fmt(txt, "%d", "{}", !isUp);
        str.buffer_replace_fmt(txt, "%mx", "{}", mousePos.x);
        str.buffer_replace_fmt(txt, "%my", "{}", mousePos.y);
        return txt.get;
    }

    private bool doInput(char[] s) {
        if (!s.length)
            return false;

        bool handled = false;

        //prefer local input handler
        if (!handled && mInput.checkCommand("", s))
            handled = mInput.execCommand("", s);

        if (!handled && mGame.control.checkCommand(s)) {
            mGame.control.execCommand(s);
            handled = true;
        }

        return handled;
    }

    override bool onTestMouse(Vector2i pos) {
        return true; //actually this is the default
    }

    float zoomLevel() {
        return mCurZoom;
    }

    override void simulate() {
        updateTeamLabels();
        updateDetailLevel();

        float zc = mZoomChange*(cZoomMax-cZoomMin)/cZoomTime.secsf
            * mGame.engine.interpolateTime.difference.secsf;
        mCurZoom = clampRangeC(mCurZoom+zc, cZoomMin, cZoomMax);
        super.simulate();
        sim_camera();
        doSim();

        //not sure if the following shouldn't be handled in onDraw()?

        //visualize earthquake
        Time curtime = mGame.engine.interpolateTime.current;
        if ((curtime - mLastShake).msecs >= cShakeIntervalMs) {
            GameEngine rengine = GameEngine.fromCore(mGame.engine);

            //100f? I don't know what it means, but it works (kind of)
            auto shake = Vector2f.fromPolar(1.0f,
                rngShared.nextDouble()*math.PI*2)
                * (rengine.earthQuakeStrength()/100f);
            mShakeOffset = toVector2i(shake);

            mLastShake = curtime;
        }

        mGameWater.simulate();
        mGameSky.simulate();
    }

    override void onDraw(Canvas c) {
        mGameDrawTime.start();
        c.pushState();
        c.translate(mShakeOffset);
        mGame.engine.scene.draw(c);
        c.popState();
        mGameDrawTime.stop();

        //mouse stuff at last?
        bool old_cursor_visible = mCursorVisible;
        if (activeWorm)
            mCursorVisible =
                activeWorm.member.control.renderOnMouse(c, mousePos);
        else
            mCursorVisible = true;
        //camera gets active again (e.g. after clicking to fire airstrike)
        //  => don't jump back immediately
        if (!old_cursor_visible && mCursorVisible)
            mCamera.reset();

        mGame.engine.debug_draw(c);

        /+ forgotten debugging code
        auto p = toVector2f(mousePos);
        float r = 10;
        c.drawCircle(toVector2i(p), cast(int)r, Color(1,0,0));
        GeomContact gcontact;
        bool hit = mGame.engine.physicWorld.collideGeometry(p, r, gcontact);
        if (hit) {
            auto dir = gcontact.normal * gcontact.depth;
            c.drawLine(toVector2i(p), toVector2i(p+dir), Color(1,0,0));
            c.drawCircle(toVector2i(p+dir), cast(int)r, Color(0,1,0));
        }
        +/
    }

    //don't draw the default Widget focus marker if the game is focused
    override void onDrawFocus(Canvas c) {
    }

    override MouseCursor mouseCursor() {
        return mCursorVisible ? MouseCursor.Standard : MouseCursor.None;
    }

    override bool doesCover() {
        //check if the sky drawer is in a mode where everything is overpainted
        //(depends from detail level)
        return !mGameSky.enableSkyTex;
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
        Time now = mCamera.ts.current;

        Sequence cur;
        TeamMember member = mGame.control.getControlledMember();
        if (member) {
            cur = member.control.controlledSprite.graphic;
        }

        //hack to disable camera when the user has control over the mouse, e.g.
        //  clicking for airstrike target (if this "heuristic" fails, we might
        //  need to add an explicit option to Controllable for camera control)
        if (!mCursorVisible)
            cur = null;

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

        mGame.engine.particleWorld.setViewArea(mCamera.visibleArea);
    }
}
