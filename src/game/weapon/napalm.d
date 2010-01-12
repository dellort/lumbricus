module game.weapon.napalm;

import framework.framework;
import game.actionsprite;
import game.game;
import game.gfxset;
import game.gobject;
import game.particles;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import game.weapon.projectile;
import physics.world;
import tango.math.Math;
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
        float mDecayPerc = 1.0f;        //cache for decay percentage
    }

    //percentage of decayTime that remains, negative if passed
    private float decayPercent() {
        float p = (mDecaySecs - (engine.gameTime.current - mLightupTime).secsf)
            / mDecaySecs;
        if (p > 0)
            //faster decay for tiny napalm
            return sqrt(p);
        else
            return p;
    }

    //call to reset decaying (like after an explosion)
    private void lightUp() {
        mLightupTime = engine.gameTime.current;
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);

        //reset decay if particle got fast enough (this has to do,
        // no way to determine if it was hit by an explosion)
        if (physics.velocity.length > myclass.lightupVelocity)
            lightUp();

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
        //xxx this has to change for multi-turn napalm or worms pushed up
        if (engine.gameTime.current - mLastDmg >= mRepeatDelay) {
            float dmg = myclass.damage.sample(engine.rnd)
                * (0.25 + mDecayPerc*0.75);
            engine.explosionAt(physics.pos, dmg, this, false);
            mLastDmg += mRepeatDelay;
            mRepeatDelay = myclass.repeatDelay.sample(engine.rnd);
        }
    }

    override protected void fillAnimUpdate() {
        super.fillAnimUpdate;
        //0: full size, 100: tiny
        graphic.lifePercent = clampRangeC(100.0f-mDecayPerc*80, 0.0f, 100.0f);
    }

    override void waterStateChange() {
        if (isUnderWater && myclass.emitOnWater) {
            //emit some particles when we die
            engine.callbacks.particleEngine.emitParticle(physics.pos,
                Vector2f(0), myclass.emitOnWater);
        }
        //if under=true, this will make the sprite die
        super.waterStateChange();
    }

    this(GameEngine engine, NapalmSpriteClass type) {
        super(engine, type);

        assert(type !is null);
        myclass = type;
        mDecaySecs = myclass.decayTime.sample(engine.rnd).secsf;
        mRepeatDelay = myclass.initialDelay.sample(engine.rnd);
        mLastDmg = engine.gameTime.current;
        lightUp();
    }

    this (ReflectCtor c) {
        super(c);
    }
}

class NapalmSpriteClass : ProjectileSpriteClass {
    RandomFloat damage = {5f, 5f};
    RandomValue!(Time) decayTime = {timeMsecs(5000), timeMsecs(5000)};
    RandomValue!(Time) initialDelay = {timeMsecs(0), timeMsecs(0)};
    RandomValue!(Time) repeatDelay = {timeMsecs(500), timeMsecs(500)};
    //can't change initState.physic_properties, so reduced radius is put here
    POSP physMedium, physSmall;
    float lightupVelocity = 400;
    ParticleType emitOnWater;

    override NapalmSprite createSprite(GameEngine engine) {
        return new NapalmSprite(engine, this);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        damage = config.getValue("damage", damage);
        initialDelay = config.getValue("initial_delay", initialDelay);
        repeatDelay = config.getValue("repeat_delay", repeatDelay);
        decayTime = config.getValue("decay_time", decayTime);
        physMedium = initState.physic_properties.copy;
        physMedium.radius = config.getFloatValue("radius_m", 2);
        physSmall = initState.physic_properties.copy;
        physSmall.radius = config.getFloatValue("radius_s", 1);
        lightupVelocity = config.getFloatValue("lightup_velocity",
            lightupVelocity);
        auto odp = config["on_drown_particle"];
        if (odp.length)
            emitOnWater = gfx.resources.get!(ParticleType)(odp);
    }

    this(GfxSet e, char[] r) {
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
