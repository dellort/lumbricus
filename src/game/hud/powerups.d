module game.hud.powerups;

import framework.framework;
import framework.font;
import game.clientengine;
import game.hud.teaminfo;
import gui.boxcontainer;
import gui.label;
import gui.renderbox;
import gui.widget;
import utils.time;
import utils.misc;
import utils.vector2;

class PowerupDisplay : BoxContainer {
    private {
        GameInfo mGame;
        ImageLabel mLblCrate, mLblDouble;
        Color mOldColor = Color.Invalid;
    }

    this(GameInfo game) {
        super(true, true, 10);
        mGame = game;
        mLblCrate = createLabel("icon_cratespy");
        mLblDouble = createLabel("icon_doubledamage");
    }

    protected ImageLabel createLabel(char[] iconRes) {
        auto ret = new ImageLabel();
        ret.styles.addClass("powerup-icon");
        ret.image = mGame.cengine.gfx.resources.get!(Surface)(iconRes);
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

        if (myTeam && isLinked) {
            //I assume the color is only used if the label is visible
            auto col = myTeam.color.color;
            if (col != mOldColor) {
                mOldColor = col;
                foreach (s; [mLblDouble, mLblCrate]) {
                    s.styles.setStyleOverrideT!(Color)("border-color", col);
                }
            }
        }
        check(mLblDouble, myTeam ? myTeam.hasDoubleDamage() : false);
        check(mLblCrate, myTeam ? myTeam.hasCrateSpy() : false);
    }
}
