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

class ActionWeapon : WeaponClass {
    ActionClass onFire, onBlowup;
    //bool waitRefire = false;

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        onFire = actionFromConfig(aengine, node.getSubNode("onfire"));
        onBlowup = actionFromConfig(aengine, node.getSubNode("onblowup", false));
        //waitRefire = node.getBoolValue("wait_refire", waitRefire);
        if (!onFire) {
            //xxx error handling...
            throw new Exception("Action-based weapon needs onfire action");
        }
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
    }
    protected WrapFireInfo fireInfo;

    this(ActionWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
        fireInfo = new WrapFireInfo;
    }

    this (ReflectCtor c) {
        super(c);
        /*c.types().registerMethod(this, &fireFinish, "fireFinish");
        c.types().registerMethod(this, &fireRound, "fireRound");
        c.types().registerMethod(this, &roundFired, "roundFired");*/
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
        return mRefireSprites.length > 0;
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

    void roundFired() {
        //called after every loop
        reduceAmmo();
    }

    void readjust(Vector2f dir) {
        fireInfo.info.dir = dir;
    }

    protected void doFire(FireInfo info) {
        if (mFireAction) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (mFireAction)
                return;
        }

        fireInfo.info = info;
        fireInfo.info.shootbyRadius = owner.physics.posp.radius;
        //create firing action
        mFireAction = createContext();

        /*//xxx this is hacky
        auto al = cast(ActionList)mFireAction;
        if (al) {
            al.onStartLoop = &fireRound;
            al.onEndLoop = &roundFired;
        } else {
            //no list? so just one-time call when mFireAction is run
            mFireAction.onExecute = &fireRound;
        }*/

        fireRound();
        myclass.onFire.execute(mFireAction);
        if (mFireAction.done()) {
            roundFired();
            fireFinish();
        } else {
            active = true;
        }

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
    }

    override bool isFixed() {
        //allow movement while waiting for refire
        return !!mFireAction;
    }

    override void interruptFiring() {
        if (mFireAction)
            mFireAction.abort();
        else if (canRefire()) {
            mRefireSprites = null;
            finished();
        }
    }

    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (mFireAction && mFireAction.done()) {
            roundFired();
            fireFinish();
        }
    }
}
