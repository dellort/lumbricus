module game.gui.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import common.visual;
import game.clientengine;
import game.gamepublic;
import game.gui.teaminfo;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;

class GameTimer : Container {
    private {
        GameInfo mGame;
        Label mTimeView;
        bool mActive;
        Time mLastTime;
        Vector2i mInitSize;
        BoxProperties mBoxProps;
    }

    this(GameInfo game) {
        mGame = game;

        mBoxProps.borderWidth = 2;
        mTimeView = new Label();
        mTimeView.font = gFramework.fontManager.loadFont("time");
        mTimeView.border = Vector2i(7, 5);

        mTimeView.text = str.format("%.2s", 99);
        //ew!
        mInitSize = mTimeView.font.textSize(mTimeView.text);

        mLastTime = timeCurrentTime();
    }

    override void simulate() {
        bool active;
        if (mGame) {
            auto m = mGame.control.getControlledMember();
            if (m) {
                active = true;
                mBoxProps.border = mGame.allMembers[m].owner.color;
                mTimeView.borderStyle = mBoxProps;
                //little hack to show correct time
                Time rt = mGame.logic.currentRoundTime()-timeMsecs(1);;
                mTimeView.text = str.format("%.2s", rt.secs >= -1 ? rt.secs+1 : 0);
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
