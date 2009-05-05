module game.hud.powerups;

import framework.framework;
import framework.font;
import game.clientengine;
import game.gamepublic;
import game.hud.teaminfo;
import gui.boxcontainer;
import gui.label;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

class PowerupDisplay : BoxContainer {
    private {
        GameInfo mGame;
        Label mLblCrate, mLblDouble;
    }

    this(GameInfo game) {
        super(true, true, 10);
        mGame = game;
        mLblCrate = createLabel("icon_cratespy");
        mLblDouble = createLabel("icon_doubledamage");
    }

    protected Label createLabel(char[] iconRes) {
        auto ret = new Label();
        ret.styles.addClass("powerup-icon");
        ret.image = mGame.cengine.gfx.resources.get!(Surface)(iconRes);
        ret.text = "";
        return ret;
    }

    override void simulate() {
        auto m = mGame.control.getControlledMember;
        Team myTeam;
        if (m)
            myTeam = m.team;

        void check(Widget w, bool vis) {
            if (vis && w.parent is null)
                add(w);
            else if (!vis && w.parent is this)
                removeChild(w);
        }

        if (myTeam) {
            mLblDouble.borderCustomColor = myTeam.color.color;
            mLblCrate.borderCustomColor = myTeam.color.color;
        }
        check(mLblDouble, myTeam ? myTeam.hasDoubleDamage() : false);
        check(mLblCrate, myTeam ? myTeam.hasCrateSpy() : false);
    }
}
