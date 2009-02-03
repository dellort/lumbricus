module game.gui.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import common.visual;
import game.clientengine;
import game.gamepublic;
import game.gui.teaminfo;
import game.gamemodes.roundbased_shared;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

import str = stdx.string;

class GameTimer : Container {
    private {
        GameInfo mGame;
        Label mTimeView;
        bool mActive, mEnabled;
        Time mLastTime;
        Vector2i mMinSize;
        BoxProperties mBoxProps;
        Font[2] mFont;
    }

    this(GameInfo game) {
        mGame = game;

        mTimeView = new Label();
        mFont[0] = gFramework.fontManager.loadFont("time");
        mFont[1] = gFramework.fontManager.loadFont("time_red");
        mTimeView.font = mFont[0];
        mTimeView.border = Vector2i(7, 5);
        mTimeView.centerX = true;

        mBoxProps.back = Color(0, 0, 0, 0.7);

        mMinSize = toVector2i(toVector2f(mTimeView.font.textSize("99"))*1.7);

        mLastTime = timeCurrentTime();

        mEnabled = game.logic.gamemode == cRoundbased;
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
                mTimeView.borderStyle = mBoxProps;
                auto st = mGame.logic.gamemodeStatus;
                //little hack to show correct time
                Time rt = st.unbox!(RoundbasedStatus).roundRemaining
                    - timeMsecs(1);
                float rt_sec = rt.secs >= -1 ? rt.secsf+1 : 0f;
                if (rt_sec < 6f) {
                    //flash red/black (red when time is lower)
                    mTimeView.font = mFont[cast(int)(rt_sec*2+1)%2];
                } else {
                    mTimeView.font = mFont[0];
                }
                mTimeView.text = myformat("{}", cast(int)rt_sec);
                //needRelayout();
            } else {
                active = false;
            }
        } else {
            active = false;
        }

        if (active != mActive) {
            mActive = active;
            if (mActive) {
                addChild(mTimeView);
                setChildLayout(mTimeView, WidgetLayout.Expand(true));
            } else {
                removeChild(mTimeView);
            }
        }
    }

    Vector2i layoutSizeRequest() {
        //idea: avoid resizing, give a larger area to have moar border
        return mMinSize;
    }
}
