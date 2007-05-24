module game.sky;

import framework.framework;
import game.game;
import game.gobject;
import game.glevel;
import game.common;
import game.animation;
import game.scene;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.configfile;

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
        for (int x = 0; x < scene.thesize.x; x += mSkyTex.size.x) {
            canvas.draw(mSkyTex, Vector2i(x, mParent.skyOffset));
        }
        if (mParent.skyOffset > 0)
            canvas.drawFilledRect(Vector2i(0, 0),
                Vector2i(scene.thesize.x, mParent.skyOffset), mSkyColor);
        if (mSkyBackdrop) {
            for (int x = 0; x < scene.thesize.x; x += mSkyBackdrop.size.x) {
                canvas.draw(mSkyBackdrop, Vector2i(x, mParent.skyBackdropOffset));
            }
        }
    }
}

class GameSky : GameObject {
    private SkyDrawer mSkyDrawer;
    protected int skyOffset, skyBackdropOffset, levelBottom;
    private Animation[] mCloudAnims;
    private bool mEnableClouds = true;
    private bool mEnableDebris = true;
    private bool mCloudsVisible;

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

    this(GameController controller) {
        super(controller);
        ConfigNode skyNode = globals.loadConfig("sky");
        Color skyColor = controller.level.skyColor;

        Surface bmp = controller.level.skyGradient;
        if (!bmp) {
            bmp = globals.loadGraphic(skyNode.getStringValue("gradient"));
            if (!bmp)
                throw new Exception("Failed to load gradient bitmap");
        }
        Texture skyTex = bmp.createTexture();
        bmp = controller.level.skyBackdrop;
        Texture skyBackdrop = null;
        if (bmp) {
            skyBackdrop = bmp.createTexture();
            skyBackdropOffset = controller.gamelevel.offset.y+controller.gamelevel.height-controller.gamelevel.waterLevel-skyBackdrop.size.y;
        }

        mDebrisAnim = controller.level.skyDebris;

        skyOffset = controller.gamelevel.offset.y+controller.gamelevel.height-skyTex.size.y;
        if (skyOffset > 0)
            mCloudsVisible = true;
        else
            mCloudsVisible = false;
        levelBottom = controller.gamelevel.offset.y+controller.gamelevel.height;

        if (mCloudsVisible) {
            try {
                foreach (char[] nodeName, ConfigNode node; skyNode.getSubNode("clouds")) {
                    mCloudAnims ~= new Animation(node);
                }

                int nAnim = 0;
                foreach (inout CloudInfo ci; mCloudAnimators) {
                    ci.anim = new Animator();
                    ci.anim.setAnimation(mCloudAnims[nAnim]);
                    ci.anim.setScene(controller.scene, GameZOrder.Objects);
                    ci.anim.pos.y = skyOffset - mCloudAnims[nAnim].size.y/2 + randRange(-cCloudHeightRange/2,cCloudHeightRange/2);
                    ci.x = randRange(-mCloudAnims[nAnim].size.x, controller.scene.thesize.x);
                    ci.anim.pos.x = cast(int)ci.x;
                    ci.anim.setFrame(randRange(0,mCloudAnims[nAnim].frameCount));
                    ci.animSizex = mCloudAnims[nAnim].size.x;
                    //speed delta to wind speed
                    ci.xspeed = randRange(-cCloudSpeedRange/2, cCloudSpeedRange/2);
                    nAnim = (nAnim+1)%mCloudAnims.length;
                }
            } catch {
                mCloudsVisible = false;
            }
        }

        if (mDebrisAnim) {
            try {
                foreach (inout DebrisInfo di; mDebrisAnimators) {
                    di.anim = new Animator();
                    di.anim.setAnimation(mDebrisAnim);
                    di.anim.setScene(controller.scene, GameZOrder.BackLayer);
                    di.x = randRange(-mDebrisAnim.size.x, controller.scene.thesize.x);
                    di.y = randRange(skyOffset, levelBottom);
                    di.anim.pos.x = cast(int)di.x;
                    di.anim.pos.y = cast(int)di.y;
                    di.anim.setFrame(randRange(0,mDebrisAnim.frameCount));
                    di.speedPerc = genrand_real1()/2.0+0.5;
                }
            } catch {
                mDebrisAnim = null;
            }
        }

        mSkyDrawer = new SkyDrawer(this, skyColor, skyTex, skyBackdrop);
        mSkyDrawer.setScene(controller.scene, GameZOrder.Background);
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
        mEnableClouds = enable;
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

    private int mTLast;

    override void simulate(Time curTime) {
        void clip(inout float v, float s, float min, float max) {
            if (v > max)
                v -= (max-min) + s;
            if (v + s < 0)
                v += (max-min) + s;
        }

        int t = curTime.msecs();
        if (mCloudsVisible && mEnableClouds) {
            if (mTLast>0) {
                float deltaT = cast(float)(t-mTLast)/1000.0f;
                foreach (inout ci; mCloudAnimators) {
                    //XXX this is acceleration, how to get a constant speed from this??
                    ci.x += (ci.xspeed+controller.windSpeed)*deltaT;
                    clip(ci.x, ci.animSizex, 0, controller.scene.thesize.x);
                    ci.anim.pos.x = cast(int)ci.x;
                }
            }
        }
        if (mDebrisAnim && mEnableDebris) {
            //XXX (and, XXX) handmade physics
            if (mTLast>0) {
                float deltaT = cast(float)(t-mTLast)/1000.0f;
                foreach (inout di; mDebrisAnimators) {
                    //XXX same here
                    di.x += 2*controller.windSpeed*deltaT*di.speedPerc;
                    di.y += cDebrisFallSpeed*deltaT;
                    clip(di.x, mDebrisAnim.size.x, 0, controller.scene.thesize.x);
                    clip(di.y, mDebrisAnim.size.y, skyOffset, levelBottom);
                    di.anim.pos.x = cast(int)di.x;
                    di.anim.pos.y = cast(int)di.y;
                }
            }
        }
        mTLast = t;
    }

    override void kill() {
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
