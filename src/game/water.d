module game.water;

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

class WaterDrawer : SceneObject {
    protected Color mWaterColor;
    protected GameWater mParent;

    this(GameWater parent, Color waterColor) {
        mParent = parent;
        mWaterColor = waterColor;
    }
}

class WaterDrawerFront : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas, SceneView parentView) {
        canvas.drawFilledRect(Vector2i(0, mParent.waterOffs),
            scene.thesize, mWaterColor);
    }
}

class WaterDrawerBack : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas, SceneView parentView) {
        canvas.drawFilledRect(Vector2i(0, mParent.waterOffs
            - mParent.cBackLayers*mParent.cWaterLayerDist),
            Vector2i(scene.thesize.x, mParent.waterOffs),
            mWaterColor);
    }
}

class GameWater : GameObject {
    package const cBackLayers = 2;
    package const cFrontLayers = 3;
    package const cWaterLayerDist = 20;

    private WaterDrawer mWaterDrawerFront, mWaterDrawerBack;
    private Animation mWaveAnim;
    private HorizontalFullsceneAnimator[3] mWaveAnimFront;
    private HorizontalFullsceneAnimator[2] mWaveAnimBack;

    /+protected+/ uint waterOffs;
    private uint mStoredWaterLevel = uint.max;
    private GameLevel mLevel;
    private bool mSimpleMode = true;

    this(GameEngine engine, char[] waterType) {
        super(engine);
        mLevel = engine.gamelevel;
        ConfigNode waterNode = globals.loadConfig("water").getSubNode(waterType);
        Color waterColor;
        parseColor(waterNode.getStringValue("color"),waterColor);
        mWaterDrawerFront = new WaterDrawerFront(this, waterColor);
        mWaterDrawerFront.setScene(engine.scene, GameZOrder.FrontWater);
        mWaterDrawerBack = new WaterDrawerBack(this, waterColor);
        mWaterDrawerBack.setScene(engine.scene, GameZOrder.BackWater);
        try {
            mWaveAnim = new Animation(waterNode.getSubNode("waves"));
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
        if (mLevel.waterLevel != mStoredWaterLevel) {
            waterOffs = mLevel.offset.y + mLevel.height-mLevel.waterLevel;
            if (mWaveAnim) {
                uint p = waterOffs;
                foreach_reverse (inout a; mWaveAnimBack) {
                    p -= cWaterLayerDist;
                    a.ypos = p - mWaveAnim.size.y/2;
                }
                p = waterOffs;
                foreach (inout a; mWaveAnimFront) {
                    a.ypos = p - mWaveAnim.size.y/2;
                    p += cWaterLayerDist;
                }
            }
            mStoredWaterLevel = mLevel.waterLevel;
        }
    }

    override void kill() {
        mWaterDrawerFront.active = false;
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

    void draw(Canvas canvas, SceneView parentView) {
        int w = mAni.size.x;
        for (int x = xoffs-w; x < scene.thesize.x; x += w) {
            pos = Vector2i(x, ypos);
            //XXX I just hope canvas does clipping instead of letting sdl to it
            super.draw(canvas, parentView);
        }
    }
}
