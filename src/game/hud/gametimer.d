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
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

class GameTimer : BoxContainer {
    private {
        GameInfo mGame;
        Label mTurnTime, mGameTime;
        bool mActive;
        Time mLastTime;
        Font[5] mFont;
        //xxx load this from somewhere
        bool mShowGameTime, mShowTurnTime;
        Color mOldBordercolor;
        TimeStatus mStatus;
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

        mTurnTime = new Label();
        mTurnTime.styles.id = "roundtime";
        mTurnTime.font = mFont[0];
        mTurnTime.border = Vector2i(7, 0);
        mTurnTime.centerX = true;

        mGameTime = new Label();
        mTurnTime.styles.id = "gametime";
        mGameTime.font = mFont[3];
        mGameTime.border = Vector2i(7, 0);
        mGameTime.centerX = true;

        minSize = toVector2i(toVector2f(mTurnTime.font.textSize("99"))*1.5f);

        mLastTime = timeCurrentTime();
        visible = false;

        hudBase.add(this, WidgetLayout.Aligned(-1, 1, Vector2i(5, 5)));
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
        char[20] turnTBuffer = void;
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
        mTurnTime.text = myformat_s(turnTBuffer, "{}",cast(int)rt_sec);
    }

    private void setGameTime(Time tRemain) {
        char[20] gameTBuffer = void;
        Time gt = tRemain - timeMsecs(1);
        int gt_sec = gt > Time.Null ? gt.secs+1 : 0;
        mGameTime.text = myformat_s(gameTBuffer, "{:d2}:{:d2}",
            gt_sec / 60, gt_sec % 60);
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
            bordercolor = mGame.allMembers[m].owner.color;
        }
        if (mStatus.showGameTime) {
            setGameTime(mStatus.gameRemaining);
        }
        if (mStatus.showTurnTime) {
            setTurnTime(mStatus.turnRemaining, mStatus.timePaused);
        }
        styles.setState("active",
            m && (m is mGame.control.getControlledMember));

        if (active != mActive) {
            mActive = active;
            visible = mActive;
        }

        assert(Color.Invalid == Color.Invalid);

        if (bordercolor != mOldBordercolor) {
            mOldBordercolor = bordercolor;
            if (bordercolor.valid()) {
                //LOL
                styles.replaceRule("/gametimer", "border-color",
                    bordercolor.fromStringRev());
            } else {
                //even more LOL
                styles.removeCustomRule("/gametimer", "border-color");
            }
        }
    }

    static this() {
        HudFactory.register!(typeof(this))("timer");
    }
}
