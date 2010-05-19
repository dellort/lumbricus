module game.weapon.napalm;

import framework.framework;
import game.core;
import game.particles;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import physics.all;
import tango.math.Math;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.random;
import utils.randval;

class NapalmSprite : Sprite {
    private {
        NapalmSpriteClass myclass;
        Time mLightupTime;              //Time when decaying started
        Time mRepeatDelay;              //delay until next damage
        Time mLastDmg;                  //Time the last damage was caused
        float mDecaySecs;               //seconds for full decay
        float mDecayPerc = 1.0f;        //cache for decay percentage
    }

    this(NapalmSpriteClass type) {
        super(type);

        myclass = type;
        mDecaySecs = myclass.decayTime.sample(engine.rnd).secsf;
        mRepeatDelay = myclass.initialDelay.sample(engine.rnd);
        mLastDmg = engine.gameTime.current;
        lightUp();
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

    override void simulate() {
        super.simulate();

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
            physics.posp = myclass.initPhysic;

        //check for death
        mDecayPerc = dp;
        if (mDecayPerc < 0)
            kill();

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
        if (isUnderWater) {
            if (myclass.emitOnWater) {
                //emit some particles when we die
                engine.particleWorld.emitParticle(physics.pos,
                    Vector2f(0), myclass.emitOnWater);
            }
            kill();
        }
        super.waterStateChange();
    }
}

class NapalmSpriteClass : SpriteClass {
    RandomFloat damage = {5f, 5f};
    RandomValue!(Time) decayTime = {timeMsecs(5000), timeMsecs(5000)};
    RandomValue!(Time) initialDelay = {timeMsecs(0), timeMsecs(0)};
    RandomValue!(Time) repeatDelay = {timeMsecs(500), timeMsecs(500)};
    //can't change initState.physic_properties, so reduced radius is put here
    POSP physMedium, physSmall;
    float lightupVelocity = 400;
    ParticleType emitOnWater;

    this(GameCore e, char[] r) {
        super(e, r);
    }

    override NapalmSprite createSprite() {
        return new NapalmSprite(this);
    }
}
