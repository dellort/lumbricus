module game.gui.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import common.scene;
import game.clientengine;
import common.visual;
import common.common;
import game.gamepublic;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;

class PrepareDisplay : Container {
    private GuiLabel mPrepareView;
    private Time mLastTime;
    private Translator tr;
    private ClientGameEngine mEngine;

    this(ClientGameEngine engine) {
        mEngine = engine;
        tr = localeRoot.bindNamespace("gui_prepare");
        mPrepareView = new GuiLabel();
        mPrepareView.font = globals.framework.fontManager.loadFont("messages");
        mPrepareView.border = Vector2i(7, 5);

        mLastTime = timeCurrentTime();
    }

    private void active(bool active) {
        if (active) {
            if (mPrepareView.parent !is this) {
                addChild(mPrepareView);
                setChildLayout(mPrepareView, WidgetLayout.Aligned(0, -1,
                    Vector2i(0, 40)));
            }
        } else {
            mPrepareView.remove();
        }
    }

    void simulate(Time curTime, Time deltaT) {
        Time cur = timeCurrentTime();
        auto logic = mEngine.logic;
        //auto controller = mEngine ? mEngine.engine.controller : null;
        if (logic.currentRoundState() == RoundState.prepare
            && logic.getControl.getActiveTeam())
        {
            Team curTeam = logic.getControl().getActiveTeam();
            active = true;
            char[] teamName = curTeam.name;
            //little hack to show correct time
            Time pt = logic.currentPrepareTime()-timeMsecs(1);
            mPrepareView.text = tr("teamgetready", teamName,
                pt.secs >= 0 ? pt.secs+1 : 0);
        } else {
            active = false;
        }

        mLastTime = cur;
    }
}
