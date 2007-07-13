module game.sky;

import framework.framework;
import common.bmpresource;
import game.clientengine;
import game.glevel;
import common.common;
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
            for (int x = 0; x < mParent.size.x; x += mSkyTex.size.x) {
                canvas.draw(mSkyTex, Vector2i(x, mParent.skyOffset));
            }
            if (mParent.skyOffset > 0)
                canvas.drawFilledRect(Vector2i(0, 0),
                    Vector2i(mParent.size.x, mParent.skyOffset), mSkyColor);
        }
        if (mSkyBackdrop && mParent.enableSkyBackdrop) {
            int offs = mParent.skyBottom - mSkyBackdrop.size.y;
            for (int x = canvas.clientOffset.x/6; x < mParent.size.x; x += mSkyBackdrop.size.x) {
                canvas.draw(mSkyBackdrop, Vector2i(x, offs));
            }
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
        ConfigNode skyNode = globals.loadConfig("sky");
        globals.resources.loadResources(skyNode);
        Color skyColor = engine.engine.level.skyColor;

        Surface bmp = engine.engine.level.skyGradient;
        if (!bmp) {
            bmp = globals.resources.resource!(BitmapResource)
                ("/default_gradient").get();
        }
        Texture skyTex = bmp.createTexture();
        mSkyHeight = skyTex.size.y;

        bmp = engine.engine.level.skyBackdrop;
        Texture skyBackdrop = null;
        if (bmp) {
            skyBackdrop = bmp.createTexture();
        }

        mDebrisAnim = engine.engine.level.skyDebris.get();

        int i = 0;
        ConfigNode cloudNode = skyNode.getSubNode("clouds");
        foreach (char[] nodeName; cloudNode) {
            char[] cName = cloudNode.getPathValue(nodeName);
            assert(cName.length > 0);
            mCloudAnims ~= globals.resources.resource!(AnimationResource)
                (cName).get();
            i++;
        }

        int nAnim = 0;
        foreach (inout CloudInfo ci; mCloudAnimators) {
            ci.anim = new Animator();
            ci.anim.setAnimation(mCloudAnims[nAnim]);
            scenes[Z.clouds].add(ci.anim);
            //xxx ci.anim.setFrame(randRange(0u,mCloudAnims[nAnim].frameCount));
            ci.animSizex = mCloudAnims[nAnim].size.x;
            ci.y = randRange(-cCloudHeightRange/2,cCloudHeightRange/2)
                - mCloudAnims[nAnim].size.y/2;
            //speed delta to wind speed
            ci.xspeed = randRange(-cCloudSpeedRange/2, cCloudSpeedRange/2);
            nAnim = (nAnim+1)%mCloudAnims.length;
        }

        if (mDebrisAnim) {
            scope (failure) mDebrisAnim = null;
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.anim = new Animator();
                di.anim.setAnimation(mDebrisAnim);
                scenes[Z.debris].add(di.anim);
                //xxx di.anim.setFrame(randRange(0u,mDebrisAnim.frameCount));
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
            ci.anim.pos.y = skyOffset + ci.y;
            ci.anim.pos.x = cast(int)ci.x;
        }

        if (mDebrisAnim) {
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.x = randRange(-mDebrisAnim.size.x, scenes[Z.debris].size.x);
                di.y = randRange(skyOffset, skyBottom);
                di.anim.pos.x = cast(int)di.x;
                di.anim.pos.y = cast(int)di.y;
            }
        }
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
                ci.anim.pos.x = cast(int)ci.x;
                ci.anim.pos.y = skyOffset + ci.y;
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            //XXX (and, XXX) handmade physics
            foreach (inout di; mDebrisAnimators) {
                //XXX same here
                di.x += 2*mEngine.windSpeed*deltaT*di.speedPerc;
                di.y += cDebrisFallSpeed*deltaT;
                clip(di.x, mDebrisAnim.size.x, 0, scenes[Z.debris].size.x);
                clip(di.y, mDebrisAnim.size.y, skyOffset, skyBottom);
                di.anim.pos.x = cast(int)di.x;
                di.anim.pos.y = cast(int)di.y;
            }
        }
    }
}
