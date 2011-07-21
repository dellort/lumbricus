//effects that can be independend from the actual game
module game.effects;

import common.scene;
import framework.drawing;
import game.temp;
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


//draw the red zones on the left and right edges of the level
class LevelEndDrawer : SceneObject {
    Vertex2f[4] mQuad;
    enum cIn = Color.Transparent;
    enum cOut = Color(1.0, 0, 0, 0.5);
    bool mLeft, mRight;

    this(bool left, bool right) {
        mLeft = left;
        mRight = right;
        //horizontal gradient
        mQuad[0].c = cOut;
        mQuad[1].c = cIn;
        mQuad[2].c = cIn;
        mQuad[3].c = cOut;
    }
    override void draw(Canvas canvas) {
        //relies that level area is set as client area
        //fails if level is smaller than screen
        if (canvas.features & DriverFeatures.transformedQuads) {
            if (mLeft) {
                //left side
                mQuad[0].p = Vector2f(0);
                mQuad[1].p = Vector2f(30, 0);
                mQuad[2].p = Vector2f(30, canvas.clientSize.y);
                mQuad[3].p = Vector2f(0, canvas.clientSize.y);
                canvas.drawQuad(null, mQuad);
            }
            if (mRight) {
                //right side
                mQuad[0].p = Vector2f(canvas.clientSize.x, 0);
                mQuad[1].p = Vector2f(canvas.clientSize.x - 30, 0);
                mQuad[2].p = Vector2f(canvas.clientSize.x - 30,
                    canvas.clientSize.y);
                mQuad[3].p = Vector2f(canvas.clientSize.x, canvas.clientSize.y);
                canvas.drawQuad(null, mQuad);
            }
        }
    }
}
