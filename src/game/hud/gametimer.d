module game.hud.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import common.visual;
import game.clientengine;
import game.gamepublic;
import game.hud.teaminfo;
import game.gamemodes.roundbased_shared;
import gui.container;
import gui.boxcontainer;
import gui.label;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

import str = stdx.string;
import tango.io.Stdout;

class GameTimer : Container {
    private {
        GameInfo mGame;
        BoxContainer mLabelBox;
        Label mRoundTime, mGameTime;
        bool mActive, mEnabled;
        Time mLastTime;
        Vector2i mMinSize;
        BoxProperties mBoxProps;
        Font[5] mFont;
        //xxx load this from somewhere
        bool mShowGameTime = true;
    }

    this(GameInfo game) {
        mGame = game;

        mLabelBox = new BoxContainer(false, false, 0);
        mLabelBox.drawBorder = true;

        mFont[0] = gFramework.fontManager.loadFont("time");
        mFont[1] = gFramework.fontManager.loadFont("time_red");
        mFont[2] = gFramework.fontManager.loadFont("time_grey");
        mFont[3] = gFramework.fontManager.loadFont("time_small");
        mFont[4] = gFramework.fontManager.loadFont("time_small_grey");

        mRoundTime = new Label();
        mRoundTime.font = mFont[0];
        mRoundTime.border = Vector2i(7, 0);
        mRoundTime.centerX = true;
        mRoundTime.drawBorder = false;

        mGameTime = new Label();
        mGameTime.font = mFont[3];
        mGameTime.border = Vector2i(7, 0);
        mGameTime.centerX = true;
        mGameTime.drawBorder = false;

        mMinSize = toVector2i(toVector2f(mRoundTime.font.textSize("99"))*1.7f);
        //mMinSize.y = 100; //cast(int)(mMinSize.x*0.9f);

        showGameTime(mShowGameTime);

        mBoxProps.back = Color(0, 0, 0, 0.7);

        mLastTime = timeCurrentTime();

        mEnabled = game.logic.gamemode == cRoundbased;
    }

    void showGameTime(bool show) {
        mShowGameTime = show;
        mLabelBox.clear();
        mLabelBox.add(mRoundTime);
        if (show)
            mLabelBox.add(mGameTime);
        needRelayout();
    }

    override void simulate() {
        if (!mEnabled)
            return;

        bool active;
        if (mGame) {
            int state = mGame.logic.currentGameState;
            Team[] t = mGame.logic.getActiveTeams;
            TeamMember m;
            if (t.length > 0)
                m = t[0].getActiveMember;
            if ((state == RoundState.prepare || state == RoundState.playing)
                && m)
            {
                active = true;
                mBoxProps.border = mGame.allMembers[m].owner.color;
                if (m == mGame.control.getControlledMember) {
                    //broad border if it's the own worm
                    mBoxProps.borderWidth = 2;
                } else {
                    mBoxProps.borderWidth = 1;
                }
                mLabelBox.borderStyle = mBoxProps;
                auto st = mGame.logic.gamemodeStatus().unbox!(RoundbasedStatus);
                //little hack to show correct time
                Time rt = st.roundRemaining - timeMsecs(1);
                float rt_sec = rt.secs >= -1 ? rt.secsf+1 : 0f;
                if (st.timePaused) {
                    mRoundTime.font = mFont[2];
                    mGameTime.font = mFont[4];
                } else if (rt_sec < 6f) {
                    //flash red/black (red when time is lower)
                    mRoundTime.font = mFont[cast(int)(rt_sec*2+1)%2];
                    mGameTime.font = mFont[3];
                } else {
                    mRoundTime.font = mFont[0];
                    mGameTime.font = mFont[3];
                }
                mRoundTime.text = myformat("{}", cast(int)rt_sec);
                Time gt = st.gameRemaining - timeMsecs(1);
                int gt_sec = gt > Time.Null ? gt.secs+1 : 0;
                mGameTime.text = myformat("{:d2}:{:d2}", gt_sec / 60,
                    gt_sec % 60);
            } else {
                active = false;
            }
        } else {
            active = false;
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
    }

    Vector2i layoutSizeRequest() {
        //idea: avoid resizing, give a larger area to have moar border
        Vector2i ret = mMinSize;
        Vector2i l = super.layoutSizeRequest();
        ret.y = max(ret.y, l.y);
        return ret;
    }
}
