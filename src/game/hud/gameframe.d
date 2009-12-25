module game.hud.gameframe;

import common.common;
import common.toplevel;
import common.scene;
import framework.framework;
import framework.event;
import framework.i18n;
import gui.container;
import gui.label;
import gui.tablecontainer;
import gui.widget;
import gui.mousescroller;
import gui.boxcontainer;
import game.hud.camera;
import game.hud.gameteams;
import game.hud.gametimer;
import game.hud.gameview;
import game.hud.windmeter;
import game.hud.teaminfo;
import game.hud.preparedisplay;
import game.hud.weaponsel;
import game.hud.messageviewer;
import game.hud.powerups;
import game.hud.replaytimer;
import game.hud.network;
import game.hud.register;
import game.clientengine;
import game.game;
import game.weapon.weapon;
import game.weapon.types;
//import levelgen.level;
import utils.interpolate;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.log;

import tango.math.Math;


class GameFrame : SimpleContainer {
    GameInfo game;
    GameView gameView;

    private {
        MouseScroller mScroller;
        SimpleContainer mGui;

        WeaponSelWindow mWeaponSel;
        //movement of mWeaponSel for blending in/out
        //InterpolateLinear!(float) mWeaponInterp;
        InterpolateExp!(float) mWeaponInterp;

        TeamWindow mTeamWindow;
        Label mPauseLabel;

        Time mLastFrameTime;
        bool mFirstFrame = true;
        Vector2i mScrollToAtStart;

        //if non-null, this dialog is modal and blocks other game input
        Widget mModalDialog;
    }

    private void updateWeapons(WeaponSet bla) {
        TeamMember t = game.control.getControlledMember();
        //don't change anything if another team's weapon set was changed
        if (t && t.team.weapons !is bla)
            return;
        mWeaponSel.update(t ? t.team.weapons : null);
    }

    private void teamChanged() {
        TeamMember t = game.control.getControlledMember();
        mWeaponSel.update(t ? t.team.weapons : null);
        if (!t && isWeaponWindowVisible())
            mWeaponInterp.revert();
    }

    private void selectWeapon(WeaponClass c) {
        //xxx not really correct, the "weapon" call could fail in the engine
        //    better: callback onWeaponSelect
        //when a point weapon is selected, hide the weapon window
        mWeaponInterp.setParams(0, 1.0f);
        game.control.executeCommand("weapon "~c.name);
    }

    private void selectCategory(char[] category) {
        auto m = game.control.getControlledMember();
        mWeaponSel.checkNextWeaponInCategoryShortcut(category,
            m?m.control.currentWeapon():null);
    }

    //scroll to level center
    void setPosition(Vector2i pos, bool reset = true) {
        if (mFirstFrame) {
            //cannot scroll yet because gui layouting is not done
            mScrollToAtStart = pos;
        } else {
            mScroller.offset = mScroller.centeredOffset(pos);
            //this call makes sure the camera stays at the new position
            //  for some time instead of just jumping back to the locked object
            if (reset)
                gameView.resetCamera;
        }
    }
    Vector2i getPosition() {
        return mScroller.uncenteredOffset(mScroller.offset);
    }

    override void internalSimulate() {
        //some hack (needs to be executed before GameView's simulate() call)
        if (mFirstFrame) {
            mFirstFrame = false;
            //scroll to level center
            setPosition(mScrollToAtStart, false);
        }
        super.internalSimulate();
    }

    override protected void simulate() {
        auto curtime = game.clientTime.current;
        if (mLastFrameTime == Time.init)
            mLastFrameTime = curtime;
        auto delta = curtime - mLastFrameTime;
        mLastFrameTime = curtime;

        bool finished = true;
        foreach (Team t; game.engine.controller.teams) {
            foreach (TeamMember tm; t.getMembers) {
                if (tm.currentHealth != tm.healthTarget())
                    finished = false;
            }
        }
        //only do the rest (like animated sorting) when all was counted down
        mTeamWindow.update(finished);

        mScroller.scale = Vector2f(gameView.zoomLevel, gameView.zoomLevel);

        int mode = 0;
        if (!hudNeedMouseInput()) {
            mode = 1;
            if (auto am = game.control.getControlledMember()) {
                //mouse follow when the weapon requires clicking, and
                //the weapon window is hidden
                bool shouldFollow = am.control.pointMode != PointMode.none
                    && !isWeaponWindowVisible();
                if (shouldFollow) {
                    mode = 2;
                }
            }
        }
        switch (mode) {
            case 1:
                //direct scrolling
                mScroller.mouseScrolling = true;
                break;
            case 2:
                //mouse follow (i.e. pushing the borders)
                if (!mScroller.mouseFollow) {
                    mScroller.startMouseFollow(Vector2i(150));
                }
                break;
            default:
                //no scrolling, normal mouse cursor
                mScroller.mouseScrolling = false;
                if (mScroller.mouseFollow) {
                    mScroller.stopMouseFollow();
                }
        }

        int wsel_edge = mWeaponSel.findParentBorderDistance(1, 0, false);
        mWeaponSel.setAddToPos(
            Vector2i(cast(int)(mWeaponInterp.value*wsel_edge), 0));
        mWeaponSel.visible = 1.0f-mWeaponInterp.value > float.epsilon;

        //unpaused if any child has focus (normally GameView)
        game.shell.pauseBlock(!subFocused(), this);
        game.shell.pauseBlock(!gFramework.appFocused, gFramework);

        mPauseLabel.visible = game.shell.paused;
    }

