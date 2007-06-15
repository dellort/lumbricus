module gui.gametimer;

import framework.framework;
import framework.font;
import game.scene;
import game.game;
import game.visual;
import game.common;
import game.controller;
import gui.guiobject;
import utils.time;

class GameTimer : GuiObject {
    private FontLabel mTimeView;
    private Time mLastTime;

    this() {
        mTimeView = new FontLabelBoxed(globals.framework.fontManager.loadFont("time"));
        mTimeView.border = Vector2i(7, 5);
        size = mTimeView.size;

        mLastTime = timeCurrentTime();
    }

    public void setScene(Scene s, int z) {
        super.setScene(s, z);
        mTimeView.setScene(s, z);
    }

    void draw(Canvas canvas) {
        Time cur = timeCurrentTime();
        if (mEngine && mEngine.controller.currentRoundState() == RoundState.prepare
            || mEngine.controller.currentRoundState() == RoundState.playing
            || mEngine.controller.currentRoundState() == RoundState.cleaningUp)
        {
            mTimeView.active = true;
            //little hack to show correct time
            Time rt = mEngine.controller.currentRoundTime()-timeMsecs(1);;
            mTimeView.text = str.format("%.2s", rt.secs >= -1 ? rt.secs+1 : 0);
        } else {
            mTimeView.active = false;
        }

        //animation stuff here

        mLastTime = cur;
    }

    void resize() {
        //xxx self-managed position (someone said gui-layouter...)
        pos = scene.size.Y - size.Y - Vector2i(-20,20);
        mTimeView.pos = pos;
    }
}
