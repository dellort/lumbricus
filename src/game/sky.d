module game.sky;

import common.animation;
import common.scene;
import framework.framework;
import game.core;
import game.game;
import game.gfxset;
import game.temp : GameZOrder;
import game.levelgen.level : EnvironmentTheme;
import utils.configfile;
import utils.misc;
import utils.random;
import utils.time;
import utils.timesource;
import utils.vector2;

class SkyDrawer : SceneObject {
    private GameSky mParent;
    private Color mSkyColor;
    private Texture mSkyTex;
    private Texture mSkyBackdrop;
    private Color[3] mGradient;

    this(GameSky parent, EnvironmentTheme theme) {
        mParent = parent;
        mSkyColor = theme.skyColor;
        mSkyTex = theme.skyGradient;
        mSkyBackdrop = theme.skyBackdrop;
        mGradient[0] = theme.skyGradientTop;
        mGradient[1] = theme.skyGradientHalf;
        mGradient[2] = theme.skyGradientBottom;
    }

    void draw(Canvas canvas) {
        if (mParent.enableSkyTex) {
            if (mSkyTex) {
                canvas.drawTiled(mSkyTex, Vector2i(0, mParent.skyOffset),
                    Vector2i(mParent.size.x, mSkyTex.size.y));
            } else {
                //skyBottom defines the height, which doesnt come from the theme
                auto rcf = Rect2i(0, mParent.skyOffset, mParent.size.x,
                    mParent.initialWaterOffset);
                auto rc1 = Rect2i.Span(rcf.p1, Vector2i(rcf.size.x,
                    rcf.size.y/2));
                auto rc2 = Rect2i(Vector2i(rcf.p1.x, rc1.p2.y), rcf.p2);
                canvas.drawVGradient(rc1, mGradient[0], mGradient[1]);
                canvas.drawVGradient(rc2, mGradient[1], mGradient[2]);
            }
            if (mParent.skyOffset > 0)
                canvas.drawFilledRect(Rect2i(0, 0,
                    mParent.size.x, mParent.skyOffset), mSkyColor);
        }
        if (mSkyBackdrop && mParent.enableSkyBackdrop) {
            int offs = mParent.initialWaterOffset - mSkyBackdrop.size.y;
            canvas.drawTiled(mSkyBackdrop, Vector2i(canvas.visibleArea.p1.x/6,
                offs), Vector2i(mParent.size.x, mSkyBackdrop.size.y));
        }
    }
}

class GameSky {
    private {
        GameCore mEngine;
        //used where it's needed
        GameEngine mREngine;

        SkyDrawer mSkyDrawer;
        int skyOffset, skyBottom, initialWaterOffset;
        Animation[] mCloudAnims;
        bool mEnableClouds = true;
        bool mEnableDebris = true;
        bool mCloudsVisible;

        Animation[] mStarAnims;

        const cNumClouds = 50;
        const cCloudHeightRange = 50;
        const cCloudSpeedRange = 100;
        const cWindMultiplier = 150;

        const cNumDebris = 100;
        //this is not gravity, as debris is not accelerated
        const cDebrisFallSpeed = 70; //pixels/sec

        struct CloudInfo {
            Animator anim;
            int animSizex;
            float xspeed;
            int y;
            float x;
        }
        CloudInfo[cNumClouds] mCloudAnimators;

        struct DebrisInfo {
            Animator anim;
            float speedPerc;
            float x, y;
        }
        DebrisInfo[cNumDebris] mDebrisAnimators;

        Animation mDebrisAnim;
    }

    bool enableSkyBackdrop = true;
    bool enableSkyTex = true;

    Vector2i size;

    ///create data structures and load textures, however no
    ///game-related values are used
    this(GameCore a_engine) {
        mEngine = a_engine;
        mREngine = GameEngine.fromCore(a_engine);

        size = mEngine.level.worldSize;

        EnvironmentTheme theme = mEngine.level.theme;

        auto gfx = mEngine.singleton!(GfxSet)();
        ConfigNode skyNode = gfx.config.getSubNode("sky");
        Color skyColor = theme.skyColor;

        mDebrisAnim = theme.skyDebris;

        Scene scene = mEngine.scene;

        ConfigNode cloudNode = skyNode.getSubNode("clouds");
        foreach (char[] name, char[] value; cloudNode) {
            mCloudAnims ~= mEngine.resources.get!(Animation)(value);
        }

        ConfigNode starNode = skyNode.getSubNode("stars");
        foreach (char[] name, char[] value; starNode) {
            mStarAnims ~= mEngine.resources.get!(Animation)(value);
        }

        int nAnim = 0;
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.anim = new Animator(ts);
            ci.anim.setAnimation(mCloudAnims[nAnim],
                timeMsecs(rngShared.nextRange(0,
                    cast(int)(mCloudAnims[nAnim].duration.msecs))));
            scene.add(ci.anim, GameZOrder.Clouds);
            ci.animSizex = 10;//mCloudAnims[nAnim].bounds.size.x;
            ci.y = rngShared.nextRange(-cCloudHeightRange/2,cCloudHeightRange/2)
                - 5;//mCloudAnims[nAnim].bounds.size.y/2;
            //speed delta to wind speed
            ci.xspeed = rngShared.nextRange(-cCloudSpeedRange/2,
                cCloudSpeedRange/2);
            nAnim = (nAnim+1)%mCloudAnims.length;
        }

