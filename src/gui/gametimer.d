module gui.gametimer;

import framework.framework;
import framework.font;
import game.scene;
import game.game;
import game.visual;
import game.common;
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
        if (mEngine) {
            int secs = mEngine.controller.currentRoundTime();
            mTimeView.text = str.format("%.2s", secs >= 0 ? secs : 0);
        }

        //xxx self-managed position (someone said gui-layouter...)
        pos = scene.size.Y - size.Y - Vector2i(-20,20);
        mTimeView.pos = pos;

        //animation stuff here

        mLastTime = cur;
    }
}
