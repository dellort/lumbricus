module game.hud.preparedisplay;

import framework.framework;
import framework.font;
import framework.i18n;
import game.core;
import game.controller;
import game.hud.hudbase;
import gui.container;
import gui.label;
import gui.widget;
import utils.misc;
import utils.time;

class HudPrepare : HudElementWidget {
    Time prepareRemaining;

    this(GameCore engine) {
        super(engine);
        auto w = new PrepareDisplay(engine, this);
        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 40));
        lay.border = Vector2i(7, 5);
        w.setLayout(lay);
        //hide initially
        set(w, false);
    }
}

class PrepareDisplay : Label {
    private {
        Translator tr;
        GameController mController;
        HudPrepare mStatus;
        bool mInit;
        int mLastSec;
        Team mLastTeam;
    }

    this(GameCore engine, HudPrepare link) {
        mController = engine.singleton!(GameController)();
        mStatus = link;
        tr = localeRoot.bindNamespace("gui_prepare");
        styles.addClass("preparebox");
    }

    override void simulate() {
        TeamMember m = mController.getControlledMember;
        if (!m) {
            mStatus.visible = false;
            return;
        }

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
