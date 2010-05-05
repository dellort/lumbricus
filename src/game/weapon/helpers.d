//sorry; didn't know where else to put the stuff
module game.weapon.helpers;

import common.scene;
import game.controller;
import game.core;
import game.sprite;
import game.temp : GameZOrder;
import game.worm;
import game.wcontrol;
import physics.world;
import utils.time;
import utils.vector2;
import utils.misc;
import utils.color;

//classes derived from this extend the functionality of a Sprite
//  the instance will die when the Sprite disappears
class SpriteHandler : GameObject {
    protected Sprite mParent;

    this(Sprite parent) {
        argcheck(parent);
        mParent = parent;
        super(parent.engine, "spritehandler");
        internal_active = true;
    }

    bool activity() {
        return internal_active;
    }

    override void simulate() {
        super.simulate();
        if (!mParent.visible())
            kill();
    }
}

//will call a delegate when the parent sprite is no longer moving
//(independant of gluing)
class StuckTrigger : SpriteHandler {
    private {
        struct DeltaSample {
            Time t;
            float delta = 0;
        }

        Vector2f mPosOld;
        DeltaSample[] mSamples;
        bool mActivated = false;
        Time mTriggerDelay;
        float mTreshold;
        bool mMultiple;
    }
    void delegate(StuckTrigger sender, Sprite sprite) onTrigger;

    this(Sprite parent, Time triggerDelay, float treshold, bool multiple) {
        super(parent);
        mPosOld = mParent.physics.pos;
        mTriggerDelay = triggerDelay;
        mTreshold = treshold;
        mMultiple = multiple;
    }

    //adds a position-change sample to the list (with timestamp)
    private void addSample(float delta) {
        Time t = engine.gameTime.current;
        foreach (ref s; mSamples) {
            if (t - s.t > mTriggerDelay) {
                //found invalid sample -> replace
                s.t = t;
                s.delta = delta;
                //one triggerDelay has passed
                mActivated = true;
                return;
            }
        }
        //no invalid sample found -> allocate new
        DeltaSample s;
        s.t = t;
        s.delta = delta;
        mSamples ~= s;
    }

    //sums position changes within trigger_delay interval
    //older samples are ignored
    private float integrate() {
        Time t = engine.gameTime.current;
        float ret = 0.0f;
        int c;
        foreach (ref s; mSamples) {
            if (t - s.t <= mTriggerDelay) {
                ret += s.delta;
                c++;
            }
        }
        return ret;
    }

    private void trigger() {
        if (onTrigger) {
            onTrigger(this, mParent);
        }
    }

    override void simulate() {
        super.simulate();
        Vector2f p = mParent.physics.pos;
        addSample((mPosOld-p).length);
        mPosOld = p;
        if (integrate() < mTreshold && mActivated) {
            //execute trigger event (which maybe blows the projectile)
            trigger();
            if (mMultiple) {
                //reset
                mActivated = false;
                mSamples = null;
            } else {
                kill();
            }
        }
    }
}

class ControlRotate : SpriteHandler, Controllable {
    private {
        WormControl mMember;
        Vector2f mMoveVector;
        float mDirection, mRotateSpeed, mThrust;
    }

    this(Sprite parent, float rotateSpeed, float thrust)
    {
        super(parent);
        auto ctl = engine.singleton!(GameController)();
        mMember = ctl.controlFromGameObject(mParent, true);
        mMember.pushControllable(this);
        //default to parent velocity (can be changed later)
        mDirection = mParent.physics.velocity.toAngle();
        mRotateSpeed = rotateSpeed;
        mThrust = thrust;
        setForce();
    }

    float direction() {
        return mDirection;
    }
    void direction(float dir) {
        mDirection = dir;
        setForce();
    }

    override protected void updateInternalActive() {
        if (!internal_active) {
            mParent.physics.selfForce = Vector2f(0);
            mMember.releaseControllable(this);
        }
    }

    override void simulate() {
        //die as sprite dies
        if (!mParent.visible())
            kill();
        float deltaT = engine.gameTime.difference.secsf;
        mDirection += mMoveVector.x * mRotateSpeed * deltaT;
        setForce();
        super.simulate();
    }

    private void setForce() {
        mParent.physics.selfForce = Vector2f.fromPolar(1.0f, mDirection)
            * mThrust;
    }

    //-- Controllable implementation

    bool fire(bool keyDown) {
        return false;
    }

    bool jump(JumpMode j) {
        return false;
    }

    bool move(Vector2f m) {
        mMoveVector = m;
        return true;
    }

    Sprite getSprite() {
        return mParent;
    }

    //-- end Controllable
}

//now used by Lua weapon; no point in changing this
class WormSelectHelper : GameObject {
    private {
        TeamMember mMember;
    }

    this(GameCore eng, TeamMember member) {
        super(eng, "wormselecthelper");
        internal_active = true;
        mMember = member;
        assert(!!mMember);
    }

    bool activity() {
        return internal_active;
    }

    override void simulate() {
        super.simulate();
        //xxx: we just need the 1-frame delay for this because initialStep() is
        //     called from doFire, which will set mMember.mWormAction = true
        //     afterwards and would conflict with the code below
        mMember.team.allowSelect = true;
        mMember.control.resetActivity();
        kill();
    }
}

//non-deterministic, transient, self-removing shoot effect
//xxx: this used to be derived from GameObject
//     now this functionality got lost: bool activity() { return active; }
//     if it's needed again, let RayShooter wait until end-time
class RenderLaser : SceneObject {
    private {
        GameCore base;
        Vector2i[2] mP;
        Time mStart, mEnd;
        Color[] mColors;
    }

    this(GameCore a_engine, Vector2f p1, Vector2f p2, Time duration,
        Color[] colors)
    {
        base = a_engine;
        zorder = GameZOrder.Effects;
        base.scene.add(this);
        mP[0] = toVector2i(p1);
        mP[1] = toVector2i(p2);
        mStart = base.interpolateTime.current;
        mEnd = mStart + duration;
        mColors = colors;
    }

    override void draw(Canvas c) {
        auto cur = base.interpolateTime.current;
        assert(cur >= mStart);
        if (cur >= mEnd) {
            removeThis();
            return;
        }
        float pos = 1.0*(cur - mStart).msecs / (mEnd - mStart).msecs;
        // [0.0, 1.0] onto range [colors[0], ..., colors[$-1]]
        pos *= mColors.length;
        int segi = cast(int)(pos);
        float segmod = pos - segi;
        //assert(segi >= 0 && segi < mColors.length-1);
        if (!(segi >= 0 && segi < mColors.length-1)) {
            removeThis();
            return;
        }
        //linear interpolation between these
        auto col = mColors[segi] + (mColors[segi+1]-mColors[segi])*segmod;
        c.drawLine(mP[0], mP[1], col);
    }
}
