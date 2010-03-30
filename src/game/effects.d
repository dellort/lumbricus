//effects that can be independend from the actual game
module game.effects;

import common.scene;
import framework.framework;
import game.temp : GameZOrder;
import utils.interpolate;
import utils.time;


class NukeSplatEffect : SceneObject {
    static float nukeFlash(float A)(float x) {
        if (x < A)
            return interpExponential!(6.0f)(x/A);
        else
            return interpExponential2!(4.5f)((1.0f-x)/(1.0f-A));
    }

    private {
        InterpolateFnTime!(float, nukeFlash!(0.01f)) mInterp;
    }

    this() {
        zorder = GameZOrder.Splat;
        mInterp.init(timeMsecs(3500), 0, 1.0f);
    }

    override void draw(Canvas c) {
        if (!mInterp.inProgress()) {
            removeThis();
            return;
        }
        c.drawFilledRect(c.visibleArea(),
            Color(1.0f, 1.0f, 1.0f, mInterp.value()));
    }
}
