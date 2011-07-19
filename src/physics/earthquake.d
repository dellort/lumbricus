module physics.earthquake;

import utils.time;
import utils.vector2;
import random = utils.random;
import utils.interpolate;

import physics.base;
import physics.force;
import physics.physobj;

import std.math;

enum Time cEarthQuakeChangeTime = timeMsecs(200);

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
    //should objects be made to bounce around? (otherwise, just for the effect)
    private bool mDoImpulse;

    this (bool doImpulse) {
        mDoImpulse = doImpulse;
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
        if (mDoImpulse) {
            mEarthQuakeImpulse = Vector2f.fromPolar(1.0f,
                world.rnd.nextDouble() * PI * 2.0f) * mEarthQuakeStrength;
        }
        mEarthQuakeLastChangeTime = 0;
    }

    //this _force_ generator applies an impulse, hope this is correct
    void applyTo(PhysicObject o, float deltaT) {
        //xxx sorry, but this needs to be called after all degrader's simulate
        if (mNeedForceUpdate)
            updateImpulse(deltaT);
        if (!mActive)
            return;
        if (mDoImpulse) {
            //unglue, and throw around if on the ground
            o.doUnglue();
            if (o.onSurface)
                o.addImpulse(mEarthQuakeImpulse);
        }
    }
}

//in seconds, change rate for degrading the earthquake
enum cEarthQuakeDegradeInterval = 1.0;

//causes an EarthQuake and also is able to degrade it down by time
class EarthQuakeDegrader : PhysicBase {
    private {
        float mStrength;
        bool mDegrade;
        EarthQuakeForce mForce;
        InterpolateExp!(float, 1.0f) mInterp;
        Time mTime;
    }

    //degrade = true for exponential degrade (else ends abruptly)
    this(float strength, Time duration, bool degrade, EarthQuakeForce eqForce) {
        mInterp.currentTimeDg = &getTime;
        mStrength = strength;
        mDegrade = degrade;
        mInterp.init(duration, mStrength, 0);
        mForce = eqForce;
        assert(!!mForce);
    }

    private Time getTime() {
        return mTime;
    }

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);

        //xxx there's no physics timesource (yet?), so do it manually
        mTime += timeSecs(deltaT);

        float s = mInterp.value();
        if (mDegrade)
            mStrength = s;

        mForce.addEarthQuakePerFrameStrength(mStrength);

        if (!mInterp.inProgress())
            dead = true;
    }
}
