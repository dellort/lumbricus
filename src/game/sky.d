module game.sky;

import framework.framework;
import framework.restypes.bitmap;
import game.clientengine;
import game.glevel;
import game.animation;
import common.scene;
import str = std.string;
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

    this(GameSky parent, Color skyColor, Texture skyTex, Texture skyBackdrop) {
        mParent = parent;
        mSkyColor = skyColor;
        mSkyTex = skyTex;
        mSkyBackdrop = skyBackdrop;
    }

    void draw(Canvas canvas) {
        if (mParent.enableSkyTex) {
            canvas.drawTiled(mSkyTex, Vector2i(0, mParent.skyOffset),
                Vector2i(mParent.size.x, mSkyTex.size.y));
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
    private int mSkyHeight;

    bool enableSkyBackdrop = true;
    bool enableSkyTex = true;

    private const cNumClouds = 50;
    private const cCloudHeightRange = 50;
    private const cCloudSpeedRange = 100;

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

    enum Z {
        back,
        debris,
        clouds,
    }
    Scene[Z.max+1] scenes;

    Vector2i size;

    ///create data structures and load textures, however no
    ///game-related values are used
    this(ClientGameEngine engine) {
        foreach (inout s; scenes) {
            s = new Scene();
            s.rect = engine.scene.rect;
        }

        size = engine.scene.size;

        mEngine = engine;
        ConfigNode skyNode = gFramework.loadConfig("sky");
        Color skyColor = engine.engine.level.skyColor;

        Surface bmp = engine.engine.level.skyGradient;
        if (!bmp) {
            bmp = mEngine.resources.get!(Surface)("default_gradient");
        }
        Texture skyTex = bmp.createTexture();
        mSkyHeight = skyTex.size.y;

        bmp = engine.engine.level.skyBackdrop;
        Texture skyBackdrop = null;
        if (bmp) {
            skyBackdrop = bmp.createTexture();
        }

        mDebrisAnim = engine.engine.level.skyDebris;

        ConfigNode cloudNode = skyNode.getSubNode("clouds");
        foreach (char[] name, char[] value; cloudNode) {
            mCloudAnims ~= mEngine.resources.get!(Animation)(value);
        }

        int nAnim = 0;
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.anim = new Animator();
            ci.anim.setAnimation(mCloudAnims[nAnim]);
            scenes[Z.clouds].add(ci.anim);
            //xxx ci.anim.setFrame(randRange(0u,mCloudAnims[nAnim].frameCount));
            ci.animSizex = 10;//mCloudAnims[nAnim].bounds.size.x;
            ci.y = randRange(-cCloudHeightRange/2,cCloudHeightRange/2)
                - 5;//mCloudAnims[nAnim].bounds.size.y/2;
            //speed delta to wind speed
            ci.xspeed = randRange(-cCloudSpeedRange/2, cCloudSpeedRange/2);
            nAnim = (nAnim+1)%mCloudAnims.length;
        }

        if (mDebrisAnim) {
            scope (failure) mDebrisAnim = null;
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.anim = new Animator();
                di.anim.setAnimation(mDebrisAnim, timeMsecs(randRange(0,
                    cast(int)(mDebrisAnim.duration.msecs))));
                scenes[Z.debris].add(di.anim);
                di.speedPerc = genrand_real1()/2.0+0.5;
            }
        }

        mSkyDrawer = new SkyDrawer(this, skyColor, skyTex, skyBackdrop);
        scenes[Z.back].add(mSkyDrawer);

        //xxx make sure mEngine.waterOffset is valid for this call
        initialize();
    }

    ///initialize object positions on game start
    ///game-specific values have to be valid (e.g. waterOffset)
    void initialize() {
        updateOffsets();
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.x = randRange(-ci.animSizex, scenes[Z.clouds].size.x);
        }

        if (mDebrisAnim) {
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.x = randRange(-mDebrisAnim.bounds.size.x, scenes[Z.debris].size.x);
                di.y = randRange(skyOffset, skyBottom);
            }
        }

        //actually let it set the positions of the scene objects
        simulate(0);
    }

    private void updateOffsets() {
        skyOffset = mEngine.waterOffset-mSkyHeight;
        if (skyOffset > 0)
            mCloudsVisible = true;
        else
            mCloudsVisible = false;
        skyBottom = mEngine.waterOffset;
    }

    public void enableClouds(bool enable) {
        mEnableClouds = enable;
        if (mCloudsVisible) {
            if (enable) {
                foreach (inout ci; mCloudAnimators) {
                    ci.anim.active = true;
                }
            } else {
                foreach (inout ci; mCloudAnimators) {
                    ci.anim.active = false;
                }
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

    void simulate(float deltaT) {
        void clip(inout float v, float s, float min, float max) {
            if (v > max)
                v -= (max-min) + s;
            if (v + s < 0)
                v += (max-min) + s;
        }

        updateOffsets();

        if (mCloudsVisible && mEnableClouds) {
            foreach (inout ci; mCloudAnimators) {
                //XXX this is acceleration, how to get a constant speed from this??
                ci.x += (ci.xspeed+mEngine.windSpeed)*deltaT;
                clip(ci.x, ci.animSizex, 0, scenes[Z.clouds].size.x);
                ci.anim.pos = Vector2i(cast(int)ci.x, skyOffset + ci.y);
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            //XXX (and, XXX) handmade physics
            foreach (inout di; mDebrisAnimators) {
                //XXX same here
                di.x += 2*mEngine.windSpeed*deltaT*di.speedPerc;
                di.y += cDebrisFallSpeed*deltaT;
                clip(di.x, mDebrisAnim.bounds.size.x, 0, scenes[Z.debris].size.x);
                clip(di.y, mDebrisAnim.bounds.size.y, skyOffset, skyBottom);
                di.anim.pos = Vector2i(cast(int)di.x, cast(int)di.y);
            }
        }
    }
}
