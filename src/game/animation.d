module game.animation;

import framework.drawing;
import utils.misc;
import utils.math;
import utils.time;
import utils.configfile;
import utils.strparser;
import utils.color;
import math = tango.math.Math;

public import common.animation;

static this() {
    //documentation on this stuff see implementations

    gAnimationParamConverters["none"] = &paramConvertNone;
    gAnimationParamConverters["direct"] = &paramConvertDirect;
    gAnimationParamConverters["step3"] = &paramConvertStep3;
    gAnimationParamConverters["twosided"] = &paramConvertTwosided;
    gAnimationParamConverters["twosided_inv"] = &paramConvertTwosidedInv;
    gAnimationParamConverters["rot360"] = &paramConvertFreeRot;
    gAnimationParamConverters["rot360inv"] = &paramConvertFreeRotInv;
    gAnimationParamConverters["rot360_90"] = &paramConvertFreeRotPlus90;
    gAnimationParamConverters["rot180"] = &paramConvertFreeRot180;
    gAnimationParamConverters["rot180_2"] = &paramConvertFreeRot180_2;
    gAnimationParamConverters["rot90"] = &paramConvertFreeRot90;
    gAnimationParamConverters["rot60"] = &paramConvertFreeRot60;
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
//no change
private int paramConvertDirect(int angle, int count) {
    return clampRangeO(angle, 0, count);
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

private int paramConvertFreeRotPlus90(int angle, int count) {
    return map(angle, 360.0f, count);
}

//180 degrees, -90 (down) to +90 (up)
//(overflows, used for weapons, it's hardcoded that it can use 180 degrees only)
private int paramConvertFreeRot180(int angle, int count) {
    //assert(angle <= 90);
    //assert(angle >= -90);
    return map2(angle+90.0f,180.0f,count);
}

//for the aim not-animation
private int paramConvertFreeRot180_2(int angle, int count) {
    return map3(angle+180,180.0f,count);
}

//90 degrees, -45 (down) to +45 (up)
private int paramConvertFreeRot90(int angle, int count) {
    angle = clampRangeC(angle, -45, 45);
    return map2(angle+45.0f,90.0f,count);
}

//60 degrees, -30 (down) to +30 (up)
private int paramConvertFreeRot60(int angle, int count) {
    angle = clampRangeC(angle, -30, 30);
    return map2(angle+30.0f,60.0f,count);
}

//0-100 mapped directly to animation frames with clipping
//(the do-it-yourself converter)
private int paramConvertLinear100(int value, int count) {
    value = clampRangeC(value, 0, 100);
    return cast(int)(cast(float)value/101.0f * count);
}


//rotate around center, time or p1
class AnimEffectRotate : AnimEffect {
    AnimEffectParam param;

    this(Animation parent, ConfigNode config) {
        super(parent);
        stringToType(param, config.getStringValue("p", "time"));
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        float f;
        switch (param) {
            case AnimEffectParam.p1:
                f = p.p1 / 360.0f;
                break;
            default:
                f = relTime(t);
        }
        eff.rotate = f * math.PI * 2;
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("rotate");
    }
}

//mirror along y axis according to p1
class AnimEffectMirrorY : AnimEffect {
    this(Animation parent, ConfigNode config) {
        super(parent);
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        //only p1 for now
        float f = p.p1 / 360.0f;
        eff.mirrorY = mymath.angleLeftRight(f * math.PI * 2, false, true);
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("mirrory");
    }
}

//bounce up and down like a bouncing ball
class AnimEffectBounceUp : AnimEffect {
    float bounceHeight = 40f;

    this(Animation parent, ConfigNode config) {
        super(parent);
        bounceHeight = config.getValue("h", bounceHeight);
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        //time only
        float f = relTime(t);
        //1 - (2x - 1)^2   (like trajectory)
        pos.y -= cast(int)(bounceHeight
            * (1f - (2f * f - 1f) * (2f * f - 1f)));
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("bounceup");
    }
}

//alternated stretching on x and y; scale factor in range [1-sx, 1+sx]
class AnimEffectStretch : AnimEffect {
    float sx = 0.2f;
    float sy = 0.2f;

    this(Animation parent, ConfigNode config) {
        super(parent);
        sx = config.getValue("sx", sx);
        sy = config.getValue("sy", sy);
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        //time only
        float f = relTime(t);
        float c = math.cos(f * math.PI * 2);
        eff.scale.x = sx * c + 1.0f;
        eff.scale.y = -sy * c + 1.0f;
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("stretch");
    }
}

//fade to color over time or 0-100 p2
class AnimEffectFade : AnimEffect {
    Color dest = Color(1,1,1,0);  //transparent
    AnimEffectParam param;

    this(Animation parent, ConfigNode config) {
        super(parent);
        dest = config.getValue("dest", dest);
        stringToType(param, config.getStringValue("p", "time"));
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        float f;
        switch (param) {
            case AnimEffectParam.p2:
                f = p.p2 / 100f;
                break;
            default:
                f = relTime(t);
        }
        eff.color = Color(1f) * (1f - f) + dest * f;
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("fade");
    }
}
