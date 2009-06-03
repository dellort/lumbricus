module game.water;

import framework.framework;
import game.clientengine;
import game.glevel;
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

    this(ClientGameEngine engine) {
        size = engine.engine.worldSize;

        mEngine = engine;
        Color waterColor = engine.gfx.waterColor;

        Scene scene = mEngine.scene;

        mWaterDrawerFront1 = new WaterDrawerFront1(this, waterColor);
        scene.add(mWaterDrawerFront1, GameZOrder.FrontWater);
        mWaterDrawerFront2 = new WaterDrawerFront2(this, waterColor);
        scene.add(mWaterDrawerFront2, GameZOrder.LevelWater);
        mWaterDrawerBack = new WaterDrawerBack(this, waterColor);
        scene.add(mWaterDrawerBack, GameZOrder.BackWater);
        //try {
            mWaveAnim = mEngine.resources.get!(Animation)("water_waves");
            foreach (int i, inout a; mWaveAnimBack) {
                a = new HorizontalFullsceneAnimator();
                a.animator = new Animator(mEngine.engineTime);
                a.animator.setAnimation(mWaveAnim);
                scene.add(a, GameZOrder.BackWater);
                a.xoffs = rngShared.nextRange(0,mWaveAnim.bounds.size.x);
                a.size = size;
                a.scrollMult = -0.16666f+i*0.08333f;
            }
            foreach (int i, inout a; mWaveAnimFront) {
                a = new HorizontalFullsceneAnimator();
                a.animator = new Animator(mEngine.engineTime);
                a.animator.setAnimation(mWaveAnim);
                scene.add(a, GameZOrder.FrontWater);
                a.xoffs = rngShared.nextRange(0,mWaveAnim.bounds.size.x);
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

    void simulate() {
        if (mEngine.engine.waterOffset != mStoredWaterLevel) {
            waterOffs = mEngine.engine.waterOffset;
            uint p = waterOffs;
            int waveCenterDiff = 0;
            backAnimTop = waterOffs;
            if (mWaveAnim) {
                waveCenterDiff = - cast(int)(mWaveAnim.bounds.size.y*cWaveAnimMult)
                    + mWaveAnim.bounds.size.y/2;
                foreach_reverse (inout a; mWaveAnimBack) {
                    p -= cWaterLayerDist;
                    a.ypos = p - cast(int)(mWaveAnim.bounds.size.y*cWaveAnimMult);
                    a.size = size;
                }
                backAnimTop = p + waveCenterDiff;
                p = waterOffs;
                foreach (inout a; mWaveAnimFront) {
                    a.ypos = p - cast(int)(mWaveAnim.bounds.size.y*cWaveAnimMult);
                    p += cWaterLayerDist;
                }
                p = p - cWaterLayerDist + waveCenterDiff;
            }
            animTop = waterOffs + waveCenterDiff;
            animBottom = p;
            mStoredWaterLevel = mEngine.engine.waterOffset;
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

        int w = animator.bounds.size.x;
        int soffs = cast(int)(scrollMult*canvas.visibleArea.p1.x);
        for (int x = xoffs-w-soffs; x < size.x; x += w) {
            //due to scrolling parallax, this can get out of the scene
            if (x+w > 0) {
                animator.pos = Vector2i(x, ypos) - animator.animation.bounds.p1;
                animator.draw(canvas);
            }
        }
    }
}
