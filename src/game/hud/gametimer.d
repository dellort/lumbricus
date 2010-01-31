module game.hud.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import game.clientengine;
import game.hud.register;
import game.hud.teaminfo;
import game.gamemodes.shared;
import gui.container;
import gui.boxcontainer;
import gui.label;
import gui.renderbox;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.interpolate;

class GameTimer : BoxContainer {
    private {
        GameInfo mGame;
        Label mTurnTime, mGameTime;
        Font[5] mFont;
        //xxx load this from somewhere
        bool mShowGameTime, mShowTurnTime;
        Color mOldBordercolor;
        TimeStatus mStatus;
        InterpolateExp!(float) mPosInterp;
    }

    this(SimpleContainer hudBase, GameInfo game, Object link) {
        mGame = game;
        mStatus = castStrict!(TimeStatus)(link);

        styles.addClass("gametimer");

        auto list = ["time"[], "time_red", "time_grey", "time_small",
            "time_small_grey"];
        foreach (int idx, name; list) {
            mFont[idx] = gFontManager.loadFont(name);
        }

        auto lay = WidgetLayout.init;
        lay.border = Vector2i(7, 0);

        mTurnTime = new Label();
        mTurnTime.styles.addClass("roundtime");
        mTurnTime.font = mFont[0];
        mTurnTime.centerX = true;
        mTurnTime.setLayout(lay);

        mGameTime = new Label();
        mTurnTime.styles.addClass("gametime");
        mGameTime.font = mFont[3];
        mGameTime.centerX = true;
        mGameTime.setLayout(lay);

        minSize = toVector2i(toVector2f(mTurnTime.font.textSize("99"))*1.5f);

        mPosInterp.init_done(timeSecs(0.4), 0, 1);

        hudBase.add(this, WidgetLayout.Aligned(-1, 1, Vector2i(5, 5)));
    }

    private bool isVisible() {
        return mPosInterp.target == 0;
    }

    private void toggleVisible() {
        mPosInterp.revert();
    }

    void setGameTimeMode(bool showGT, bool showTT = true) {
        if ((showGT == mShowGameTime) && (showTT == mShowTurnTime))
            return;
        mShowGameTime = showGT;
        mShowTurnTime = showTT;
        clear();
        if (showTT)
            add(mTurnTime);
        if (showGT)
            add(mGameTime);
        needRelayout();
    }

    private void setTurnTime(Time tRemain, bool paused = false) {
        //little hack to show correct time
        Time rt = tRemain - timeMsecs(1);
        float rt_sec = rt.secs >= -1 ? rt.secsf+1 : 0f;

        if (paused) {
            mTurnTime.font = mFont[2];
            mGameTime.font = mFont[4];
        } else if (rt_sec < 6f) {
            //flash red/black (red when time is higher)
            mTurnTime.font = mFont[cast(int)(rt_sec*4)%2];
            mGameTime.font = mFont[3];
        } else {
            mTurnTime.font = mFont[0];
            mGameTime.font = mFont[3];
        }

        mTurnTime.setTextFmt(false, "{}", cast(int)rt_sec);
    }

    private void setGameTime(Time tRemain) {
        Time gt = tRemain - timeMsecs(1);
        int gt_sec = gt > Time.Null ? gt.secs+1 : 0;
        mGameTime.setTextFmt(false, "{:d2}:{:d2}", gt_sec / 60, gt_sec % 60);
    }

    override void simulate() {
        Color bordercolor = Color(0.7f);

        setGameTimeMode(mStatus.showGameTime, mStatus.showTurnTime);
        bool active = mStatus.showGameTime || mStatus.showTurnTime;

        auto m = mGame.control.getControlledMember;
        foreach (t; mGame.logic.teams) {
            if (m)
                break;
            m = t.current;
        }
        if (m) {
            bordercolor = m.team.color.color;
        }
        if (mStatus.showGameTime) {
            setGameTime(mStatus.gameRemaining);
        }
        if (mStatus.showTurnTime) {
            setTurnTime(mStatus.turnRemaining, mStatus.timePaused);
        }
        styles.setState("active",
            m && (m is mGame.control.getControlledMember));

        if (active != isVisible) {
            toggleVisible();
        }

        assert(Color.Invalid == Color.Invalid);

        if (bordercolor != mOldBordercolor) {
            mOldBordercolor = bordercolor;
            if (bordercolor.valid()) {
                styles.setStyleOverrideT!(Color)("border-color", bordercolor);
            } else {
                styles.clearStyleOverride("border-color");
            }
        }

        int edge = findParentBorderDistance(0, 1, false);
        setAddToPos(Vector2i(0, cast(int)(mPosInterp.value*edge)));
    }

    static this() {
        HudFactory.register!(typeof(this))("timer");
    }
}
