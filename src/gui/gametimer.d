module gui.gametimer;

import framework.framework;
import framework.font;
import game.scene;
import game.game;
import game.visual;
import game.common;
import game.controller;
import utils.time;

class GameTimer : SceneObjectPositioned {
    private FontLabel mTimeView;
    private Time mLastTime;
    private GameEngine mEngine;

    this() {
        mTimeView = new FontLabelBoxed(globals.framework.fontManager.loadFont("time"));
        mTimeView.border = Vector2i(7, 5);
        size = mTimeView.size;

        mLastTime = globals.gameTimeAnimations;
    }

    void engine(GameEngine c) {
        mEngine = c;
    }

    public void setScene(Scene s, int z) {
        super.setScene(s, z);
        mTimeView.setScene(s, z);
    }

    void draw(Canvas canvas, SceneView parentView) {
        Time cur = globals.gameTimeAnimations;
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

        //xxx self-managed position (someone said gui-layouter...)
        pos = scene.size.Y - size.Y - Vector2i(-20,20);
        mTimeView.pos = pos;

        //animation stuff here

        mLastTime = cur;
    }
}
