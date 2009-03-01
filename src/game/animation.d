module game.animation;

import common.scene;
import common.common;
import framework.framework;
import common.resset;
import common.restypes.bitmap;
import common.restypes.frames;
import utils.configfile;
import utils.misc;
import utils.array;
import utils.perf;
import utils.time;
import utils.log;
import utils.math;
import math = tango.math.Math;

public import common.animation;

alias Resource!(Animation) AnimationResource;

static this() {
    //documentation on this stuff see implementations

    gAnimationParamConverters["none"] = &paramConvertNone;
    gAnimationParamConverters["step3"] = &paramConvertStep3;
    gAnimationParamConverters["twosided"] = &paramConvertTwosided;
    gAnimationParamConverters["twosided_inv"] = &paramConvertTwosidedInv;
    gAnimationParamConverters["rot360"] = &paramConvertFreeRot;
    gAnimationParamConverters["rot360inv"] = &paramConvertFreeRotInv;
    gAnimationParamConverters["rot180"] = &paramConvertFreeRot2;
    gAnimationParamConverters["rot180_2"] = &paramConvertFreeRot2_2;
    gAnimationParamConverters["linear100"] = &paramConvertLinear100;
}

//return the index of the angle in "angles" which is closest to "angle"
//all units in degrees, return values is always an index into angles
private uint pickNearestAngle(int[] angles, int iangle) {
    //pick best angle (what's nearer)
    uint closest;
    float angle = iangle/180.0f*math.PI;
    float cur = float.max;
    foreach (int i, int x; angles) {
        auto d = angleDistance(angle,x/180.0f*math.PI);
        if (d < cur) {
            cur = d;
            closest = i;
        }
    }
    return closest;
}

//param converters

//map with wrap-around
private int map(float val, float rFrom, int rTo) {
    return cast(int)(realmod(val + 0.5f*rFrom/rTo,rFrom)/rFrom * rTo);
}

//map without wrap-around, assuming val will not exceed rFrom
private int map2(float val, float rFrom, int rTo) {
    return cast(int)((val + 0.5f*rFrom/rTo)/rFrom * (rTo-1));
}

//and finally the DWIM (Do What I Mean) version of map: anything can wrap around
private int map3(float val, float rFrom, int rTo) {
    return cast(int)(realmod(val + 0.5f*rFrom/rTo + rFrom,rFrom)/rFrom * rTo);
}

//default
private int paramConvertNone(int angle, int count) {
    return 0;
}
//expects count to be 6 (for the 6 angles)
private int paramConvertStep3(int angle, int count) {
    static int[] angles = [180,180+45,180-45,0,0-45,0+45];
    return pickNearestAngle(angles, angle);
}
//expects count to be 2 (two sides)
private int paramConvertTwosided(int angle, int count) {
    return angleLeftRight(cast(float)(angle/180.0f*math.PI), 0, 1);
}
private int paramConvertTwosidedInv(int angle, int count) {
    return angleLeftRight(cast(float)(angle/180.0f*math.PI), 1, 0);
}
//360 degrees freedom
private int paramConvertFreeRot(int angle, int count) {
    return map(-angle+270, 360.0f, count);
}
//360 degrees freedom, inverted spinning direction
private int paramConvertFreeRotInv(int angle, int count) {
    return map(-(-angle+270), 360.0f, count);
}
//180 degrees, -90 (down) to +90 (up)
//(overflows, used for weapons, it's hardcoded that it can use 180 degrees only)
private int paramConvertFreeRot2(int angle, int count) {
    //assert(angle <= 90);
    //assert(angle >= -90);
    return map2(angle+90.0f,180.0f,count);
}

//for the aim not-animation
private int paramConvertFreeRot2_2(int angle, int count) {
    return map3(angle+180,180.0f,count);
}

//0-100 mapped directly to animation frames with clipping
//(the do-it-yourself converter)
private int paramConvertLinear100(int value, int count) {
    value = clampRangeC(value, 0, 100);
    return cast(int)(cast(float)value/101.0f * count);
}
