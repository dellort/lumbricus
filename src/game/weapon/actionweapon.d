module game.weapon.actionweapon;

import framework.framework;
import physics.world;
import game.action.base;
import game.action.wcontext;
import game.actionsprite;
import game.game;
import game.gfxset;
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
import utils.time;
import utils.randval;

class ActionWeapon : ConfWeaponClass {
    ActionClass onFire, onBlowup; //, onSelect;
    int repeatCount = 1;      //how many shots will be fired on one activation
    int reduceAmmo = int.max; //take 1 ammo every x bullets (and always at end)
    RandomValue!(Time) repeatDelay = {Time.Null, Time.Null};

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        ActionClass getaction(char[] aname, bool required) {
            auto res = actionFromConfig(gfx, node.getSubNode(aname, required),
                name ~ "::" ~ aname);
            if (!res && required) {
                //xxx error handling...
                throw new CustomException(myformat("Action-based weapon needs action:"
                    " weapon={} action={}", name, aname));
            }
            return res;
        }
        onFire = getaction("onfire", true);
        onBlowup = getaction("onblowup", false);
        //onSelect = getaction("onselect", false);
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
    }

    bool manualFire() {
        return !!(repeatDelay.min == Time.Never);
    }

    /+
    override void select(Sprite selected_by) {
        if (!onSelect || !selected_by)
            return;
        auto ctx = new SpriteContext(selected_by.engine);
        ctx.ownerSprite = selected_by;
        onSelect.execute(ctx);
    }
    +/

    ActionShooter createShooter(Sprite go, GameEngine engine) {
        return new ActionShooter(this, go, engine);
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

    this(ActionWeapon base, Sprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
        fireInfo = new WrapFireInfo;
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
        ctx.shooter = this;
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

    override void readjust(Vector2f dir) {
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
            internal_active = true;
        }
    }

    private void fireDone() {
        if (mShotsRemain <= 0) {
            //all shots fired, done
            internal_active = false;
            fireFinish();
        } else if (!myclass.manualFire()) {
            //need to wait for next shot
            mWaitDone = engine.gameTime.current
                + myclass.repeatDelay.sample(engine.rnd);
            internal_active = true;
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
        if (internal_active) {
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
                internal_active = false;
                fireOne();
            }
        } else if (mFireAction.done()) {
            //background activity terminated
            fireDone();
        }
    }
}
