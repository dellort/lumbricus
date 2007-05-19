module game.sky;

import framework.framework;
import game.game;
import game.gobject;
import game.glevel;
import game.common;
import game.animation;
import game.scene;
import rand = std.random;
import utils.time;
import utils.vector2;
import utils.configfile;

int random(int min, int max) {
    auto r = rand.rand();
    return cast(int)(min + (max-min)*(cast(float)r/r.max));
}

class SkyDrawer : SceneObject {
    private GameSky mParent;
    private Color mSkyColor;
    private Texture mSkyTex;

    this(GameSky parent, Color skyColor, Texture skyTex) {
        mParent = parent;
        mSkyColor = skyColor;
        mSkyTex = skyTex;
    }

    void draw(Canvas canvas) {
        for (int x = 0; x < scene.thesize.x; x += mSkyTex.size.x) {
            canvas.draw(mSkyTex, Vector2i(x, mParent.skyOffset));
        }
        if (mParent.skyOffset > 0)
            canvas.drawFilledRect(Vector2i(0, 0),
                Vector2i(scene.thesize.x, mParent.skyOffset), mSkyColor);
    }
}

class GameSky : GameObject {
    private SkyDrawer mSkyDrawer;
    protected int skyOffset;
    private Animation[] mCloudAnims;
    private bool mEnableClouds = false;

    private const cNumClouds = 50;
    private const cCloudMaxSpeed = 200;

    private struct CloudInfo {
        Animator anim;
        int animSizex;
        float xspeed;
        float x;
    }
    private CloudInfo[cNumClouds] mCloudAnimators;

    this(GameController controller) {
        super(controller);
        ConfigNode skyNode = globals.loadConfig("sky");
        Color skyColor;
        parseColor(skyNode.getStringValue("skycolor"),skyColor);

        Surface bmp = globals.loadGraphic(skyNode.getStringValue("gradient"));
        if (!bmp)
            throw new Exception("Failed to load animation bitmap");
        Texture skyTex = bmp.createTexture();

        skyOffset = controller.gamelevel.offset.y+controller.gamelevel.height-skyTex.size.y;
        if (skyOffset > 0)
            mEnableClouds = true;
        else
            mEnableClouds = false;

        if (mEnableClouds) {
            try {
                foreach (char[] nodeName, ConfigNode node; skyNode.getSubNode("clouds")) {
                    mCloudAnims ~= new Animation(node);
                }

                int nAnim = 0;
                foreach (inout CloudInfo ci; mCloudAnimators) {
                    ci.anim = new Animator();
                    ci.anim.setAnimation(mCloudAnims[nAnim]);
                    ci.anim.setScene(controller.scene, GameZOrder.Background);
                    ci.anim.pos.y = skyOffset - mCloudAnims[nAnim].size.y/2;
                    ci.x = random(-mCloudAnims[nAnim].size.x, controller.scene.thesize.x);
                    ci.anim.pos.x = cast(int)ci.x;
                    ci.anim.setFrame(random(0,mCloudAnims[nAnim].frameCount));
                    ci.animSizex = mCloudAnims[nAnim].size.x;
                    ci.xspeed = random(1,cCloudMaxSpeed);
                    nAnim = (nAnim+1)%mCloudAnims.length;
                }
            } catch {
                mEnableClouds = false;
            }
        }

        mSkyDrawer = new SkyDrawer(this, skyColor, skyTex);
        mSkyDrawer.setScene(controller.scene, GameZOrder.Background);
    }

    private int mTLast;

    override void simulate(Time curTime) {
        if (mEnableClouds) {
            int t = curTime.msecs();
            if (mTLast>0) {
                float deltaT = cast(float)(t-mTLast)/1000.0f;
                foreach (inout ci; mCloudAnimators) {
                    ci.x += ci.xspeed*deltaT;
                    if (ci.x > controller.scene.thesize.x)
                        ci.x = -ci.animSizex;
                    ci.anim.pos.x = cast(int)ci.x;
                }
            }
            mTLast = t;
        }
    }

    override void kill() {
        mSkyDrawer.active = false;
        if (mEnableClouds) {
            foreach (inout ci; mCloudAnimators) {
                ci.anim.active = false;
                ci.anim = null;
            }
        }
    }
}
