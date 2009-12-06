module game.hud.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import common.visual;
import game.clientengine;
import game.hud.teaminfo;
import game.gamemodes.turnbased_shared;
import gui.container;
import gui.boxcontainer;
import gui.label;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

class GameTimer : Container {
    private {
        GameInfo mGame;
        BoxContainer mLabelBox;
        Label mTurnTime, mGameTime;
        bool mActive, mEnabled;
        Time mLastTime;
        Vector2i mMinSize;
        Font[5] mFont;
        //xxx load this from somewhere
        bool mShowGameTime = true;
        Color mOldBordercolor;
        bool mGameEndingCache;
    }

    this(GameInfo game) {
        mGame = game;

        //styles.addClass("gametimer");

        mLabelBox = new BoxContainer();
        mLabelBox.styles.addClass("gametimer");

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

        mMinSize = toVector2i(toVector2f(mTurnTime.font.textSize("99"))*1.7f);
        //mMinSize.y = 100; //cast(int)(mMinSize.x*0.9f);

        setGameTimeMode(mShowGameTime || !!statusRT(), !statusRT());

        mLastTime = timeCurrentTime();

        //???
        mEnabled = !!status() || !!statusRT();
    }

    //returns info-object, or null if no turn based stuff is going on
    //slight code duplication with preparedisplay.d
    private TurnbasedStatus status() {
        return cast(TurnbasedStatus)mGame.logic.gamemodeStatus();
    }

    private RealtimeStatus statusRT() {
        return cast(RealtimeStatus)mGame.logic.gamemodeStatus();
    }

    void setGameTimeMode(bool showGT, bool showRT = true) {
        mShowGameTime = showGT;
        mLabelBox.clear();
        if (showRT)
            mLabelBox.add(mTurnTime);
        if (showGT)
            mLabelBox.add(mGameTime);
        needRelayout();
    }

    private void setTurnTime(Time tRemain, bool paused = false) {
        static char[20] turnTBuffer;
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
        static char[20] gameTBuffer;
        Time gt = tRemain - timeMsecs(1);
        int gt_sec = gt > Time.Null ? gt.secs+1 : 0;
        mGameTime.text = myformat_s(gameTBuffer, "{:d2}:{:d2}",
            gt_sec / 60, gt_sec % 60);
    }

    override void simulate() {
        if (!mEnabled)
            return;

        auto st = status();
        auto stRT = statusRT();

        Color bordercolor = Color.Invalid;

        bool active;
        if (st) {
            int state = st.state;
            TeamMember m;
            foreach (t; mGame.logic.teams) {
                m = t.current;
                if (m)
                    break;
            }
            if ((state == TurnState.prepare || state == TurnState.playing
                || state == TurnState.inTurnCleanup) && m)
            {
                active = true;
                bordercolor = mGame.allMembers[m].owner.color;
                mLabelBox.styles.setState("active",
                    m is mGame.control.getControlledMember);
                setTurnTime(st.turnRemaining, st.timePaused);
                setGameTime(st.gameRemaining);
            } else {
                active = false;
            }
        } else if (stRT) {
            auto m = mGame.control.getControlledMember;
            if (m)
                bordercolor = mGame.allMembers[m].owner.color;
            else
                bordercolor = Color(0.7f);
            mLabelBox.styles.setState("active", !!m);
            //game running, and not in "happy jumping worms" phase
            active = !mGame.logic.gameEnded() && (!stRT.gameEnding || m);
            if (stRT.gameEnding) {
                //game is over, just the winner is still retreating
                setTurnTime(stRT.retreatRemaining);
                if (stRT.gameEnding != mGameEndingCache) {
                    mGameEndingCache = stRT.gameEnding;
                    //hide total time, show turn time
                    setGameTimeMode(false, true);
                }
            } else {
                setGameTime(stRT.gameRemaining);
            }
        }

        if (active != mActive) {
            mActive = active;
            if (mActive) {
                addChild(mLabelBox);
                setChildLayout(mLabelBox, WidgetLayout());
            } else {
                removeChild(mLabelBox);
            }
        }

        assert(Color.Invalid == Color.Invalid);

        if (bordercolor != mOldBordercolor) {
            mOldBordercolor = bordercolor;
            if (bordercolor.valid()) {
                //LOL
                mLabelBox.styles.replaceRule("/gametimer", "border-color",
                    bordercolor.fromStringRev());
            } else {
                //even more LOL
                mLabelBox.styles.removeCustomRule("/gametimer", "border-color");
            }
        }
    }

    Vector2i layoutSizeRequest() {
        //idea: avoid resizing, give a larger area to have moar border
        Vector2i ret = mMinSize;
        Vector2i l = super.layoutSizeRequest();
        ret.y = max(ret.y, l.y);
        return ret;
    }
}
