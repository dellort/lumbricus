module gui.windmeter;

import framework.framework;
import game.common;
import game.scene;
import game.game;
import gui.guiobject;
import utils.configfile;
import utils.time;
import utils.vector2;

class WindMeter : GuiObject {
    private Vector2i mSize;
    private Texture mBackgroundTex;
    private Texture mWindLeft, mWindRight;
    private float mTexOffsetf = 0;
    private Time mLastTime;
    private Vector2i mPosCenter;

    //pixels/sec
    private float mAnimSpeed;
    private int mTexStep;
    private float mWindScale;

    this() {
        ConfigNode wmNode = globals.loadConfig("windmeter");
        ConfigNode imgNode = wmNode.getSubNode("images");
        mBackgroundTex = gFramework.loadImage(imgNode.getStringValue("back"),Transparency.Colorkey).createTexture();
        mSize = mBackgroundTex.size;
        mWindLeft = gFramework.loadImage(imgNode.getStringValue("left"),Transparency.Colorkey).createTexture();
        mWindRight = gFramework.loadImage(imgNode.getStringValue("right"),Transparency.Colorkey).createTexture();

        ConfigNode ctNode = wmNode.getSubNode("center");
        mPosCenter.x = ctNode.getIntValue("x",mSize.x/2);
        mPosCenter.y = ctNode.getIntValue("y",0);

        mTexStep = wmNode.getIntValue("textureStep",8);
        mAnimSpeed = wmNode.getFloatValue("animSpeed",40.0f);
        mWindScale = wmNode.getFloatValue("windScale",0.5f);

        mLastTime =  timeCurrentTime();
    }

    void simulate(float deltaT) {
        mTexOffsetf = mTexOffsetf + mAnimSpeed*deltaT;
    }

    void draw(Canvas canvas) {
        if (mEngine) {
            canvas.draw(mBackgroundTex, pos);
            float wspeed = mEngine.windSpeed;
            int anisize = cast(int)(wspeed*mWindScale);
            if (wspeed < 0)
                canvas.draw(mWindLeft, pos + Vector2i(mPosCenter.x - 1 + anisize, mPosCenter.y),
                    Vector2i((cast(int)mTexOffsetf)%mTexStep, 0), Vector2i(-anisize, mWindLeft.size.y));
            else
                canvas.draw(mWindRight, pos + Vector2i(mPosCenter.x + 2, mPosCenter.y),
                    Vector2i(mTexStep-(cast(int)mTexOffsetf)%mTexStep, 0), Vector2i(anisize, mWindRight.size.y));
        }
    }

    Vector2i size() {
        return mSize;
    }

    void resize() {
        pos = scene.size - size - Vector2i(5,5);
    }
}
