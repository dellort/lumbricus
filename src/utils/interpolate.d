module utils.interpolate;

import utils.time;
import math = tango.math.Math;

typedef int Missing;

//this is a try to get rid of the code duplication (although it's too late)
//it's rather trivial, but annoying
//when started, it interpolates from one value to another in a given time span
//T must be a scalar, like float or int
//all fields are read-only (in gameframe I have some code for changing "targets")

///Interpolate according to a mapping function
///Params:
///  FN = mapping function
///  FN_1 = inverse mapping function
///  T = scalar type, like float or int
struct InterpolateFnTime(T, alias FN, alias FN_1 = Missing) {
    Time startTime, duration = Time.Never;
    T start;
    T target;
    private T doneValue;
    Time delegate() currentTimeDg;

    Time currentTime() {
        if (!currentTimeDg)
            return timeCurrentTime();
        return currentTimeDg();
    }

    ///Init interpolation in [a_start, a_target] over a_duration, starting now
    void init(Time a_duration, T a_start, T a_target) {
        startTime = currentTime();
        duration = a_duration;
        start = a_start;
        target = a_target;
        //not all functions have to end at f(x) = 1.0f
        doneValue = start + cast(T)((target - start) * FN(1.0f));
    }

    ///init as if the animation is done and has stopped; it's like a_duration
    /// has already passed after this call, and value() will always be a_target
    ///useful with revert()
    void init_done(Time a_duration, T a_start, T a_target) {
        init(a_duration, a_start, a_target);
        startTime -= a_duration;
    }

    ///Return the current value (will sample time)
    T value() {
        auto d = currentTime() - startTime;
        if (d >= duration) {
            return doneValue;
        }
        //have to scale it without knowing what datatype it is
        return start + cast(T)((target - start)
            * FN(cast(float)d.msecs / duration.msecs));
    }

    Time endTime() {
        return startTime + duration;
    }

    ///return if the value is still changing (false when this is uninitialized)
    bool inProgress() {
        return initialized && currentTime() < startTime + duration;
    }

//we need the inverse function of FN for this
static if (!is(FN_1 == Missing)) {
    ///calculate startTime so that value() will return a_value
    ///must call init() before
    void set(T a_value) {
        assert(duration != Time.Never, "Call init() before");
        float progress = cast(float)(a_value - start) / (target - start);
        startTime = currentTime() - duration * FN_1(progress);
    }

    ///Change parameters without losing current value
    void setParams(Time a_duration, T a_start, T a_target) {
        T cur = value();
        init(a_duration, a_start, a_target);
        set(cur);
    }

    ///Same as above, but doesn't change duration
    void setParams(T a_start, T a_target) {
        setParams(duration, a_start, a_target);
    }

    ///restart with same duration, but swapped start/target values
    void revert() {
        setParams(target, start);
    }
}

    ///start interpolating again (if init() has been called before)
    void restart() {
        assert(duration != Time.Never, "Call init() before");
        startTime = currentTime();
    }

    //reset everything to init (except currentTimeDg)
    void reset() {
        start = target = T.init;
        startTime = duration = Time.Never;
    }

    bool initialized() {
        return duration != Time.Never;
    }
}


//----------------------------------------------------------------------

float interpLinear(float x) {
    return x;
}

//for convenience
template InterpolateLinear(T) {
    alias InterpolateFnTime!(T, interpLinear, interpLinear) InterpolateLinear;
}


//----------------------------------------------------------------------

//x, result = [0,1] -> [0,1], exponential-like curve
//A = steepness of curve
//  A == 0: linear
//  A > 0: | 0.0 fast ... slow 1.0 |
//  A < 0: | 0.0 slow ... fast 1.0 |
float interpExponential(float A)(float x) {
    static if(A == 0) {
        return x;
    } else {
        //this graphs amazingly similar to the old one, but is
        //  much easier to invert
        //only drawback is it fails for A == 0, use interpLinear() then
        return (1.0f - (math.exp(-A * x))) / (1.0f - (math.exp(-A)));
    }
}
float interpExponential_1(float A)(float x) {
    static if(A == 0) {
        return x;
    } else {
        //thx maple ;)
        return 1.0f - math.log(x + (1.0f - x)*math.exp(A))/A;
    }
}

//another one to save you the typing
template InterpolateExp(T, float A = 4.5f) {
    alias InterpolateFnTime!(T, interpExponential!(A),
        interpExponential_1!(A)) InterpolateExp;
}


//----------------------------------------------------------------------

//looks like this:   | 0.0 slow ... fast 0.5 fast ... slow 1.0 |
float interpExponential2(float A)(float x) {
    auto dir = x < 0.5f;
    auto res = (interpExponential!(A)(math.abs(2*x-1)) + 1) / 2;
    return dir ? 1 - res : res;
}
float interpExponential2_1(float A)(float x) {
    auto dir = x < 0.5f;
    //xxx: is it really that easy? looks right in the plotter
    auto res = (interpExponential_1!(A)(math.abs(2*x-1)) + 1) / 2;
    return dir ? 1 - res : res;
}

template InterpolateExp2(T, float A = 4.5f) {
    alias InterpolateFnTime!(T, interpExponential2!(A),
        interpExponential2_1!(A)) InterpolateExp2;
}
