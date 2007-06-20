module game.sky;

import framework.framework;
import game.clientengine;
import game.glevel;
import game.common;
import game.animation;
import game.scene;
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
            for (int x = 0; x < scene.size.x; x += mSkyTex.size.x) {
                canvas.draw(mSkyTex, Vector2i(x, mParent.skyOffset));
            }
            if (mParent.skyOffset > 0)
                canvas.drawFilledRect(Vector2i(0, 0),
                    Vector2i(scene.size.x, mParent.skyOffset), mSkyColor);
        }
        if (mSkyBackdrop && mParent.enableSkyBackdrop) {
            int offs = mParent.skyBottom - mSkyBackdrop.size.y;
            for (int x = canvas.clientOffset.x/8; x < scene.size.x; x += mSkyBackdrop.size.x) {
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

    private Scene mScene;

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

    this(ClientGameEngine engine, Scene target) {
        mEngine = engine;
        mScene = target;
        ConfigNode skyNode = globals.loadConfig("sky");
        globals.resources.loadResources(skyNode);
        Color skyColor = engine.level.skyColor;

        Surface bmp = engine.level.skyGradient;
        if (!bmp) {
            bmp = globals.loadGraphic(skyNode.getStringValue("gradient"));
            if (!bmp)
                throw new Exception("Failed to load gradient bitmap");
        }
        Texture skyTex = bmp.createTexture();
        mSkyHeight = skyTex.size.y;

        bmp = engine.level.skyBackdrop;
        Texture skyBackdrop = null;
        if (bmp) {
            skyBackdrop = bmp.createTexture();
        }

        mDebrisAnim = engine.level.skyDebris.get();

        //xxx as waterOffset is not valid here, this will set strange values
        //however the first onFrame should fix them
        //but initial anim offsets are affected
        updateOffsets();

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
            ci.anim.setScene(target, GameZOrder.Objects);
            ci.y = randRange(-cCloudHeightRange/2,cCloudHeightRange/2)
                - mCloudAnims[nAnim].size.y/2;
            ci.anim.pos.y = skyOffset + ci.y;
            ci.x = randRange(-mCloudAnims[nAnim].size.x, target.size.x);
            ci.anim.pos.x = cast(int)ci.x;
            //xxx ci.anim.setFrame(randRange(0u,mCloudAnims[nAnim].frameCount));
            ci.animSizex = mCloudAnims[nAnim].size.x;
            //speed delta to wind speed
            ci.xspeed = randRange(-cCloudSpeedRange/2, cCloudSpeedRange/2);
            nAnim = (nAnim+1)%mCloudAnims.length;
        }

        if (mDebrisAnim) {
            scope (failure) mDebrisAnim = null;
            foreach (inout DebrisInfo di; mDebrisAnimators) {
                di.anim = new Animator();
                di.anim.setAnimation(mDebrisAnim);
                di.anim.setScene(target, GameZOrder.BackLayer);
                di.x = randRange(-mDebrisAnim.size.x, target.size.x);
                di.y = randRange(skyOffset, skyBottom);
                di.anim.pos.x = cast(int)di.x;
                di.anim.pos.y = cast(int)di.y;
                //xxx di.anim.setFrame(randRange(0u,mDebrisAnim.frameCount));
                di.speedPerc = genrand_real1()/2.0+0.5;
            }
        }

        mSkyDrawer = new SkyDrawer(this, skyColor, skyTex, skyBackdrop);
        mSkyDrawer.setScene(target, GameZOrder.Background);
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
                clip(ci.x, ci.animSizex, 0, mScene.size.x);
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
                clip(di.x, mDebrisAnim.size.x, 0, mScene.size.x);
                clip(di.y, mDebrisAnim.size.y, skyOffset, skyBottom);
                di.anim.pos.x = cast(int)di.x;
                di.anim.pos.y = cast(int)di.y;
            }
        }
    }

    void kill() {
        mSkyDrawer.active = false;
        if (mCloudsVisible && mEnableClouds) {
            foreach (inout ci; mCloudAnimators) {
                ci.anim.active = false;
                ci.anim = null;
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            foreach (inout di; mDebrisAnimators) {
                di.anim.active = false;
                di.anim = null;
            }
        }
    }
}
