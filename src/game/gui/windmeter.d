module game.gui.windmeter;

import framework.framework;
import common.scene;
import common.visual;
import framework.restypes.bitmap;
import game.clientengine;
import gui.widget;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.vector2;

class WindMeter : Widget {
    private ClientGameEngine mEngine;
    private Vector2i mSize;
    //private Texture mBackgroundTex;
    private Texture mWindLeft, mWindRight;
    private float mTexOffsetf = 0;
    private Time mLastTime;
    private Vector2i mPosCenter;
    private BoxProperties mBoxStyle;

    //pixels/sec
    private float mAnimSpeed;
    private int mTexStep;
    private int mMaxWidth;
    private float mWindScale;

    this(ClientGameEngine engine) {
        mEngine = engine;

        ConfigNode wmNode = gFramework.loadConfig("windmeter");

        //mBackgroundTex = gFramework.resources.resource!(BitmapResource)
        //    ("/windmeter_back").get().createTexture();
        mWindLeft = engine.resources.get!(Surface)("windmeter_left");
        mWindRight = engine.resources.get!(Surface)("windmeter_right");

        int borderdist = wmNode.getIntValue("borderdist", 2);
        mTexStep = wmNode.getIntValue("textureStep", 8);
        mAnimSpeed = wmNode.getFloatValue("animSpeed", 40.0f);
        mWindScale = wmNode.getFloatValue("windScale", 0.5f);

        mBoxStyle.loadFrom(wmNode.getSubNode("box"));

        mMaxWidth = mWindLeft.size.x - mTexStep;
        mSize = Vector2i(2*mMaxWidth + 2*borderdist + 3/*center*/
            + 2/*round corners*/, mWindLeft.size.y + 2*borderdist);
        mPosCenter.x = mSize.x/2;
        mPosCenter.y = borderdist;

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
            //canvas.draw(mBackgroundTex, pos);
            drawBox(canvas, pos, mSize, mBoxStyle);
            float wspeed = mEngine.windSpeed;
            int anisize = clampRangeC(cast(int)(wspeed*mWindScale),
                -mMaxWidth,mMaxWidth);
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
