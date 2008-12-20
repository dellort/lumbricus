module game.weapon.actionweapon;

import framework.framework;
import game.animation;
import physics.world;
import game.action;
import game.actionsprite;
import game.game;
import game.gobject;
import game.sprite;
import game.sequence;
import game.weapon.weapon;
import utils.array;
import utils.misc;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.factory;

private class ActionWeapon : WeaponClass {
    ActionClass onFire, onBlowup;
    //bool waitRefire = false;

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
private class ActionShooter : Shooter, RefireTrigger {
    private {
        ActionWeapon myclass;
        Action mFireAction;
        //holds a list of sprites that can execute the onrefire event
        ActionSprite[] mRefireSprites;
    }
    protected FireInfo fireInfo;

    this(ActionWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
    }

    bool activity() {
        //still firing, or waiting for refire keypress
        return !!mFireAction || canRefire;
    }

    override bool delayedAction() {
        return !!mFireAction;
    }

    void fireFinish(Action sender) {
        //xxx no list? so run after-loop event manually
        if (!cast(ActionList)sender)
            roundFired(sender);
        mFireAction = null;
        if (!canRefire)
            finished();
    }

    private bool canRefire() {
        foreach (int i, sp; mRefireSprites) {
            //remove dead sprites
            if (!sp.active) {
                if (i < mRefireSprites.length-1)
                    mRefireSprites[i] = mRefireSprites[$-1];
                mRefireSprites.length = mRefireSprites.length - 1;
            }
        }
        //only sprites with refire possible are in this list
        return mRefireSprites.length > 0;
    }

    protected MyBox fireReadParam(char[] id) {
        switch (id) {
            case "fireinfo":
                return MyBox.Box(&fireInfo);
            case "owner_game":
                return MyBox.Box!(GameObject)(owner);
            case "refire_trigger":
                return MyBox.Box!(RefireTrigger)(this);
            default:
                return MyBox();
        }
    }

    //interface RefireTrigger.addSprite
    void addSprite(ActionSprite s) {
        mRefireSprites ~= s;
    }

    void fireRound(Action sender) {
        //if the outer fire action is a list, called every loop, else once
        //before firing
        fireInfo.pos = owner.physics.pos;
    }

    void roundFired(Action sender) {
        //called after every loop
        reduceAmmo();
    }

    void readjust(Vector2f dir) {
        fireInfo.dir = dir;
    }

    protected void doFire(FireInfo info) {
        if (mFireAction) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (mFireAction)
                return;
        }

        fireInfo = info;
        fireInfo.shootbyRadius = owner.physics.posp.radius;
        //create firing action
        mFireAction = myclass.onFire.createInstance(engine);
        mFireAction.onFinish = &fireFinish;
        //set parameters and let action do the rest
        //parameter stuff is a big xxx

        //xxx this is hacky
        auto al = cast(ActionList)mFireAction;
        if (al) {
            al.onStartLoop = &fireRound;
            al.onEndLoop = &roundFired;
        } else {
            //no list? so just one-time call when mFireAction is run
            mFireAction.onExecute = &fireRound;
        }

        auto ctx = new ActionContext(&fireReadParam);
        mFireAction.execute(ctx);

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
        if (mRefireSprites.length == 0)
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
}
