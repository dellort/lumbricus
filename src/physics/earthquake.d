module physics.earthquake;

import utils.reflection;
import utils.time;
import utils.vector2;
import random = utils.random;

import physics.base;
import physics.force;
import physics.physobj;

import math = stdx.math;

const Time cEarthQuakeChangeTime = timeMsecs(200);

//causes a one-frame earthquake with the strength accumulated by
//addEarthQuakePerFrameStrength, use EarthQuakeDegrader to generate strength
//actual force vector will randomly change over time
//works best if used as singleton
class EarthQuakeForce : PhysicForce {
    //valid per frame
    private float mEarthQuakeStrength = 0;
    //last valid value
    private float mLastStrength = 0;
    //the force is updated in intervals according to the strength
    //reason: would look silly if it changed each frame
    private Vector2f mEarthQuakeImpulse;
    // a bit silly/dangerous: sum up the deltaTs until "change" time is
    // reached; initialized with NaN to trigger change in first simulate()
    private float mEarthQuakeLastChangeTime;
    private bool mNeedForceUpdate = true;

    //is there any force to apply?
    private bool mActive = false;

    this () {
    }
    this (ReflectCtor c) {
    }

    //when something wants to cause an earth quake, it needs to update this
    //each frame (in PhysicBase.simulate()!)
    void addEarthQuakePerFrameStrength(float force) {
        mEarthQuakeStrength += force;
    }

    float earthQuakeStrength() {
        return mLastStrength;
    }

    //can't update the force directly, as EarthQuakeDegraders may add strength
    //before and after this
    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);
        mNeedForceUpdate = true;
    }

    //calculate the current frame's earthquake force
    private void updateImpulse(float deltaT) {
        mActive = false;
        scope(exit) {
            //reset per-frame strength
            mLastStrength = mEarthQuakeStrength;
            mEarthQuakeStrength = 0;
            //set updated flag
            mNeedForceUpdate = false;
        }
        if (mEarthQuakeStrength <= float.epsilon) {
            mEarthQuakeImpulse = Vector2f.init;
            mEarthQuakeLastChangeTime = float.init;
            return;
        }

        mActive = true;
        mEarthQuakeLastChangeTime += deltaT;

        //NOTE: don't return if mEathQuakeLastChangeTime is NaN
        if (mEarthQuakeLastChangeTime < cEarthQuakeChangeTime.secs())
            return;

        //new direction
        //xxx: undeterministic randomness
        //using an angle here is a simple way to create a normalized vector
        mEarthQuakeImpulse = Vector2f.fromPolar(1.0f,
            world.rnd.nextDouble() * math.PI * 2.0f) * mEarthQuakeStrength;
        mEarthQuakeLastChangeTime = 0;
    }

    //this _force_ generator applies an impulse, hope this is correct
    void applyTo(PhysicObject o, float deltaT) {
        //xxx sorry, but this needs to be called after all degrader's simulate
        if (mNeedForceUpdate)
            updateImpulse(deltaT);
        if (!mActive)
            return;
        //influence on objects disabled
        return;
        //xxx should be applied only to objects on the ground (this is an
        //    _earth_quake, not a skyquake, but this requires major changes
        //    in PhysicObject
        o.addImpulse(mEarthQuakeImpulse);
    }
}

//in seconds, change rate for degrading the earthquake
const cEarthQuakeDegradeInterval = 1.0;

//causes an EarthQuake and also is able to degrade it down by time
class EarthQuakeDegrader : PhysicBase {
    private {
        float mDegrade;
        float mStrength;
        //silly, cf. same member in class EarthQuake
        //maybe should be changed, but with a constant frame rate, it's ok
        float mLastChange = 0;
        EarthQuakeForce mForce;
    }

    //1.0f means forever
    this(float strength, float degrade, EarthQuakeForce eqForce) {
        mStrength = strength;
        mDegrade = degrade;
        mForce = eqForce;
        assert(!!mForce);
    }

    this (ReflectCtor c) {
    }

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);

        mForce.addEarthQuakePerFrameStrength(mStrength);

        mLastChange += deltaT;

        if (mLastChange < cEarthQuakeDegradeInterval)
            return;

        mStrength *= mDegrade;

        //if strength is too small, die
        //what would be a good value to trigger destruction?
        if (mStrength < 0.01)
            dead = true;

        mLastChange = 0;
    }
}
