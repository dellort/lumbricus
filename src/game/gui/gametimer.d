module game.gui.gametimer;

import framework.framework;
import framework.font;
import common.scene;
import game.clientengine;
import common.visual;
import common.common;
import game.gamepublic;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;

class GameTimer : Container {
    private ClientGameEngine mEngine;
    private Label mTimeView;
    private bool mActive;
    private Time mLastTime;
    private Vector2i mInitSize;

    this(ClientGameEngine engine) {
        mEngine = engine;
        mTimeView = new Label();
        mTimeView.font = globals.framework.fontManager.loadFont("time");
        mTimeView.border = Vector2i(7, 5);

        mTimeView.text = str.format("%.2s", 99);
        //ew!
        mInitSize = mTimeView.font.textSize(mTimeView.text);

        addChild(mTimeView);
        setChildLayout(mTimeView, WidgetLayout.Noexpand);

        mLastTime = timeCurrentTime();
    }

    void simulate(Time curTime, Time deltaT) {
        bool active;
        if (mEngine) {
            auto controller = mEngine.engine.logic;
            if (controller.currentRoundState() == RoundState.prepare
                || controller.currentRoundState() == RoundState.playing
                || controller.currentRoundState() == RoundState.cleaningUp)
            {
                active = true;
                //little hack to show correct time
                Time rt = controller.currentRoundTime()-timeMsecs(1);;
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
                //xxx
                //scene.add(mTimeView);
            } else {
                //scene.remove(mTimeView);
            }
        }
    }

    Vector2i layoutSizeRequest() {
        //idea: avoid resizing, give a larger area to have moar border
        return mInitSize*2;
    }
}
