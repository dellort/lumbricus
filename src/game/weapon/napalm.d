module game.weapon.napalm;

import framework.framework;
import game.animation;
import game.action;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.spriteactions;
import game.weapon.weapon;
import game.weapon.projectile;
import physics.world;
import std.math;
import str = std.string;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.log;
import utils.random;
import utils.randval;
import utils.factory;
import utils.reflection;

class NapalmSprite : ProjectileSprite {
    private {
        NapalmSpriteClass myclass;
        Time mLightupTime;              //Time when decaying started
        Time mRepeatDelay;              //delay until next damage
        Time mLastDmg;                  //Time the last damage was caused
        float mDecaySecs;               //seconds for full decay
        NapalmSequenceUpdate mNUpdate;  //sequence update, to report decay
        float mDecayPerc = 1.0f;        //cache for decay percentage
    }

    //percentage of decayTime that remains, negative if passed
    private float decayPercent() {
        return (mDecaySecs - (engine.gameTime.current - mLightupTime).secsf)
            / mDecaySecs;
    }

    //call to reset decaying (like after an explosion)
    private void lightUp() {
        mLightupTime = engine.gameTime.current;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        float dp = decayPercent();
        //adjust particle radius to decay
        if (dp <= 0.25 && mDecayPerc > 0.25)
            physics.posp = myclass.physSmall;
        else if (dp <= 0.5 && mDecayPerc > 0.5)
            physics.posp = myclass.physMedium;
        else if (dp > 0.5 && mDecayPerc <= 0.5)
            physics.posp = currentState.physic_properties;

        //check for death
        mDecayPerc = dp;
        if (mDecayPerc < 0)
            die();

        //cause some damage
        //NOTE: not using action stuff because of custom damage, and
        //      for optimization
        //xxx this has to change for multi-round napalm or worms pushed up
        if (engine.gameTime.current - mLastDmg >= mRepeatDelay) {
            float dmg = myclass.damage.sample*(0.25+mDecayPerc*0.75);
            engine.explosionAt(physics.pos, dmg, this);
            mLastDmg += mRepeatDelay;
            mRepeatDelay = timeSecs(myclass.repeatDelay.sample);
        }
    }

    override protected void createSequenceUpdate() {
        mNUpdate = new NapalmSequenceUpdate();
        seqUpdate = mNUpdate;
    }

    override protected void fillAnimUpdate() {
        super.fillAnimUpdate;
        //0: full size, 100: tiny
        mNUpdate.decay = clampRangeC(100-cast(int)(mDecayPerc*80), 0, 100);
    }

    override protected void physUpdate() {
        super.physUpdate();
        //reset decay if particle got fast enough (this has to do,
        // no way to determine if it was hit by an explosion)
        if (physics.velocity.length > myclass.lightupVelocity)
            lightUp();
    }

    this(GameEngine engine, NapalmSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        mDecaySecs = myclass.decayTime.sample;
        mRepeatDelay = timeSecs(myclass.initialDelay.sample);
        mLastDmg = engine.gameTime.current;
        lightUp();
    }

    this (ReflectCtor c) {
        super(c);
    }
}

class NapalmSpriteClass : ProjectileSpriteClass {
    RandomFloat damage, decayTime, initialDelay, repeatDelay;
    //can't change initState.physic_properties, so reduced radius is put here
    POSP physMedium, physSmall;
    float lightupVelocity = 400;

    override NapalmSprite createSprite() {
        return new NapalmSprite(engine, this);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        damage = RandomFloat(config.getStringValue("damage","5"), engine.rnd);
        initialDelay = RandomFloat(config.getStringValue("initial_delay","0"),
            engine.rnd);
        repeatDelay = RandomFloat(config.getStringValue("repeat_delay","0.5"),
            engine.rnd);
        decayTime = RandomFloat(config.getStringValue("decay_time","5"),
            engine.rnd);
        physMedium = initState.physic_properties.copy;
        physMedium.radius = config.getFloatValue("radius_m", 2);
        physSmall = initState.physic_properties.copy;
        physSmall.radius = config.getFloatValue("radius_s", 1);
        lightupVelocity = config.getFloatValue("lightup_velocity",
            lightupVelocity);
    }

    this(GameEngine e, char[] r) {
        super(e, r);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("napalm_mc");
    }
}