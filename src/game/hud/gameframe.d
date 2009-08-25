module game.hud.gameframe;

import common.common;
import common.scene;
import common.visual;
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
import game.clientengine;
import game.gamepublic;
import game.game;
import game.weapon.weapon;
//import levelgen.level;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.log;

import tango.math.Math;

//time for which it takes to add/remove 1 health point in the animation
const Time cTimePerHealthTick = timeMsecs(4);

class GameFrame : SimpleContainer {
    GameInfo game;
    GameView gameView;

    private {
        MouseScroller mScroller;
        SimpleContainer mGui;

        WeaponSelWindow mWeaponSel;

        TeamWindow mTeamWindow;

        Time mLastFrameTime, mRestTime;
        bool mFirstFrame = true;
        Vector2i mScrollToAtStart;
    }

    //xxx: parameter bla seems to be a relict...
    private void updateWeapons(Team bla) {
        TeamMember t = game.control.getControlledMember();
        mWeaponSel.update(t ? t.team.weapons : null);
    }

    private void teamChanged() {
        updateWeapons(null);
    }

    private void selectWeapon(WeaponClass c) {
        game.control.executeCommand("weapon "~c.name);
    }

    private void selectCategory(char[] category) {
        auto m = game.control.getControlledMember();
        mWeaponSel.checkNextWeaponInCategoryShortcut(category,
            m?m.currentWeapon():null);
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

    //if you have an event, which shall occur all duration times, return the
    //number of events which fit in t and return the rest time in t (divmod)
    static int removeNTimes(ref Time t, Time duration) {
        int r = t/duration;
        t -= duration*r;
        return r;
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

        //take care of counting down the health value
        mRestTime += delta;
        int change = removeNTimes(mRestTime, cTimePerHealthTick);
        assert(change >= 0);
        bool finished = true;
        foreach (TeamMemberInfo tmi; game.allMembers) {
            int diff = tmi.realHealth() - tmi.currentHealth;
            if (diff != 0) {
                finished = false;
                int c = min(abs(diff), change);
                tmi.currentHealth += (diff < 0) ? -c : c;
            }
        }
        //only do the rest (like animated sorting) when all was counted down
        mTeamWindow.update(finished);

        mScroller.scale = Vector2f(gameView.zoomLevel, gameView.zoomLevel);
    }

    override bool doesCover() {
        //assumption: gameView covers this widget completely, i.e. no borders
        //etc...; warning: assumption isn't true if level+gameView is smaller
        //than window; would need to check that
        return gameView.doesCover();
    }

    this(GameInfo g) {
        game = g;

        gDefaultLog("initializeGameGui");

        auto wormbinds = new KeyBindings();
        wormbinds.loadFrom(loadConfig("wormbinds").getSubNode("binds"));

        mGui = new SimpleContainer();
        //needed because I messed up input handling
        //no children of mGui can receive mouse events
        mGui.mouseEvents = false;

        //xxx ehrm, lol... config file?
        mGui.add(new WindMeter(game),
            WidgetLayout.Aligned(1, 1, Vector2i(5, 5)));
        mGui.add(new GameTimer(game),
            WidgetLayout.Aligned(-1, 1, Vector2i(5, 5)));
        mGui.add(new PrepareDisplay(game),
            WidgetLayout.Aligned(0, -1, Vector2i(0, 40)));
        mGui.add(new PowerupDisplay(game),
            WidgetLayout.Aligned(1, -1, Vector2i(5, 20)));
        mGui.add(new MessageViewer(game),
            WidgetLayout.Aligned(0, -1, Vector2i(0, 5)));
        mGui.add(new ReplayTimer(game),
            WidgetLayout.Aligned(-1, -1, Vector2i(10, 0)));

        mTeamWindow = new TeamWindow(game);
        mGui.add(mTeamWindow);

        gameView = new GameView(game);
        gameView.onTeamChange = &teamChanged;
        gameView.onSelectCategory = &selectCategory;
        gameView.bindings = wormbinds;

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

        mWeaponSel.selectionBindings = wormbinds;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(5, 40)));

        WeaponClass[] wlist = game.engine.gfx.weaponList();
        mWeaponSel.init(game.engine, wlist);

        setPosition(game.engine.level.worldCenter);

        auto cb = game.engine.callbacks();
        cb.weaponsChanged ~= &updateWeapons;
    }
}
