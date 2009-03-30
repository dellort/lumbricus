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

class GameFrame : SimpleContainer, GameEngineCallback {
    GameInfo game;
    GameView gameView;

    private {
        MouseScroller mScroller;
        SimpleContainer mGui;

        WeaponSelWindow mWeaponSel;

        TeamWindow mTeamWindow;
        Label mReplayImg, mReplayTimer;

        MessageViewer mMessageViewer;

        Time mLastFrameTime, mRestTime;
        bool mFirstFrame = true;
        Vector2i mScrollToAtStart;
    }

    //-- GameEngineCallback
    //this sucks etc., there should be a way to register delegates to listen for
    //single events, instead of having to implement this interface in each case

    //handled in ClientGameEngine
    void damage(Vector2i pos, int radius, bool explode) {
    }

    void showMessage(LocalizedMessage msg) {
        mMessageViewer.showMessage(msg);
    }
    void weaponsChanged(Team t) {
        updateWeapons();
    }

    //-- end interface

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
        auto curtime = game.clientTime.current;
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

        mScroller.scale = Vector2f(gameView.zoomLevel, gameView.zoomLevel);

        if (game.replayRemain != Time.Null) {
            mReplayImg.visible = (timeCurrentTime().msecs/500)%2 == 0;
            mReplayTimer.visible = true;
            mReplayTimer.text = myformat("{:f1}s", game.replayRemain.secsf);
        } else {
            mReplayImg.visible = false;
            mReplayTimer.visible = false;
        }
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

        game.engine.addCallback(this);

        auto wormbinds = new KeyBindings();
        wormbinds.loadFrom(gConf.loadConfig("wormbinds").getSubNode("binds"));

        mGui = new SimpleContainer();
        //needed because I messed up input handling
        //no children of mGui can receive mouse events
        mGui.mouseEvents = false;

        mGui.add(new WindMeter(game),
            WidgetLayout.Aligned(1, 1, Vector2i(5, 5)));
        mGui.add(new GameTimer(game),
            WidgetLayout.Aligned(-1, 1, Vector2i(5, 5)));

        mGui.add(new PrepareDisplay(game));

        mMessageViewer = new MessageViewer(game);
        mGui.add(mMessageViewer);

        mTeamWindow = new TeamWindow(game);
        mGui.add(mTeamWindow);

        mReplayImg = new Label();
        //mReplayImg.image = globals.guiResources.get!(Surface)("replay_r");
        mReplayImg.text = "R";
        mReplayImg.font = gFramework.fontManager.loadFont("replay_r");
        mReplayImg.drawBorder = false;
        mReplayImg.visible = false;
        mReplayTimer = new Label();
        mReplayTimer.drawBorder = false;
        mReplayTimer.visible = false;
        mReplayTimer.font = gFramework.fontManager.loadFont("replaytime");
        auto rbox = new BoxContainer(false);
        rbox.add(mReplayImg);
        rbox.add(mReplayTimer, WidgetLayout.Aligned(0, 0));
        mGui.add(rbox, WidgetLayout.Aligned(-1, -1, Vector2i(10, 0)));

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

        WeaponHandle[] wlist = game.logic.weaponList();
        mWeaponSel.init(wlist);

        setPosition(game.cengine.worldCenter);
    }
}
