module game.gui.gameframe;

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
import gui.messageviewer;
import gui.mousescroller;
import game.gui.camera;
import game.gui.loadingscreen;
import game.gui.gameteams;
import game.gui.gametimer;
import game.gui.gameview;
import game.gui.windmeter;
import game.gui.teaminfo;
import game.gui.preparedisplay;
import game.gui.weaponsel;
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
    ClientGameEngine clientengine;
    GameInfo game;
    GameView gameView;

    private {
        MouseScroller mScroller;
        SimpleContainer mGui;

        WeaponSelWindow mWeaponSel;

        TeamWindow mTeamWindow;

        MessageViewer mMessageViewer;

        Time mLastFrameTime, mRestTime;
        bool mFirstFrame = true;
        Vector2i mScrollToAtStart;

        int mMsgChangeCounter, mWeaponChangeCounter;
        Translator mLocaleMsg;
    }

    void showMessage(char[] msgid, char[][] args, uint rnd) {
        char[] translated = mLocaleMsg.translateWithArray(msgid, args, rnd);
        mMessageViewer.addMessage(translated);
    }

    private void updateWeapons() {
        TeamMember t = game.control.getControlledMember();
        mWeaponSel.update(t ? t.team.getWeapons() : null);
    }

    private void teamChanged() {
        updateWeapons();
    }

    private void selectWeapon(WeaponHandle c) {
        game.control.executeCommand("weapon "~c.name);
    }

    private void selectCategory(char[] category) {
        auto m = game.control.getControlledMember();
        mWeaponSel.checkNextWeaponInCategoryShortcut(category,
            m?m.getCurrentWeapon():null);
    }

    //scroll to level center
    void setPosition(Vector2i pos) {
        if (mFirstFrame) {
            //cannot scroll yet because gui layouting is not done
            mScrollToAtStart = pos;
        } else {
            mScroller.offset = mScroller.centeredOffset(pos);
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

    override protected void simulate() {
        auto curtime = globals.gameTimeAnimations.current;
        if (mLastFrameTime == Time.init)
            mLastFrameTime = curtime;
        auto delta = curtime - mLastFrameTime;
        mLastFrameTime = curtime;

        //some hack
        if (mFirstFrame) {
            mFirstFrame = false;
            //scroll to level center
            setPosition(mScrollToAtStart);
        }

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

        int c = game.logic.getMessageChangeCounter();
        if (c != mMsgChangeCounter) {
            mMsgChangeCounter = c;
            char[] id;
            char[][] args;
            uint rnd;
            game.logic.getLastMessage(id, args, rnd);
            showMessage(id, args, rnd);
        }

        c = game.logic.getWeaponListChangeCounter();
        if (c != mWeaponChangeCounter) {
            mWeaponChangeCounter = c;
            updateWeapons();
        }

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

        clientengine = game.cengine;
        gDefaultLog("initializeGameGui");

        auto wormbinds = new KeyBindings();
        wormbinds.loadFrom(gFramework.loadConfig("wormbinds").getSubNode("binds"));

        mGui = new SimpleContainer();
        //needed because I messed up input handling
        //no children of mGui can receive mouse events
        mGui.mouseEvents = false;

        mGui.add(new WindMeter(clientengine),
            WidgetLayout.Aligned(1, 1, Vector2i(5, 5)));
        mGui.add(new GameTimer(game),
            WidgetLayout.Aligned(-1, 1, Vector2i(5, 5)));

        mGui.add(new PrepareDisplay(game));

        mMessageViewer = new MessageViewer();
        mGui.add(mMessageViewer);

        gameView = new GameView(game);
        gameView.onTeamChange = &teamChanged;
        gameView.onSelectCategory = &selectCategory;
        gameView.bindings = wormbinds;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        mScroller.zorder = -1; //don't hide the game GUI
        add(mScroller);
        add(mGui);

        gameView.camera.control = mScroller;

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        mWeaponSel.selectionBindings = wormbinds;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(5, 40)));

        mTeamWindow = new TeamWindow(game);
        add(mTeamWindow);

        WeaponHandle[] wlist = game.logic.weaponList();
        mWeaponSel.init(wlist);

        mLocaleMsg = Translator.ByNamespace("game_msg");

        setPosition(clientengine.worldCenter);
    }
}
