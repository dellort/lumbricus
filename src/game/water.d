module game.water;

import framework.framework;
import game.clientengine;
import game.glevel;
import game.common;
import game.animation;
import game.scene;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.configfile;
import utils.random;

/+
class WaterDrawer : SceneObject {
    protected Color mWaterColor;
    protected GameWater mParent;

    this(GameWater parent, Color waterColor) {
        mParent = parent;
        mWaterColor = waterColor;
    }
}

class WaterDrawerFront1 : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0, mParent.animTop),
            Vector2i(scene.size.x, mParent.animBottom), mWaterColor);
    }
}

class WaterDrawerFront2 : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0, mParent.animBottom),
            scene.size, mWaterColor);
    }
}

class WaterDrawerBack : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0, mParent.backAnimTop),
            Vector2i(scene.size.x, mParent.animTop),
            mWaterColor);
    }
}

class GameWater {
    package const cBackLayers = 2;
    package const cFrontLayers = 3;
    package const cWaterLayerDist = 20;
    package const cWaveAnimMult = 0.7f;

    private WaterDrawer mWaterDrawerFront1,mWaterDrawerFront2,mWaterDrawerBack;
    private Animation mWaveAnim;
    private HorizontalFullsceneAnimator[3] mWaveAnimFront;
    private HorizontalFullsceneAnimator[2] mWaveAnimBack;

    protected uint waterOffs, animTop, animBottom, backAnimTop;
    private uint mStoredWaterLevel = uint.max;
    private ClientGameEngine mEngine;
    private bool mSimpleMode = true;

    this(ClientGameEngine engine, Scene target, char[] waterType) {
        mEngine = engine;
        ConfigNode waterConf = globals.loadConfig("water");
        globals.resources.loadResources(waterConf);
        ConfigNode waterNode = waterConf.getSubNode(waterType);
        Color waterColor;
        parseColor(waterNode.getStringValue("color"),waterColor);
        mWaterDrawerFront1 = new WaterDrawerFront1(this, waterColor);
        mWaterDrawerFront1.setScene(target, GameZOrder.FrontUpperWater);
        mWaterDrawerFront2 = new WaterDrawerFront2(this, waterColor);
        mWaterDrawerFront2.setScene(target, GameZOrder.FrontLowerWater);
        mWaterDrawerBack = new WaterDrawerBack(this, waterColor);
        mWaterDrawerBack.setScene(target, GameZOrder.BackWater);
        try {
            mWaveAnim = globals.resources.resource!(AnimationResource)
                (waterNode.getPathValue("waves")).get();
            foreach (int i, inout a; mWaveAnimBack) {
                a = new HorizontalFullsceneAnimator();
                a.setAnimation(mWaveAnim);
                a.setScene(target, GameZOrder.BackWaterWaves1+i);
                a.xoffs = randRange(0,mWaveAnim.size.x);
                a.scrollMult = -0.16666f+i*0.08333f;
            }
            foreach (int i, inout a; mWaveAnimFront) {
                a = new HorizontalFullsceneAnimator();
                a.setAnimation(mWaveAnim);
                a.setScene(target, GameZOrder.FrontWaterWaves1+i);
                a.xoffs = randRange(0,mWaveAnim.size.x);
                a.scrollMult = 0.0f+i*0.15f;
            }
        } catch {};
        simpleMode(mSimpleMode);
    }

    public void simpleMode(bool simple) {
        mSimpleMode = simple;
        if (mWaveAnim) {
            if (simple) {
                //no background layers, one front layer
                foreach (inout a; mWaveAnimBack) {
                    a.active = false;
                }
                for (int i = 1; i < mWaveAnimFront.length; i++) {
                    mWaveAnimFront[i].active = false;
                }
                mWaterDrawerBack.active = false;
            } else {
                //all on
                foreach (inout a; mWaveAnimBack) {
                    a.active = true;
                }
                foreach (inout a; mWaveAnimFront) {
                    a.active = true;
                }
                mWaterDrawerBack.active = true;
            }
        } else {
            mWaterDrawerBack.active = false;
        }
    }
    public bool simpleMode() {
        return mSimpleMode;
    }

    void simulate(float deltaT) {
        if (mEngine.waterOffset != mStoredWaterLevel) {
            waterOffs = mEngine.waterOffset;
            uint p = waterOffs;
            int waveCenterDiff = 0;
            backAnimTop = waterOffs;
            if (mWaveAnim) {
                waveCenterDiff = - cast(int)(mWaveAnim.size.y*cWaveAnimMult)
                    + mWaveAnim.size.y/2;
                foreach_reverse (inout a; mWaveAnimBack) {
                    p -= cWaterLayerDist;
                    a.ypos = p - cast(int)(mWaveAnim.size.y*cWaveAnimMult);
                }
                backAnimTop = p + waveCenterDiff;
                p = waterOffs;
                foreach (inout a; mWaveAnimFront) {
                    a.ypos = p - cast(int)(mWaveAnim.size.y*cWaveAnimMult);
                    p += cWaterLayerDist;
                }
                p = p - cWaterLayerDist + waveCenterDiff;
            }
            animTop = waterOffs + waveCenterDiff;
            animBottom = p;
            mStoredWaterLevel = mEngine.waterOffset;
        }
    }

    void kill() {
        mWaterDrawerFront1.active = false;
        mWaterDrawerFront2.active = false;
        mWaterDrawerBack.active = false;
        foreach (int i, inout a; mWaveAnimBack) {
            a.active = false;
        }
        foreach (int i, inout a; mWaveAnimFront) {
            a.active = false;
        }
    }
}

//XXX I don't like that
//quite dirty hack to get water drawn over the complete scene
class HorizontalFullsceneAnimator : Animator {
    public uint ypos;
    //texture offset
    public uint xoffs;
    //scrolling pos multiplier
    public float scrollMult = 0;

    void draw(Canvas canvas) {
        int w = size.x;
        int soffs = cast(int)(scrollMult*canvas.clientOffset.x);
        for (int x = xoffs-w-soffs; x < scene.size.x; x += w) {
            //due to scrolling parallax, this can get out of the scene
            if (x+w > 0) {
                pos = Vector2i(x, ypos);
                //XXX I hope canvas does clipping instead of letting sdl to it
                super.draw(canvas);
            }
        }
    }
}
+/