    override bool doesCover() {
        //assumption: gameView covers this widget completely, i.e. no borders
        //etc...; warning: assumption isn't true if level+gameView is smaller
        //than window; would need to check that
        return gameView.doesCover();
    }

    private class ModalNotice : SimpleContainer {
        this(Widget client) {
            focusable = true;
            isClickable = true;
            client.setLayout(WidgetLayout.Noexpand());
            addChild(client);
        }

        void lock() {
            claimFocus();
            if (!captureEnable(true, true, false)) {
                remove();
                return;
            }
            game.shell.pauseBlock(true, this);
        }

        override void onKeyEvent(KeyInfo info) {
            //filter against releasing 'h'
            if (info.isUp() || info.isPress())
                return;
            this.outer.mModalDialog = null;
            remove();
            game.shell.pauseBlock(false, this);
        }
    }

    //show current (game) key bindings
    private void keyHelp() {
        auto dlg = new ModalNotice(gameView.createKeybindingsHelp());
        add(dlg);
        mModalDialog = dlg;
        //mScroller.mouseScrolling = false; //protect against random fuckup
        dlg.lock();
    }

    private void toggleWeaponWindow() {
        if (game.control.getControlledMember())
            mWeaponInterp.revert();
    }
    private bool isWeaponWindowVisible() {
        return mWeaponInterp.target == 0;
    }
    //return true if any hud element (other than the game) requires clicking
    private bool hudNeedMouseInput() {
        //currently just the weapon window; maybe others will be added later
        //  (e.g. pause window)
        return isWeaponWindowVisible() || gameView.scrollOverride
            || gTopLevel.consoleVisible() || game.shell.paused();
    }

    this(GameInfo g) {
        game = g;

        gDefaultLog("initializeGameGui");

        mGui = new SimpleContainer();
        //needed because I messed up input handling
        //no children of mGui can receive mouse events
        mGui.mouseEvents = false;

        //xxx ehrm, lol... config file?
        mGui.add(new WindMeter(game),
            WidgetLayout.Aligned(1, 1, Vector2i(5, 5)));
        mGui.add(new PowerupDisplay(game),
            WidgetLayout.Aligned(1, -1, Vector2i(5, 20)));
        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 5));
        lay.border = Vector2i(5, 1);
        mGui.add(new MessageViewer(game), lay);
        mGui.add(new ReplayTimer(game),
            WidgetLayout.Aligned(-1, -1, Vector2i(10, 0)));
        //hud elements requested by gamemode
        //[id : StatusObject]
        auto hudReqs = game.logic.gamemode.getHudRequests();
        foreach (id, link; hudReqs) {
            HudFactory.instantiate(id, mGui, game, link);
        }

        mTeamWindow = new TeamWindow(game);
        mGui.add(mTeamWindow);

        gameView = new GameView(game);
        gameView.onTeamChange = &teamChanged;
        gameView.onSelectCategory = &selectCategory;
        gameView.onKeyHelp = &keyHelp;
        gameView.onToggleWeaponWindow = &toggleWeaponWindow;

        mScroller = new MouseScroller();
        //changed after r845, was WidgetLayout.Aligned(0, -1)
        mScroller.add(gameView, WidgetLayout());
        mScroller.zorder = -1; //don't hide the game GUI
        add(mScroller);
        add(mGui);
        if (game.connection) {
            auto n = new NetworkHud(game);
            //network error screen covers all hud elements
            n.zorder = 10;
            add(n);
        }

        gameView.camera.control = mScroller;

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        mWeaponSel.selectionBindings = gameView.bindings;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(5, 40)));

        WeaponClass[] wlist = game.engine.gfx.weaponList();
        mWeaponSel.init(game.engine, wlist);

        mWeaponInterp.init_done(timeSecs(0.4), 0, 1);

        mPauseLabel = new Label;
        mPauseLabel.textMarkup = "\\t(gamehud.paused)";
        mPauseLabel.centerX = true;
        mPauseLabel.styles.id = "gamepauselabel";
        mPauseLabel.visible = false;
        add(mPauseLabel, WidgetLayout.Noexpand());

        setPosition(game.engine.level.worldCenter);

        auto cb = game.engine.callbacks();
        cb.weaponsChanged ~= &updateWeapons;
    }
}
