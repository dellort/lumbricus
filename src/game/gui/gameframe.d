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

import std.math;

//time for which it takes to add/remove 1 health point in the animation
const Time cTimePerHealthTick = timeMsecs(4);

class GameFrame : SimpleContainer, GameLogicPublicCallback {
    ClientGameEngine clientengine;
    GameInfo game;

    private MouseScroller mScroller;
    private SimpleContainer mGui;
    GameView gameView;

    private WeaponSelWindow mWeaponSel;

    private TeamWindow mTeamWindow;

    private MessageViewer mMessageViewer;

    private Camera mCamera;

    private Time mLastFrameTime, mRestTime;

    //xxx this be awful hack
    void gameLogicRoundTimeUpdate(Time t, bool timePaused) {
    }
    void gameLogicUpdateRoundState() {
    }
    void gameLogicWeaponListUpdated(Team team) {
        updateWeapons();
    }
    void gameShowMessage(char[] msgid, char[][] args) {
        char[] translated = localeRoot.translateWithArray(msgid, args);
        mMessageViewer.addMessage(translated);
    }

    private void updateWeapons() {
        Team t = clientengine.logic.getControl.getActiveTeam();
        if (t) {
            mWeaponSel.update(t.getWeapons());
        }
    }

    private void teamChanged() {
        updateWeapons();
    }

    private void selectWeapon(WeaponClass c) {
        clientengine.logic.getControl.weaponDraw(c);
    }

    //could be unclean: catch weapon selection shortcut before passing it down
    //to GameView (the GUI does that part)
    protected override bool onKeyEvent(KeyInfo k) {
        if (k.isDown) {
            //noone knows why it doesn't simply pass the bind, instead of k
            auto c = clientengine.logic.getControl.currentWeapon;
            if (mWeaponSel.checkNextWeaponInCategoryShortcut(k, c))
                return true;
        }
        return super.onKeyEvent(k);
    }

    //scroll to level center
    void setPosition(Vector2i pos) {
        mScroller.offset = mScroller.centeredOffset(pos);
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

        mCamera.doFrame();

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
    }

    override bool doesCover() {
        //assumption: gameView covers this widget completely, i.e. no borders
        //etc...; warning: assumption isn't true if level+gameView is smaller
        //than window; would need to check that
        return gameView.doesCover();
    }

    this(ClientGameEngine ce) {
        clientengine = ce;

        clientengine.logic.setGameLogicCallback(this);

        game = new GameInfo(clientengine);

        gDefaultLog("initializeGameGui");

        auto wormbinds = new KeyBindings();
        wormbinds.loadFrom(gFramework.loadConfig("wormbinds").getSubNode("binds"));

        mGui = new SimpleContainer();

        mGui.add(new WindMeter(clientengine),
            WidgetLayout.Aligned(1, 1, Vector2i(10, 10)));
        mGui.add(new GameTimer(clientengine),
            WidgetLayout.Aligned(-1, 1, Vector2i(5,5)));

        mGui.add(new PrepareDisplay(clientengine));

        mMessageViewer = new MessageViewer();
        mGui.add(mMessageViewer);

        mCamera = new Camera();

        gameView = new GameView(clientengine, mCamera, game);
        gameView.onTeamChange = &teamChanged;
        gameView.bindings = wormbinds;

        mScroller = new MouseScroller();
        mScroller.add(gameView);
        mScroller.zorder = -1; //don't hide the game GUI
        add(mScroller);
        add(mGui);

        mCamera.control = mScroller;

        mWeaponSel = new WeaponSelWindow();
        mWeaponSel.onSelectWeapon = &selectWeapon;

        mWeaponSel.selectionBindings = wormbinds;

        add(mWeaponSel, WidgetLayout.Aligned(1, 1, Vector2i(10, 40)));

        mTeamWindow = new TeamWindow(game);
        add(mTeamWindow);
    }
}
