module game.weapon.actionweapon;

import framework.framework;
import game.animation;
import physics.world;
import game.action.base;
import game.action.wcontext;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import game.weapon.projectile;
import utils.array;
import utils.misc;
import utils.mybox;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.randval;

class ActionWeapon : WeaponClass {
    ActionClass onFire, onBlowup;
    int repeatCount = 1;      //how many shots will be fired on one activation
    int reduceAmmo = int.max; //take 1 ammo every x bullets (and always at end)
    RandomValue!(Time) repeatDelay = {Time.Null, Time.Null};

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        onFire = actionFromConfig(aengine, node.getSubNode("onfire"));
        onBlowup = actionFromConfig(aengine, node.getSubNode("onblowup", false));
        repeatCount = node.getValue("repeat", repeatCount);
        if (node["repeat_delay"] == "user") {
            //repeat on spacebar
            repeatDelay = Time.Never;
        } else {
            //auto-repeat
            repeatDelay = node.getValue("repeat_delay", repeatDelay);
        }
        if (node["reduce_ammo"] != "end" && node["reduce_ammo"] != "max") {
            reduceAmmo = node.getValue("reduce_ammo", reduceAmmo);
        }
        if (!onFire) {
            //xxx error handling...
            throw new Exception("Action-based weapon needs onfire action");
        }
    }

    bool manualFire() {
        return !!(repeatDelay.min == Time.Never);
    }

    ActionShooter createShooter(GObjectSprite go) {
        return new ActionShooter(this, go, mEngine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("action");
    }
}

//standard projectile shooter for projectiles which are started from the worm
//(as opposed to air strikes etc.)
class ActionShooter : Shooter, ProjectileFeedback {
    private {
        ActionWeapon myclass;
        ActionContext mFireAction;
        //holds a list of sprites that can execute the onrefire event
        ProjectileSprite[] mRefireSprites;
        int mShotsRemain;
        Time mWaitDone = Time.Never;
        bool mCanManualFire;
    }
    protected WrapFireInfo fireInfo;

    this(ActionWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
        fireInfo = new WrapFireInfo;
    }

    this (ReflectCtor c) {
        super(c);
    }

    bool activity() {
        //still firing, or waiting for refire keypress
        return !!mFireAction || canRefire;
    }

    override bool delayedAction() {
        return !!mFireAction;
    }

    void fireFinish() {
        mFireAction = null;
        if (!activity)
            finished();
    }

    private bool canRefire() {
        //only sprites with refire possible are in this list
        return mCanManualFire || mRefireSprites.length > 0;
    }

    WeaponContext createContext() {
        auto ctx = new WeaponContext(engine);
        ctx.fireInfo = fireInfo;
        ctx.ownerSprite = owner;
        ctx.createdBy = this;
        ctx.feedback = this;
        return ctx;
    }

    //interface ProjectileFeedback.addSprite
    void addRefire(ProjectileSprite s) {
        mRefireSprites ~= s;
    }

    void removeRefire(ProjectileSprite s) {
        arrayRemoveUnordered(mRefireSprites, s, true);
        if (!activity)
            //all possible refire sprites died by themselves
            finished();
    }

    void fireRound() {
        //if the outer fire action is a list, called every loop, else once
        //before firing
        fireInfo.info.pos = owner.physics.pos;
    }

    void readjust(Vector2f dir) {
        fireInfo.info.dir = dir;
    }

    private void fireOne() {
        mCanManualFire = false;
        if (mShotsRemain <= 0)
            return;
        fireRound();
        mFireAction.reset();
        myclass.onFire.execute(mFireAction);

        //reduce ammo after the projectile was launched (as logic dictates)
        mShotsRemain--;
        //take 1 ammo every myclass.reduceAmmo (always at end of firing)
        if ((myclass.repeatCount - mShotsRemain) % myclass.reduceAmmo == 0
            || mShotsRemain <= 0)
        {
            reduceAmmo();
        }

        if (mFireAction.done()) {
            fireDone();
        } else {
            //need to wait for action to finish
            active = true;
        }
    }

    private void fireDone() {
        if (mShotsRemain <= 0) {
            //all shots fired, done
            active = false;
            fireFinish();
        } else if (!myclass.manualFire()) {
            //need to wait for next shot
            mWaitDone = engine.gameTime.current
                + myclass.repeatDelay.sample(engine.rnd);
            active = true;
        } else {
            mCanManualFire = true;
        }
    }

    protected void doFire(FireInfo info) {
        if (mFireAction) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (mFireAction)
                return;
        }

        mShotsRemain = myclass.repeatCount;
        fireInfo.info = info;
        fireInfo.info.shootbyRadius = owner.physics.posp.radius;
        //create firing action
        mFireAction = createContext();

        fireOne();

        //wut?
        /+
        //if it has an extra firing, let the owner update it
        //(cf. Worm.getAnimationForState())
        if (owner && weapon.animations[WeaponWormAnimations.Fire].defined) {
            owner.updateAnimation();
        }
        +/
    }

    protected bool doRefire() {
        if (!canRefire())
            return false;
        //I decided that, in the special case where both is possible
        //  (e.g. a multi-shot sally army), blowing up already out
        //  projectiles has priority
        //Note: It gets very weird if you combine refireable projectiles with
        //      auto-repeating; this case should be considered the
        //      script-writer's fault
        if (mRefireSprites.length > 0) {
            auto curs = mRefireSprites.dup;
            mRefireSprites = null;
            foreach (as; curs) {
                //note that the event could spawn new projectiles which add
                //themselves to the mRefireSprites list
                as.doEvent("onrefire");
            }
            //check if all refire sprites got blown up
            if (!activity)
                finished();
            return true;
        } else if (mCanManualFire) {
            fireOne();
            return true;
        }
        //see canRefire()
        assert(false);
    }

    override bool isFixed() {
        //allow movement while waiting for refire
        return !!mFireAction;
    }

    override void interruptFiring(bool outOfAmmo = false) {
        mShotsRemain = 0;
        //don't abort the current projectile if the gun ran out of ammo after
        //  firing it
        if (outOfAmmo)
            return;
        //... but abort everything if the worm was hit etc.
        if (active) {
            //waiting for fire action to run, or for next shot
            assert(!!mFireAction);
            mWaitDone = Time.Never;
            mFireAction.abort();
            //we set mShotsRemain = 0 above, this will not fire again
            fireDone();
        } else if (canRefire()) {
            mRefireSprites = null;
            finished();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        assert(!!mFireAction);
        if (mWaitDone != Time.Never) {
            if (engine.gameTime.current >= mWaitDone) {
                //waited long enough, auto-fire next shot
                assert(!myclass.manualFire());
                mWaitDone = Time.Never;
                active = false;
                fireOne();
            }
        } else if (mFireAction.done()) {
            //background activity terminated
            fireDone();
        }
    }
}
