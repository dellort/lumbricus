module game.hud.preparedisplay;

import framework.font;
import framework.i18n;
import game.core;
import game.controller;
import game.hud.hudbase;
import game.hud.teaminfo;
import gui.container;
import gui.label;
import gui.widget;
import utils.misc;
import utils.time;
import utils.vector2;

import std.conv;

class HudPrepare : HudElementWidget {
    Time prepareRemaining;

    this(GameCore engine) {
        super(engine);
        auto w = new PrepareDisplay(engine, this);
        auto lay = WidgetLayout.Aligned(0, -1, Vector2i(0, 200));
        lay.border = Vector2i(7, 5);
        w.setLayout(lay);
        //hide initially
        set(w, false);
    }
}

class PrepareDisplay : Label {
    private {
        Translator tr;
        GameCore mEngine;
        GameInfo mGame;
        HudPrepare mStatus;
        bool mInit;
        int mLastSec;
        Team mLastTeam;
        Font mFontTeam, mFontFlash;
    }

    this(GameCore engine, HudPrepare link) {
        mEngine = engine;
        mStatus = link;
        tr = localeRoot.bindNamespace("gui_prepare");
        styles.addClass("preparebox");
    }

    override void simulate() {
        if (!mGame) {
            mGame = mEngine.singleton!(GameInfo)();
        }
        TeamMember m;
        if (mGame)
            m = mGame.control.getControlledMember();
        if (!m) {
            mStatus.visible = false;
            return;
        }

        Team curTeam = m.team;

        //little hack to show correct time
        Time pt = mStatus.prepareRemaining - timeMsecs(1);
        float pt_secs = pt.secs >= 0 ? pt.secsf+1 : 0;
        int secs = cast(int)pt_secs;

        if (mLastTeam !is curTeam || mLastSec != secs) {
            //cache fonts
            auto props = font.properties;
            props.fore_color = curTeam.theme.color;
            mFontTeam = gFontManager.create(props);
            props = font.properties;
            props.fore_color = curTeam.theme.font_flash.properties.fore_color;
            mFontFlash = gFontManager.create(props);

            text = tr("teamgetready", curTeam.name, to!(string)(secs));
        }

        bool flash = (cast(int)(pt_secs*2)%2 == 0);
        font = flash ? mFontFlash : mFontTeam;

        mLastTeam = curTeam;
        mLastSec = secs;
    }
}
