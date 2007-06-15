module gui.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import game.scene;
import game.game;
import game.visual;
import game.common;
import game.controller;
import gui.guiobject;
import utils.time;

class PrepareDisplay : GuiObject {
    private FontLabel mPrepareView;
    private Time mLastTime;
    private Translator tr;

    this() {
        tr = new Translator("gui_prepare");
        mPrepareView = new FontLabelBoxed(globals.framework.fontManager.loadFont("messages"));
        mPrepareView.border = Vector2i(7, 5);
        size = mPrepareView.size;

        mLastTime = timeCurrentTime();
    }

    public void setScene(Scene s, int z) {
        super.setScene(s, z);
        mPrepareView.setScene(s, z);
    }

    void draw(Canvas canvas) {
        Time cur = timeCurrentTime();
        if (mEngine && mEngine.controller.currentRoundState() == RoundState.prepare) {
            Team curTeam = mEngine.controller.currentTeam();
            if (curTeam) {
                mPrepareView.active = true;
                char[] teamName = curTeam.name;
                //little hack to show correct time
                Time pt = mEngine.controller.currentPrepareTime()-timeMsecs(1);
                mPrepareView.text = tr("teamgetready", teamName, pt.secs >= 0 ? pt.secs+1 : 0);
            } else {
                mPrepareView.active = false;
            }
        } else {
            mPrepareView.active = false;
        }

        size = mPrepareView.size;
        pos.x = scene.size.x/2 - size.x/2;
        mPrepareView.pos = pos;

        //animation stuff here

        mLastTime = cur;
    }

    void resize() {
        //xxx self-managed position (someone said gui-layouter...)
        pos.y = 40;
    }
}
