module physics.earthquake;

import physics.base;

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
    }

    //1.0f means forever
    this(float strength, float degrade) {
        mStrength = strength;
        mDegrade = degrade;
    }

    override /+package+/ void simulate(float deltaT) {
        world.addEarthQuakePerFrameStrength(mStrength);

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
