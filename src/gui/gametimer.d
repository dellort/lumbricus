module gui.gametimer;

import framework.framework;
import framework.font;
import game.scene;
import game.clientengine;
import game.visual;
import game.common;
import game.controller;
import gui.guiobject;
import utils.time;

class GameTimer : GuiObject {
    private ClientGameEngine mEngine;
    private FontLabel mTimeView;
    private Time mLastTime;

    this(ClientGameEngine engine) {
        mEngine = engine;
        mTimeView = new FontLabelBoxed(globals.framework.fontManager.loadFont("time"));
        mTimeView.border = Vector2i(7, 5);
        size = mTimeView.size;

        mLastTime = timeCurrentTime();
    }

    override protected void onChangeScene(bool activeness) {
        mTimeView.setScene(scene, zorder, active);
    }

    void draw(Canvas canvas) {
        if (mEngine) {
            auto controller = mEngine.mEngine.controller;
            if (controller.currentRoundState() == RoundState.prepare
                || controller.currentRoundState() == RoundState.playing
                || controller.currentRoundState() == RoundState.cleaningUp)
            {
                mTimeView.active = true;
                //little hack to show correct time
                Time rt = controller.currentRoundTime()-timeMsecs(1);;
                mTimeView.text = str.format("%.2s", rt.secs >= -1 ? rt.secs+1 : 0);
            } else {
                mTimeView.active = false;
            }
        } else {
            mTimeView.active = false;
        }
    }

    void resize() {
        //xxx self-managed position (someone said gui-layouter...)
        pos = scene.size.Y - size.Y - Vector2i(-20,20);
        mTimeView.pos = pos;
    }
}
