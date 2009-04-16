module game.hud.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import common.scene;
import common.visual;
import game.clientengine;
import game.hud.teaminfo;
import game.gamepublic;
import game.gamemodes.roundbased_shared;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;

class PrepareDisplay : Container {
    private {
        Label mPrepareView;
        Time mLastTime;
        Translator tr;
        GameInfo mGame;
        bool mEnabled;
    }

    this(GameInfo game) {
        mGame = game;
        tr = localeRoot.bindNamespace("gui_prepare");
        mPrepareView = new Label();
        mPrepareView.styles.id = "preparebox";
        mPrepareView.font = gFramework.fontManager.loadFont("messages");
        mPrepareView.border = Vector2i(7, 5);

        mLastTime = timeCurrentTime();

        //???
        mEnabled = !!status();
    }

    //returns info-object, or null if no round based stuff is going on
    private RoundbasedStatus status() {
        return cast(RoundbasedStatus)mGame.logic.gamemodeStatus();
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

    override void simulate() {
        if (!mEnabled)
            return;

        auto st = status();
        assert (!!st);

        Time cur = timeCurrentTime();
        auto logic = mGame.logic;
        //auto controller = mEngine ? mEngine.engine.controller : null;
        if (st.state == RoundState.prepare
            && mGame.control.getControlledMember)
        {
            Team curTeam = mGame.control.getControlledMember.team;
            //set box border color
            //yyy bring this back
            //mBoxProps.border = mGame.teams[curTeam].color;
            active = true;
            char[] teamName = curTeam.name;
            //little hack to show correct time
            Time pt = st.prepareRemaining - timeMsecs(1);
            mPrepareView.text = tr("teamgetready", teamName,
                pt.secs >= 0 ? pt.secs+1 : 0);
        } else {
            active = false;
        }

        mLastTime = cur;
    }
}
