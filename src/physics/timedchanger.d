module physics.timedchanger;

import tango.math.IEEE : copysign;
import utils.reflection;
import utils.vector2;

import physics.base;

//base template for changers that will update a value over time until a
//specified target is reached
//use this as mixin and implement updateStep(float deltaT) (strange D world...)
template PhysicTimedChanger(T) {
    //current value
    protected T mValue;
    //do a change over time to target value, changing with changePerSec/s
    T target;
    T changePerSec;
    //callback that is executed when the real value changes
    void delegate(T newValue) onValueChange;

    this(T startValue, void delegate(T newValue) valChange) {
        onValueChange = valChange;
        value = startValue;
    }

    this (ReflectCtor c) {
    }

    void value(T v) {
        mValue = v;
        target = v;
        doValueChange();
    }
    T value() {
        return mValue;
    }

    bool done() {
        return mValue == target;
    }

    private void doValueChange() {
        if (onValueChange)
            onValueChange(mValue);
    }

    protected void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mValue != target) {
            //this is expensive, but only executed when the value is changing
            updateStep(deltaT);
            doValueChange();
        }
    }
}

class PhysicTimedChangerFloat : PhysicBase {
    mixin PhysicTimedChanger!(float);

    protected void updateStep(float deltaT) {
        float diff = target - mValue;
        mValue += copysign(changePerSec*deltaT,diff);
        float diffn = target - mValue;
        float sgn = diff*diffn;
        if (sgn < 0)
            mValue = target;
    }
}

class PhysicTimedChangerVector2f : PhysicBase {
    mixin PhysicTimedChanger!(Vector2f);

    protected void updateStep(float deltaT) {
        Vector2f diff = target - mValue;
        mValue.x += copysign(changePerSec.x*deltaT,diff.x);
        mValue.y += copysign(changePerSec.y*deltaT,diff.y);
        Vector2f diffn = target - mValue;
        Vector2f sgn = diff.mulEntries(diffn);
        if (sgn.x < 0)
            mValue.x = target.x;
        if (sgn.y < 0)
            mValue.y = target.y;
    }
}
