module game.hud.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import game.hud.teaminfo;
import game.gamemodes.turnbased_shared;
import gui.container;
import gui.label;
import gui.widget;
import utils.time;

class PrepareDisplay : Label {
    private {
        Translator tr;
        GameInfo mGame;
        bool mEnabled;
    }

    this(GameInfo game) {
        mGame = game;
        tr = localeRoot.bindNamespace("gui_prepare");
        styles.id = "preparebox";
        font = gFontManager.loadFont("messages");
        border = Vector2i(7, 5);

        //prepare display is only needed for turnbased gamemode
        mEnabled = !!status();
        //hide initially
        visible = false;
    }

    //returns info-object, or null if no turn based stuff is going on
    private TurnbasedStatus status() {
        return cast(TurnbasedStatus)mGame.logic.gamemodeStatus();
    }

    override void simulate() {
        if (!mEnabled)
            return;

        auto st = status();
        assert (!!st);

        auto logic = mGame.logic;
        //auto controller = mEngine ? mEngine.engine.controller : null;
        if (st.state == TurnState.prepare
            && mGame.control.getControlledMember)
        {
            Team curTeam = mGame.control.getControlledMember.team;

            //little hack to show correct time
            Time pt = st.prepareRemaining - timeMsecs(1);
            float pt_secs = pt.secs >= 0 ? pt.secsf+1 : 0;
            auto t = mGame.teams[curTeam];
            font = (cast(int)(pt_secs*2)%2 == 0)
                ? t.font_flash : t.font;

            visible = true;
            char[] teamName = curTeam.name;
            text = tr("teamgetready", teamName, cast(int)pt_secs);
        } else {
            visible = false;
        }
    }
}
