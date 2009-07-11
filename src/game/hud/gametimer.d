module game.hud.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import common.visual;
import game.clientengine;
import game.gamepublic;
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
        Label mRoundTime, mGameTime;
        bool mActive, mEnabled;
        Time mLastTime;
        Vector2i mMinSize;
        Font[5] mFont;
        //xxx load this from somewhere
        bool mShowGameTime = true;
        char[20] mRndTBuffer, mGameTBuffer;
        Color mOldBordercolor;
    }

    this(GameInfo game) {
        mGame = game;

        //styles.addClass("gametimer");

        mLabelBox = new BoxContainer();
        mLabelBox.styles.addClass("gametimer");

        mFont[0] = gFramework.fontManager.loadFont("time");
        mFont[1] = gFramework.fontManager.loadFont("time_red");
        mFont[2] = gFramework.fontManager.loadFont("time_grey");
        mFont[3] = gFramework.fontManager.loadFont("time_small");
        mFont[4] = gFramework.fontManager.loadFont("time_small_grey");

        mRoundTime = new Label();
        mRoundTime.styles.id = "roundtime";
        mRoundTime.font = mFont[0];
        mRoundTime.border = Vector2i(7, 0);
        mRoundTime.centerX = true;

        mGameTime = new Label();
        mRoundTime.styles.id = "gametime";
        mGameTime.font = mFont[3];
        mGameTime.border = Vector2i(7, 0);
        mGameTime.centerX = true;

        mMinSize = toVector2i(toVector2f(mRoundTime.font.textSize("99"))*1.7f);
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
            mLabelBox.add(mRoundTime);
        if (showGT)
            mLabelBox.add(mGameTime);
        needRelayout();
    }

    private void setGameTime(Time tRemain) {
        Time gt = tRemain - timeMsecs(1);
        int gt_sec = gt > Time.Null ? gt.secs+1 : 0;
        mGameTime.text = myformat_s(mGameTBuffer, "{:d2}:{:d2}",
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
            foreach (t; mGame.logic.getTeams) {
                m = t.getActiveMember;
                if (m)
                    break;
            }
            if ((state == TurnState.prepare || state == TurnState.playing)
                && m)
            {
                active = true;
                bordercolor = mGame.allMembers[m].owner.color;
                mLabelBox.styles.setState("active",
                    m == mGame.control.getControlledMember);
                //little hack to show correct time
                Time rt = st.roundRemaining - timeMsecs(1);
                float rt_sec = rt.secs >= -1 ? rt.secsf+1 : 0f;
                if (st.timePaused) {
                    mRoundTime.font = mFont[2];
                    mGameTime.font = mFont[4];
                } else if (rt_sec < 6f) {
                    //flash red/black (red when time is higher)
                    mRoundTime.font = mFont[cast(int)(rt_sec*4)%2];
                    mGameTime.font = mFont[3];
                } else {
                    mRoundTime.font = mFont[0];
                    mGameTime.font = mFont[3];
                }
                mRoundTime.text = myformat_s(mRndTBuffer, "{}",cast(int)rt_sec);
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
            active = !mGame.logic.gameEnded();
            setGameTime(stRT.gameRemaining);
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
