module game.hud.windmeter;

import framework.config;
import framework.drawing;
import framework.surface;
import common.scene;
import game.game;
import game.teamtheme;
import game.hud.teaminfo;
import gui.renderbox;
import gui.widget;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.vector2;

class WindMeter : Widget {
    private {
        GameInfo mGame;
        //Texture mBackgroundTex;
        Surface mWindLeft, mWindRight;
        Vector2i mPosCenter;
        BoxProperties mBoxStyle;

        //pixels/sec
        float mAnimSpeed;
        int mTexStep;
        int mMaxWidth;
    }

    this(GameInfo game) {
        setVirtualFrame(false);
        mGame = game;

        ConfigNode wmNode = loadConfig("windmeter.conf");

        //mBackgroundTex = gResources.resource!(BitmapResource)
        //    ("/windmeter_back").get().createTexture();
        mWindLeft = mGame.engine.resources.get!(Surface)("windmeter_left");
        mWindRight = mGame.engine.resources.get!(Surface)("windmeter_right");

        int borderdist = wmNode.getIntValue("borderdist", 2);
        mTexStep = wmNode.getIntValue("textureStep", 8);
        mAnimSpeed = wmNode.getFloatValue("animSpeed", 40.0f);

        mMaxWidth = mWindLeft.size.x - mTexStep;
        minSize = Vector2i(2*mMaxWidth + 2*borderdist + 3/*center*/
            + 2/*round corners*/, mWindLeft.size.y + 2*borderdist);
        mPosCenter.x = minSize.x/2;
        mPosCenter.y = borderdist;

        mBoxStyle = WormLabels.textWormBorderStyle();
    }

    override protected void onDraw(Canvas canvas) {
        auto time = timeCurrentTime;
        if (mGame.engine) {
            drawBox(canvas, Vector2i(0), size, mBoxStyle);
            auto rengine = GameEngine.fromCore(mGame.engine);
            float wspeed = rengine.windSpeed;
            int anisize = clampRangeC(cast(int)(wspeed*mMaxWidth),
                -mMaxWidth,mMaxWidth);
            int texOffset = (cast(int)(time.secsf*mAnimSpeed)
                + (anisize<0?anisize:0)) % mTexStep;
            if (wspeed < 0)
                canvas.drawPart(mWindLeft,
                    Vector2i(mPosCenter.x - 1 + anisize, mPosCenter.y),
                    Vector2i(texOffset, 0),
                    Vector2i(-anisize, mWindLeft.size.y));
            else
                canvas.drawPart(mWindRight,
                    Vector2i(mPosCenter.x + 2, mPosCenter.y),
                    Vector2i(mTexStep - texOffset, 0),
                    Vector2i(anisize, mWindRight.size.y));
        }
    }
}
