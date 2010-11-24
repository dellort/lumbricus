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
import common.restypes.animation;

//rotate around center, time or p1
class AnimEffectRotate : AnimEffect {
    AnimEffectParam param;
    float multiplier = 1.0f;

    this(Animation parent, ConfigNode config) {
        super(parent);
        stringToType(param, config.getStringValue("p", "time"));
        multiplier = config.getValue("m", multiplier);
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        float f;
        switch (param) {
            case AnimEffectParam.p1:
                f = p.p[0] / 360.0f;
                break;
            default:
                f = relTime(t);
        }
        eff.rotate = f * math.PI * 2 * multiplier;
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
        float f = p.p[0] / 360.0f;
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
    bool inverse;
    AnimEffectParam param;

    this(Animation parent, ConfigNode config) {
        super(parent);
        dest = config.getValue("dest", dest);
        inverse = config.getValue("inv", inverse);
        stringToType(param, config.getStringValue("p", "time"));
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        float f;
        switch (param) {
            case AnimEffectParam.p2:
                f = p.p[1] / 100f;
                break;
            default:
                f = relTime(t);
        }
        if (inverse)
            f = 1.0f - f;
        eff.color = Color(1f) * (1f - f) + dest * f;
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("fade");
    }
}

//shrink from scale = 1.0 to scale = 0.0 (invisible)
class AnimEffectShrink : AnimEffect {
    bool inverse;

    this(Animation parent, ConfigNode config) {
        super(parent);
        inverse = config.getValue("inv", inverse);
    }

    override void effect(ref Vector2i pos, ref AnimationParams p, Time t,
        ref BitmapEffect eff)
    {
        //time only
        float f = relTime(t);
        if (!inverse)
            f = 1.0f - f;
        eff.scale.x = eff.scale.y = f;
    }

    static this() {
        AnimEffectFactory.register!(typeof(this))("shrink");
    }
}
