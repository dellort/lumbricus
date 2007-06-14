module game.water;

import framework.framework;
import game.game;
import game.gobject;
import game.glevel;
import game.common;
import game.animation;
import game.scene;
import game.resources;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.configfile;

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
        canvas.drawFilledRect(Vector2i(0, mParent.waterOffs
            - mParent.cBackLayers*mParent.cWaterLayerDist),
            Vector2i(scene.size.x, mParent.waterOffs),
            mWaterColor);
    }
}

class GameWater : GameObject {
    package const cBackLayers = 2;
    package const cFrontLayers = 3;
    package const cWaterLayerDist = 20;
    package const cWaveAnimMult = 0.7f;

    private WaterDrawer mWaterDrawerFront1,mWaterDrawerFront2,mWaterDrawerBack;
    private Animation mWaveAnim;
    private HorizontalFullsceneAnimator[3] mWaveAnimFront;
    private HorizontalFullsceneAnimator[2] mWaveAnimBack;

    protected uint waterOffs, animTop, animBottom;
    private uint mStoredWaterLevel = uint.max;
    private GameEngine mEngine;
    private bool mSimpleMode = true;

    this(GameEngine engine, char[] waterType) {
        super(engine);
        mEngine = engine;
        ConfigNode waterNode = globals.loadConfig("water").getSubNode(waterType);
        Color waterColor;
        parseColor(waterNode.getStringValue("color"),waterColor);
        mWaterDrawerFront1 = new WaterDrawerFront1(this, waterColor);
        mWaterDrawerFront1.setScene(engine.scene, GameZOrder.FrontUpperWater);
        mWaterDrawerFront2 = new WaterDrawerFront2(this, waterColor);
        mWaterDrawerFront2.setScene(engine.scene, GameZOrder.FrontLowerWater);
        mWaterDrawerBack = new WaterDrawerBack(this, waterColor);
        mWaterDrawerBack.setScene(engine.scene, GameZOrder.BackWater);
        try {
            mWaveAnim = globals.resources.createAnimation(waterNode.getSubNode("waves"),waterType~"_waves").get();
            foreach (int i, inout a; mWaveAnimBack) {
                a = new HorizontalFullsceneAnimator();
                a.setAnimation(mWaveAnim);
                a.setScene(engine.scene, GameZOrder.BackWaterWaves1+i);
                a.xoffs = randRange(0,mWaveAnim.size.x);
            }
            foreach (int i, inout a; mWaveAnimFront) {
                a = new HorizontalFullsceneAnimator();
                a.setAnimation(mWaveAnim);
                a.setScene(engine.scene, GameZOrder.FrontWaterWaves1+i);
                a.xoffs = randRange(0,mWaveAnim.size.x);
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

    override void simulate(float deltaT) {
        if (mEngine.waterOffset != mStoredWaterLevel) {
            waterOffs = mEngine.waterOffset;
            uint p = waterOffs;
            int waveCenterDiff = 0;
            if (mWaveAnim) {
                waveCenterDiff = - cast(int)(mWaveAnim.size.y*cWaveAnimMult)
                    + mWaveAnim.size.y/2;
                foreach_reverse (inout a; mWaveAnimBack) {
                    p -= cWaterLayerDist;
                    a.ypos = p - cast(int)(mWaveAnim.size.y*cWaveAnimMult);
                }
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

    override void kill() {
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

    void draw(Canvas canvas) {
        int w = mAni.size.x;
        for (int x = xoffs-w; x < scene.size.x; x += w) {
            pos = Vector2i(x, ypos);
            //XXX I just hope canvas does clipping instead of letting sdl to it
            super.draw(canvas);
        }
    }
}
