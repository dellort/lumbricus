module game.sky;

import framework.framework;
import common.restypes.bitmap;
import game.clientengine;
import game.glevel;
import game.animation;
import game.levelgen.level : EnvironmentTheme;
import common.scene;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.configfile;
import utils.random;

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
                    mParent.skyBottom);
                auto rc1 = Rect2i.Span(rcf.p1, Vector2i(rcf.size.x,
                    rcf.size.y/2));
                auto rc2 = Rect2i(Vector2i(rcf.p1.x, rc1.p2.y), rcf.p2);
                canvas.drawVGradient(rc1, mGradient[0], mGradient[1]);
                canvas.drawVGradient(rc2, mGradient[1], mGradient[2]);
            }
            if (mParent.skyOffset > 0)
                canvas.drawFilledRect(Vector2i(0, 0),
                    Vector2i(mParent.size.x, mParent.skyOffset), mSkyColor);
        }
        if (mSkyBackdrop && mParent.enableSkyBackdrop) {
            int offs = mParent.skyBottom - mSkyBackdrop.size.y;
            canvas.drawTiled(mSkyBackdrop, Vector2i(canvas.clientOffset.x/6,
                offs), Vector2i(mParent.size.x, mSkyBackdrop.size.y));
        }
    }
}

class GameSky {
    private ClientGameEngine mEngine;

    private SkyDrawer mSkyDrawer;
    protected int skyOffset, skyBottom;
    private Animation[] mCloudAnims;
    private bool mEnableClouds = true;
    private bool mEnableDebris = true;
    private bool mCloudsVisible;

    bool enableSkyBackdrop = true;
    bool enableSkyTex = true;

    private const cNumClouds = 50;
    private const cCloudHeightRange = 50;
    private const cCloudSpeedRange = 100;
    private const cWindMultiplier = 150;

    private const cNumDebris = 100;
    //this is not gravity, as debris is not accelerated
    private const cDebrisFallSpeed = 70; //pixels/sec

    private struct CloudInfo {
        Animator anim;
        int animSizex;
        float xspeed;
        int y;
        float x;
    }
    private CloudInfo[cNumClouds] mCloudAnimators;

    private struct DebrisInfo {
        Animator anim;
        float speedPerc;
        float x, y;
    }
    private DebrisInfo[cNumDebris] mDebrisAnimators;
    private Animation mDebrisAnim;

    Vector2i size;

    ///create data structures and load textures, however no
    ///game-related values are used
    this(ClientGameEngine engine) {
        size = engine.worldSize;

        EnvironmentTheme theme = engine.engine.level.theme;

        mEngine = engine;
        ConfigNode skyNode = engine.gfx.config.getSubNode("sky");
        Color skyColor = theme.skyColor;

        mDebrisAnim = theme.skyDebris;

        Scene scene = mEngine.scene;

        ConfigNode cloudNode = skyNode.getSubNode("clouds");
        foreach (char[] name, char[] value; cloudNode) {
            mCloudAnims ~= mEngine.resources.get!(Animation)(value);
        }

        int nAnim = 0;
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.anim = new Animator(engine.engineTime);
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
            scope (failure) mDebrisAnim = null;
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.anim = new Animator(engine.engineTime);
                di.anim.setAnimation(mDebrisAnim, timeMsecs(rngShared.nextRange
                    (0, cast(int)(mDebrisAnim.duration.msecs))));
                scene.add(di.anim, GameZOrder.BackLayer);
                di.speedPerc = rngShared.nextDouble()/2.0+0.5;
            }
        }

        mSkyDrawer = new SkyDrawer(this, theme);
        scene.add(mSkyDrawer, GameZOrder.Background);

        //xxx make sure mEngine.waterOffset is valid for this call
        initialize();
    }

    ///initialize object positions on game start
    ///game-specific values have to be valid (e.g. waterOffset)
    void initialize() {
        updateOffsets();
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
        skyOffset = mEngine.engine.level.skyTopY;
        if (skyOffset > 0)
            mCloudsVisible = true;
        else
            mCloudsVisible = false;
        skyBottom = mEngine.engine.level.waterBottomY;
        //update cloud visibility status
        enableClouds(mEnableClouds);
    }

    public void enableClouds(bool enable) {
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
            if (v + s < 0)
                v += (max-min) + s;
        }

        updateOffsets();

        float deltaT = mEngine.engineTime.difference.secsf;

        if (mCloudsVisible && mEnableClouds) {
            foreach (inout ci; mCloudAnimators) {
                //XXX this is acceleration, how to get a constant speed from this??
                ci.x += (ci.xspeed+mEngine.windSpeed*cWindMultiplier)*deltaT;
                clip(ci.x, ci.animSizex, 0, size.x);
                ci.anim.pos = Vector2i(cast(int)ci.x, skyOffset + ci.y);
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            //XXX (and, XXX) handmade physics
            foreach (inout di; mDebrisAnimators) {
                //XXX same here
                di.x += 2*mEngine.windSpeed*cWindMultiplier*deltaT*di.speedPerc;
                di.y += cDebrisFallSpeed*deltaT;
                clip(di.x, mDebrisAnim.bounds.size.x, 0, size.x);
                clip(di.y, mDebrisAnim.bounds.size.y, skyOffset, skyBottom);
                di.anim.pos = Vector2i(cast(int)di.x, cast(int)di.y);
            }
        }
    }
}
