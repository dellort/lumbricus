module game.weapon.napalm;

import game.core;
import game.particles;
import game.sprite;
import game.sequence;
import physics.all;
import std.math;
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
        float mDecaySecs;               //seconds for full (or step) decay
        //percentage of decayTime that remains, negative if passed
        float mDecayPerc = 1.0f;
        int mDecayStep;                 //sticky napalm: current decay step
        int mDecayOffset;
    }

    this(NapalmSpriteClass type) {
        super(type);

        myclass = type;
        mDecayOffset = myclass.currentDecay;
        mDecaySecs = myclass.decayTime.sample(engine.rnd).secsf;
        mRepeatDelay = myclass.initialDelay.sample(engine.rnd);
        mLastDmg = engine.gameTime.current;
        lightUp();
    }

    //time in seconds until the next decay happens
    private float nextDecaySecs() {
        return mDecaySecs - (engine.gameTime.current - mLightupTime).secsf;
    }

    private void updateDecay() {
        if (myclass.sticky) {
            mDecayPerc = 1.0f - mDecayStep*1.0f / myclass.decaySteps;
        } else {
            float p = nextDecaySecs() / mDecaySecs;
            if (p > 0)
                //faster decay for tiny napalm
                mDecayPerc = sqrt(p);
            else
                mDecayPerc = p;
        }
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

        if (myclass.sticky && myclass.currentDecay != mDecayOffset) {
            mDecayStep += myclass.currentDecay - mDecayOffset;
            mDecayOffset = myclass.currentDecay;
            //reset nextDecaySecs() value so napalm becomes active
            lightUp();
        }

        updateDecay();

        //adjust particle radius to decay
        POSP npsp = physics.posp;
        if (mDecayPerc <= 0.25)
            physics.posp = myclass.physSmall;
        else if (mDecayPerc <= 0.5)
            physics.posp = myclass.physMedium;
        else
            physics.posp = myclass.initPhysic;

        //check for death
        if (mDecayPerc <= 0)
            kill();

        //cause some damage
        //xxx this has to change for worms pushed up (<--- ?)
        if (engine.gameTime.current - mLastDmg >= mRepeatDelay) {
            float dmg = myclass.damage.sample(engine.rnd)
                * (0.25 + mDecayPerc*0.75);

            //sticky napalm affects only non-static objects (i.e. worms, not
            //  landscape)
            //xxx: this may interfere with the game logic's activity check
            bool filter_static(PhysicObject obj) {
                return !obj.isStatic();
            }
            bool delegate(PhysicObject) filter;
            if (!activity)
                filter = &filter_static;

            engine.explosionAt(physics.pos, dmg, this, false, filter);
            mLastDmg = engine.gameTime.current;
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

    override bool activity() {
        if (myclass.sticky) {
            return nextDecaySecs() > 0;
        } else {
            return true;
        }
    }
}

class NapalmSpriteClass : SpriteClass {
    //damage to worm and landscape; will somehow be reduced by decay
    RandomFloat damage = {5f, 5f};
    //time for full decay of the particle
    RandomValue!(Time) decayTime = {timeMsecs(5000), timeMsecs(5000)};
    //first repeatDelay - time after which first damage is done
    RandomValue!(Time) initialDelay = {timeMsecs(0), timeMsecs(0)};
    //time after next damage is done
    RandomValue!(Time) repeatDelay = {timeMsecs(500), timeMsecs(500)};
    //can't change initState.physic_properties, so reduced radius is put here
    POSP physMedium, physSmall;
    float lightupVelocity = 400;
    ParticleType emitOnWater;
    //true: napalm is persistent and "sticks" on the landscape; you use
    //  stepDecay() to explicitly decay all particles (e.g. on each turn change)
    //false: each napalm particle decays on its own and never sticks
    bool sticky;
    //for sticky napalm: number of decay steps until napalm is gone
    int decaySteps;

    package int currentDecay;

    this(GameCore e, string r) {
        super(e, r);
    }

    override NapalmSprite createSprite() {
        return new NapalmSprite(this);
    }

    //step the decay of all alive napalm particles of this type
    void stepDecay() {
        argcheck(sticky);
        currentDecay++;
    }
}