        if (mDebrisAnim) {
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.anim = new Animator(ts);
                di.anim.setAnimation(mDebrisAnim, timeMsecs(rngShared.nextRange
                    (0, cast(int)(mDebrisAnim.duration.msecs))));
                scene.add(di.anim, GameZOrder.BackLayer);
                di.speedPerc = rngShared.nextRange(0.4f, 1.5f);
            }
        }

        if (skyNode.getValue!(bool)("enableStars", false)) {
            Scene stars = new Scene();
            auto worldsz = mEngine.level.worldBounds;
            nAnim = 0;
            for (int n = 0; n < 1000; n++) {
                auto anim = new Animator(ts);
                anim.setAnimation(mStarAnims[nAnim]);
                float py = rngShared.nextRange(0.0, 1.0);
                py = py*py; //more stars at top
                auto y = rngShared.nextRange(worldsz.p1.y, worldsz.p2.y) * py;
                anim.pos = Vector2i(
                    rngShared.nextRange(worldsz.p1.x, worldsz.p2.x),
                    cast(int)y);
                stars.add(anim);
                nAnim = (nAnim+1)%mStarAnims.length;
            }
            scene.add(stars, GameZOrder.Stars);
        }

        mSkyDrawer = new SkyDrawer(this, theme);
        scene.add(mSkyDrawer, GameZOrder.Background);

        //xxx make sure mEngine.waterOffset is valid for this call
        initialize();
    }

    private TimeSourcePublic ts() {
        //timesource changed in r1119
        return mEngine.interpolateTime;
    }

    ///initialize object positions on game start
    ///game-specific values have to be valid (e.g. waterOffset)
    private void initialize() {
        updateOffsets();
        initialWaterOffset = mEngine.level.waterBottomY;
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.x = rngShared.nextRange(-ci.animSizex, size.x);
        }

        if (mDebrisAnim) {
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.x = rngShared.nextRange(-mDebrisAnim.bounds.size.x, size.x);
                di.y = rngShared.nextRange(skyOffset, skyBottom);
            }
        }

        //actually let it set the positions of the scene objects
        simulate();
    }

    private void updateOffsets() {
        skyOffset = mEngine.level.skyTopY;
        if (skyOffset > 0)
            mCloudsVisible = true;
        else
            mCloudsVisible = false;
        skyBottom = mREngine.waterOffset;
        //update cloud visibility status
        enableClouds(mEnableClouds);
    }

    public void enableClouds(bool enable) {
        if (mEnableClouds == enable)
            return;
        mEnableClouds = enable;
        if (mCloudsVisible && enable) {
            foreach (inout ci; mCloudAnimators) {
                ci.anim.active = true;
            }
        } else {
            foreach (inout ci; mCloudAnimators) {
                ci.anim.active = false;
            }
        }
    }
    public bool enableClouds() {
        return mEnableClouds;
    }

    public void enableDebris(bool enable) {
        if (mEnableDebris == enable)
            return;
        mEnableDebris = enable;
        if (mDebrisAnim) {
            if (enable) {
                foreach (inout di; mDebrisAnimators) {
                    di.anim.active = true;
                }
            } else {
                foreach (inout di; mDebrisAnimators) {
                    di.anim.active = false;
                }
            }
        }
    }
    public bool enableDebris() {
        return mEnableDebris;
    }

    void simulate() {
        void clip(inout float v, float s, float min, float max) {
            if (v > max)
                v -= (max-min) + s;
            if (v + s < min)
                v += (max-min) + s;
        }

        updateOffsets();

        float deltaT = ts.difference.secsf;

        if (mCloudsVisible && mEnableClouds) {
            foreach (inout ci; mCloudAnimators) {
                //XXX this is acceleration, how to get a constant speed from this??
                ci.x += (ci.xspeed + mREngine.windSpeed*cWindMultiplier)
                    * deltaT;
                clip(ci.x, ci.animSizex, 0, size.x);
                ci.anim.pos = Vector2i(cast(int)ci.x, skyOffset + ci.y);
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            //XXX (and, XXX) handmade physics
            foreach (inout di; mDebrisAnimators) {
                //XXX same here
                di.x += 2 * mREngine.windSpeed * cWindMultiplier * deltaT
                    * di.speedPerc;
                di.y += cDebrisFallSpeed*deltaT;
                clip(di.x, mDebrisAnim.bounds.size.x, 0, size.x);
                clip(di.y, mDebrisAnim.bounds.size.y, skyOffset, skyBottom);
                di.anim.pos = Vector2i(cast(int)di.x, cast(int)di.y);
            }
        }
    }
}
