module game.hud.preparedisplay;

import framework.framework;
import framework.i18n;
import game.hud.teaminfo;
import game.gamepublic;
import game.gamemodes.roundbased_shared;
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
        font = gFramework.fontManager.loadFont("messages");
        border = Vector2i(7, 5);

        //prepare display is only needed for roundbased gamemode
        mEnabled = !!status();
        //hide initially
        visible = false;
    }

    //returns info-object, or null if no round based stuff is going on
    private RoundbasedStatus status() {
        return cast(RoundbasedStatus)mGame.logic.gamemodeStatus();
    }

    override void simulate() {
        if (!mEnabled)
            return;

        auto st = status();
        assert (!!st);

        auto logic = mGame.logic;
        //auto controller = mEngine ? mEngine.engine.controller : null;
        if (st.state == RoundState.prepare
            && mGame.control.getControlledMember)
        {
            Team curTeam = mGame.control.getControlledMember.team;

            //little hack to show correct time
            Time pt = st.prepareRemaining - timeMsecs(1);
            float pt_secs = pt.secs >= 0 ? pt.secsf+1 : 0;
            fontCustomColor = (cast(int)(pt_secs*2)%2 == 0)
                ? mGame.teams[curTeam].color : Color.Invalid;

            visible = true;
            char[] teamName = curTeam.name;
            text = tr("teamgetready", teamName, cast(int)pt_secs);
        } else {
            visible = false;
        }
    }
}
