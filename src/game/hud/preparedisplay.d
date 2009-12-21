module game.hud.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
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
    }

    this(SimpleContainer hudBase, GameInfo game, Object link) {
        mGame = game;
        mStatus = castStrict!(PrepareStatus)(link);
        tr = localeRoot.bindNamespace("gui_prepare");
        styles.id = "preparebox";
        font = gFontManager.loadFont("messages");
        border = Vector2i(7, 5);

        //hide initially
        visible = false;

        hudBase.add(this, WidgetLayout.Aligned(0, -1, Vector2i(0, 40)));
    }

    override void simulate() {
        auto logic = mGame.logic;
        auto m = mGame.control.getControlledMember;
        visible = mStatus.visible && m;
        if (visible) {
            Team curTeam = m.team;

            //little hack to show correct time
            Time pt = mStatus.prepareRemaining - timeMsecs(1);
            float pt_secs = pt.secs >= 0 ? pt.secsf+1 : 0;
            auto t = mGame.teams[curTeam];
            font = (cast(int)(pt_secs*2)%2 == 0)
                ? t.font_flash : t.font;

            char[] teamName = curTeam.name;
            text = tr("teamgetready", teamName, cast(int)pt_secs);
        }
    }

    static this() {
        HudFactory.register!(typeof(this))("prepare");
    }
}
