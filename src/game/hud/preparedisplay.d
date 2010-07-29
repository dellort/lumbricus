module game.hud.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import game.controller;
import game.hud.register;
import game.hud.teaminfo;
import game.gamemodes.shared;
import gui.container;
import gui.label;
import gui.widget;
import utils.misc;
import utils.time;

class PrepareDisplay : Label {
    private {
        Translator tr;
        GameInfo mGame;
        PrepareStatus mStatus;
        bool mInit;
        int mLastSec;
        Team mLastTeam;
    }

    this(SimpleContainer hudBase, GameInfo game, Object link) {
        mGame = game;
        mStatus = castStrict!(PrepareStatus)(link);
        tr = localeRoot.bindNamespace("gui_prepare");
        styles.addClass("preparebox");

        //hide initially
        visible = false;

        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 40));
        lay.border = Vector2i(7, 5);
        hudBase.add(this, lay);
    }

    override void simulate() {
        auto m = mGame.control.getControlledMember;
        visible = mStatus.visible && m;
        if (visible) {
            Team curTeam = m.team;

            //little hack to show correct time
            Time pt = mStatus.prepareRemaining - timeMsecs(1);
            float pt_secs = pt.secs >= 0 ? pt.secsf+1 : 0;
            font = (cast(int)(pt_secs*2)%2 == 0)
                ? curTeam.color.font_flash : curTeam.color.font;
            int secs = cast(int)pt_secs;

            if (mLastTeam !is curTeam || mLastSec != secs)
                text = tr("teamgetready", curTeam.name, secs);
            mLastTeam = curTeam;
            mLastSec = secs;
        }
    }

    static this() {
        HudFactory.register!(typeof(this))("prepare");
    }
}
