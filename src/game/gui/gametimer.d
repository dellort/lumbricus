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

import str = stdx.string;

class GameTimer : Container {
    private {
        GameInfo mGame;
        Label mTimeView;
        bool mActive, mEnabled;
        Time mLastTime;
        Vector2i mInitSize;
        BoxProperties mBoxProps;
    }

    this(GameInfo game) {
        mGame = game;

        mTimeView = new Label();
        mTimeView.font = gFramework.fontManager.loadFont("time");
        mTimeView.border = Vector2i(7, 5);

        mTimeView.text = myformat("%.2s", 99);
        //ew!
        mInitSize = mTimeView.font.textSize(mTimeView.text);

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
                    - timeMsecs(1);;
                mTimeView.text = myformat("%.2s", rt.secs >= -1 ? rt.secs+1 : 0);
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
                setChildLayout(mTimeView, WidgetLayout.Noexpand);
            } else {
                removeChild(mTimeView);
            }
        }
    }

    Vector2i layoutSizeRequest() {
        //idea: avoid resizing, give a larger area to have moar border
        return mInitSize*2;
    }
}
