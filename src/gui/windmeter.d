module gui.windmeter;

import framework.framework;
import game.common;
import game.scene;
import game.game;
import utils.time;
import utils.vector2;

class WindMeter : SceneObjectPositioned {
    private GameController mController;
    private Vector2i mSize;
    private Texture mBackgroundTex;
    private Texture mWindLeft, mWindRight;
    private float mTexOffsetf = 0;
    private Time mLastTime;
    private Vector2i mPosCenter;

    //pixels/sec
    private const cAnimSpeed = 40.0f;
    private const cTexStep = 8;

    this() {
        mSize = Vector2i(181, 17);
        mBackgroundTex = gFramework.loadImage("wind.png",Transparency.Colorkey).createTexture();
        mWindLeft = gFramework.loadImage("windl.png",Transparency.Colorkey).createTexture();
        mWindRight = gFramework.loadImage("windr.png",Transparency.Colorkey).createTexture();
        mLastTime = globals.gameTimeAnimations;
        mPosCenter = mSize/2;
    }

    void controller(GameController c) {
        mController = c;
    }

    void draw(Canvas canvas, SceneView parentView) {
        Time cur = globals.gameTimeAnimations;
        if (mController) {
            float deltaT = (cur.msecs - mLastTime.msecs)/1000.0f;
            mTexOffsetf = mTexOffsetf + cAnimSpeed*deltaT;
            canvas.draw(mBackgroundTex, pos);
            float wspeed = mController.windSpeed;
            int anisize = cast(int)(wspeed/2.0f);
            if (wspeed < 0)
                canvas.draw(mWindLeft, pos + Vector2i(mPosCenter.x - 1 + anisize, 2),
                    Vector2i((cast(int)mTexOffsetf)%cTexStep, 0), Vector2i(-anisize, mWindLeft.size.y));
            else
                canvas.draw(mWindRight, pos + Vector2i(mPosCenter.x + 2, 2),
                    Vector2i(cTexStep-(cast(int)mTexOffsetf)%cTexStep, 0), Vector2i(anisize, mWindRight.size.y));
        }
        mLastTime = cur;
    }

    Vector2i size() {
        return mSize;
    }
}
