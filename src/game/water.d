module game.water;

import framework.framework;
import game.core;
import game.game;
import game.gfxset;
import game.temp : GameZOrder;
import game.particles;
import common.animation;
import common.scene;
import utils.misc;
import utils.time;
import utils.timer;
import utils.vector2;
import utils.configfile;
import utils.random;


//height in pixels of the alpha blend-out region
const cBlendOutHeight = 75;

class WaterDrawer : SceneObject {
    protected Color mWaterColor;
    protected GameWater mParent;

    void init(GameWater parent, Color waterColor) {
        mParent = parent;
        mWaterColor = waterColor;
    }
}

class WaterDrawerFront1 : WaterDrawer {
    void draw(Canvas canvas) {
        canvas.drawFilledRect(Rect2i(0, mParent.animTop,
            mParent.size.x, mParent.animBottom), mWaterColor);
    }
}

class WaterDrawerFront2 : WaterDrawer {
    void draw(Canvas canvas) {
        canvas.drawFilledRect(Rect2i(Vector2i(0, mParent.animBottom),
            mParent.size), mWaterColor);
    }
}

class WaterDrawerBlendOut : WaterDrawer {
    void draw(Canvas canvas) {
        auto a0 = mWaterColor;
        a0.a = 0;
        canvas.drawVGradient(
            Rect2i(Vector2i(0, mParent.size.y - cBlendOutHeight), mParent.size),
            a0, mWaterColor);
        //draw water _below_ the level area (this code also assumes there's
        //  always water, e.g. water can't turn into a bottomless chasm if the
        //  water level drops below the level height)
        //also not sure about z-order
        //not drawn in simple mode (don't know if ok?)
        auto v = canvas.visibleArea();
        v.p1.y = max(v.p1.y, mParent.size.y);
        if (v.size.y > 0)
            canvas.drawFilledRect(v, mWaterColor);
    }
}

class WaterDrawerBack : WaterDrawer {
    void draw(Canvas canvas) {
        canvas.drawFilledRect(Rect2i(0, mParent.backAnimTop,
            mParent.size.x, mParent.animTop),
            mWaterColor);
    }
}

class GameWater {
    package const cBackLayers = 2;
    package const cFrontLayers = 3;
    package const cWaterLayerDist = 20;
    package const cWaveAnimMult = 0.7f;
    //delay between spawning bubbles in a cave level (scaled if world is larger)
    package const cBubbleInterval = timeMsecs(150);

    private WaterDrawer mWaterDrawerBack, mWaterDrawerBlendOut;
    private Animation mWaveAnim;
    private HorizontalFullsceneAnimator[3] mWaveAnimFront;
    private HorizontalFullsceneAnimator[2] mWaveAnimBack;

    protected uint waterOffs, animTop, animBottom, backAnimTop;
    private uint mStoredWaterLevel = uint.max;
    private GameCore mEngine;
    private bool mSimpleMode = true;
    private ParticleType mBubbleParticle;
    private Timer mBubbleTimer;

    Vector2i size;

    this(GameCore engine) {
        mEngine = engine;

        //NOTE: used to be some other timesource, changed in r1119
        auto ts = mEngine.interpolateTime;

        size = mEngine.level.worldSize;

        //GfxSet just for waterColor
        GfxSet gfx = mEngine.singleton!(GfxSet)();

        WaterDrawer wd(GameZOrder z, WaterDrawer drawer) {
            drawer.init(this, gfx.waterColor);
            mEngine.scene.add(drawer, z);
            return drawer;
        }

        wd(GameZOrder.FrontWater, new WaterDrawerFront1);
        wd(GameZOrder.LevelWater, new WaterDrawerFront2);
        mWaterDrawerBack = wd(GameZOrder.BackWater, new WaterDrawerBack);
        //that zorder is over FrontWater and under Splat, so it's ok
        mWaterDrawerBlendOut = wd(GameZOrder.RangeArrow,
            new WaterDrawerBlendOut);

        mWaveAnim = mEngine.resources.get!(Animation)("water_waves");
        Scene scene = mEngine.scene;
        foreach (int i, inout a; mWaveAnimBack) {
            a = new HorizontalFullsceneAnimator();
            a.animator = new Animator(ts);
            a.animator.setAnimation(mWaveAnim);
            scene.add(a, GameZOrder.BackWater);
            a.xoffs = rngShared.nextRange(0,mWaveAnim.bounds.size.x);
            a.size = size;
            a.scrollMult = -0.16666f+i*0.08333f;
        }
        foreach (int i, inout a; mWaveAnimFront) {
            a = new HorizontalFullsceneAnimator();
            a.animator = new Animator(ts);
            a.animator.setAnimation(mWaveAnim);
            scene.add(a, GameZOrder.FrontWater);
            a.xoffs = rngShared.nextRange(0,mWaveAnim.bounds.size.x);
            a.size = size;
            a.scrollMult = 0.0f+i*0.15f;
        }

        mBubbleParticle = mEngine.resources.get!(ParticleType)("p_waterbubble");
        mBubbleTimer = new Timer(cBubbleInterval*(2000f/size.x), &spawnBubble,
            &ts.current);

        //xxx force execution of setter code in hackish way, may be unneeded
        mSimpleMode = !mSimpleMode;
        simpleMode(!mSimpleMode);
    }

    private void spawnBubble(Timer sender) {
        mEngine.particleWorld.emitParticle(
            Vector2f(size.x * rngShared.nextRealOpen, size.y),
            Vector2f(0), mBubbleParticle);
    }

    public void simpleMode(bool simple) {
        if (mSimpleMode == simple)
            return;
        mSimpleMode = simple;
        //no particle bubbles in simple mode
        mBubbleTimer.enabled = !simple;
        assert(!!mWaveAnim);
        //make sure to kill all, then
        if (simple) {
            //no background layers, one front layer
            foreach (inout a; mWaveAnimBack) {
                a.active = false;
            }
            for (int i = 1; i < mWaveAnimFront.length; i++) {
                mWaveAnimFront[i].active = false;
            }
        } else {
            //all on
            foreach (inout a; mWaveAnimBack) {
                a.active = true;
            }
            foreach (inout a; mWaveAnimFront) {
                a.active = true;
            }
        }
        mWaterDrawerBack.active = !simple;
        mWaterDrawerBlendOut.active = !simple;
    }
    public bool simpleMode() {
        return mSimpleMode;
    }

    void simulate() {
        //GameEngine just for waterOffset
        GameEngine rengine = GameEngine.fromCore(mEngine);
        if (rengine.waterOffset != mStoredWaterLevel) {
            waterOffs = rengine.waterOffset;
            uint p = waterOffs;
            int waveCenterDiff = 0;
            backAnimTop = waterOffs;

            assert(!!mWaveAnim);
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

            animTop = waterOffs + waveCenterDiff;
            animBottom = p;
            mStoredWaterLevel = rengine.waterOffset;
        }
        mBubbleTimer.update();
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
