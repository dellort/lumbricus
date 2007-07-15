module game.gui.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import common.scene;
import game.clientengine;
import common.visual;
import common.common;
import game.gamepublic;
import gui.widget;
import utils.time;

class PrepareDisplay : Widget {
    private FontLabel mPrepareView;
    private bool mActive;
    private Time mLastTime;
    private Translator tr;
    private ClientGameEngine mEngine;

    this(ClientGameEngine engine) {
        mEngine = engine;
        tr = new Translator("gui_prepare");
        mPrepareView = new FontLabelBoxed(globals.framework.fontManager.loadFont("messages"));
        mPrepareView.border = Vector2i(7, 5);

        mLastTime = timeCurrentTime();
    }

    void simulate(Time curTime, Time deltaT) {
        Time cur = timeCurrentTime();
        //auto controller = mEngine ? mEngine.engine.controller : null;
        /*if (controller && controller.currentRoundState() == RoundState.prepare
            && controller.currentTeam())
        {
            Team curTeam = controller.currentTeam();
            if (!mActive) {
                scene.add(mPrepareView);
                mActive = true;
            }
            char[] teamName = curTeam.name;
            //little hack to show correct time
            Time pt = controller.currentPrepareTime()-timeMsecs(1);
            mPrepareView.text = tr("teamgetready", teamName, pt.secs >= 0 ? pt.secs+1 : 0);
        } else {
            if (mActive) {
                scene.remove(mPrepareView);
                mActive = false;
            }
        }*/

        mPrepareView.pos.x = size.x/2 - mPrepareView.size.x/2;
        mPrepareView.pos.y = 40;

        //animation stuff here

        mLastTime = cur;
    }

    void relayout() {
        //xxx self-managed position (someone said gui-layouter...)
        //pos.y = 40;
    }
}
