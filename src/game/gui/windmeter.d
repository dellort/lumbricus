module game.gui.windmeter;

import framework.framework;
import common.common;
import common.scene;
import common.bmpresource;
import game.clientengine;
import gui.widget;
import utils.configfile;
import utils.time;
import utils.vector2;

class WindMeter : Widget {
    private ClientGameEngine mEngine;
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

    this(ClientGameEngine engine) {
        mEngine = engine;

        ConfigNode wmNode = globals.loadConfig("windmeter");
        globals.resources.loadResources(wmNode);

        mBackgroundTex = globals.resources.resource!(BitmapResource)
            ("/windmeter_back").get().createTexture();
        mSize = mBackgroundTex.size;
        mWindLeft = globals.resources.resource!(BitmapResource)
            ("/windmeter_left").get().createTexture();
        mWindRight = globals.resources.resource!(BitmapResource)
            ("/windmeter_right").get().createTexture();

        ConfigNode ctNode = wmNode.getSubNode("center");
        mPosCenter.x = ctNode.getIntValue("x",mSize.x/2);
        mPosCenter.y = ctNode.getIntValue("y",0);

        mTexStep = wmNode.getIntValue("textureStep",8);
        mAnimSpeed = wmNode.getFloatValue("animSpeed",40.0f);
        mWindScale = wmNode.getFloatValue("windScale",0.5f);

        mLastTime =  timeCurrentTime();
    }

    protected void onDraw(Canvas canvas) {
        auto pos = Vector2i(0);
        auto time = timeCurrentTime;
        //mLastTime first isn't initialized, but the resulting random value
        //  doesn't really matter (note you also must be able to deal with
        //  unexpected pauses)
        auto deltaT = time - mLastTime;
        mLastTime = time;
        mTexOffsetf = mTexOffsetf + mAnimSpeed*(deltaT.secsf);
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

    override Vector2i layoutSizeRequest() {
        return mSize;
    }
}
