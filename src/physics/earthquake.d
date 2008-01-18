module physics.earthquake;

import utils.vector2;
import random = utils.random;

import physics.base;
import physics.force;
import physics.physobj;

//causes a one-frame earthquake with the strength accumulated by
//addEarthQuakePerFrameStrength, use EarthQuakeDegrader to generate strength
//actual force vector will randomly change over time
//works best if used as singleton
class EarthQuakeForce : PhysicForce {
    //valid per frame
    private float mEarthQuakeStrength = 0;
    //the force is updated in intervals according to the strength
    //reason: would look silly if it changed each frame
    private Vector2f mEarthQuakeForce;
    // a bit silly/dangerous: sum up the deltaTs until "change" time is
    // reached; initialized with NaN to trigger change in first simulate()
    private float mEarthQuakeLastChangeTime;
    private bool mNeedForceUpdate = true;

    //when something wants to cause an earth quake, it needs to update this
    //each frame (in PhysicBase.simulate()!)
    void addEarthQuakePerFrameStrength(float force) {
        mEarthQuakeStrength += force;
    }

    float earthQuakeStrength() {
        return mEarthQuakeStrength;
    }

    //can't update the force directly, as EarthQuakeDegraders may add strength
    //before and after this
    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);
        mNeedForceUpdate = true;
    }

    //calculate the current frame's earthquake force
    private void updateForce(float deltaT) {
        scope(exit) {
            //reset per-frame strength
            mEarthQuakeStrength = 0;
            //set updated flag
            mNeedForceUpdate = false;
        }
        if (mEarthQuakeStrength <= float.epsilon) {
            mEarthQuakeForce = Vector2f.init;
            mEarthQuakeLastChangeTime = float.init;
            return;
        }

        mEarthQuakeLastChangeTime += deltaT;

        //NOTE: don't return if mLastChange is NaN
        //this constant is the update-radnom-vector-change time
        if (mEarthQuakeLastChangeTime < 0.2)
            return;

        //new direction
        //xxx: undeterministic randomness
        //using an angle here is a simple way to create a normalized vector
        mEarthQuakeForce = Vector2f.fromPolar(1.0f,
            random.random() * PI * 2.0f) * mEarthQuakeStrength;
        mEarthQuakeLastChangeTime = 0;
    }

    Vector2f getAccelFor(PhysicObject o, float deltaT) {
        //xxx sorry, but this needs to be called after all degrader's simulate
        if (mNeedForceUpdate)
            updateForce(deltaT);
        //xxx should be applied only to objects on the ground (this is an
        //    _earth_quake, not a skyquake, but this requires major changes
        //    in PhysicObject
        return mEarthQuakeForce;
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

    override /+package+/ void simulate(float deltaT) {
        super.simulate(deltaT);

        mForce.addEarthQuakePerFrameStrength(mStrength);

        mLastChange += deltaT;

        if (mLastChange < cEarthQuakeDegradeInterval)
            return;

        mStrength *= mDegrade;

        //if strength is too small, die
        //what would be a good value to trigger destruction?
        if (mStrength < 0.2)
            dead = true;

        mLastChange = 0;
    }
}
