module game.water;

import framework.framework;
import game.clientengine;
import game.glevel;
import common.common;
import game.animation;
import common.scene;
import utils.misc;
import utils.time;
import utils.vector2;
import utils.configfile;
import utils.random;


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
            Vector2i(mParent.size.x, mParent.animBottom), mWaterColor);
    }
}

class WaterDrawerFront2 : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0, mParent.animBottom),
            mParent.size, mWaterColor);
    }
}

class WaterDrawerBack : WaterDrawer {
    this(GameWater parent, Color waterColor) {
        super(parent, waterColor);
    }

    void draw(Canvas canvas) {
        canvas.drawFilledRect(Vector2i(0, mParent.backAnimTop),
            Vector2i(mParent.size.x, mParent.animTop),
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

    Vector2i size;

    enum Z {
        back,
        level,
        front,
    }
    Scene[Z.max+1] scenes;  //back, level, front

    this(ClientGameEngine engine, char[] waterType) {
        foreach (inout s; scenes) {
            s = new Scene();
            s.rect = engine.scene.rect;
        }

        size = engine.scene.size;

        mEngine = engine;
        ConfigNode waterConf = globals.loadConfig("water");
        globals.resources.loadResources(waterConf);
        ConfigNode waterNode = waterConf.getSubNode(waterType);
        Color waterColor;
        parseColor(waterNode.getStringValue("color"),waterColor);
        mWaterDrawerFront1 = new WaterDrawerFront1(this, waterColor);
        scenes[Z.front].add(mWaterDrawerFront1);
        mWaterDrawerFront2 = new WaterDrawerFront2(this, waterColor);
        scenes[Z.level].add(mWaterDrawerFront2);
        mWaterDrawerBack = new WaterDrawerBack(this, waterColor);
        scenes[Z.back].add(mWaterDrawerBack);
        //try {
            mWaveAnim = globals.resources.resource!(AnimationResource)
                (waterNode.getPathValue("waves")).get();
            foreach (int i, inout a; mWaveAnimBack) {
                a = new HorizontalFullsceneAnimator();
                a.animator = new Animator();
                a.animator.setAnimation(mWaveAnim);
                scenes[Z.back].add(a);
                a.xoffs = randRange(0,mWaveAnim.size.x);
                a.size = size;
                a.scrollMult = -0.16666f+i*0.08333f;
            }
            foreach (int i, inout a; mWaveAnimFront) {
                a = new HorizontalFullsceneAnimator();
                a.animator = new Animator();
                a.animator.setAnimation(mWaveAnim);
                scenes[Z.front].add(a);
                a.xoffs = randRange(0,mWaveAnim.size.x);
                a.size = size;
                a.scrollMult = 0.0f+i*0.15f;
            }
        //wtf? } catch {};
        simpleMode(mSimpleMode);
    }

    public void simpleMode(bool simple) {
        mSimpleMode = simple;
        if (mWaveAnim) {
            //make sure to kill all, then
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
            //what?
            assert(false);
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
                    a.size = size;
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
}

//XXX I don't like that
//quite dirty hack to get water drawn over the complete scene
class HorizontalFullsceneAnimator : SceneObject {
    public uint ypos;
    //texture offset
    public uint xoffs;
    //scrolling pos multiplier
    public float scrollMult = 0;

    public Vector2i size;

    Animator animator;

    void draw(Canvas canvas) {
        if (!animator)
            return;

        int w = animator.size.x;
        int soffs = cast(int)(scrollMult*canvas.clientOffset.x);
        for (int x = xoffs-w-soffs; x < size.x; x += w) {
            //due to scrolling parallax, this can get out of the scene
            if (x+w > 0) {
                animator.pos = Vector2i(x, ypos);
                //XXX I hope canvas does clipping instead of letting sdl to it
                //answer: no, it will be sent to the sdl (and sdl clips it)
                animator.draw(canvas);
            }
        }
    }
}
