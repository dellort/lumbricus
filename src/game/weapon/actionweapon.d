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
import utils.misc;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.factory;

private class ActionWeapon : WeaponClass {
    ActionClass onFire, onBlowup;

    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
        onFire = actionFromConfig(aengine, node.getSubNode("onfire"));
        onBlowup = actionFromConfig(aengine, node.getSubNode("onblowup", false));
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
private class ActionShooter : Shooter {
    private {
        ActionWeapon myclass;
        Action mFireAction;
    }
    protected FireInfo fireInfo;

    this(ActionWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        myclass = base;
    }

    bool activity() {
        return !!mFireAction;
    }

    void fireFinish(Action sender) {
        mFireAction = null;
    }

    protected MyBox fireReadParam(char[] id) {
        switch (id) {
            case "fireinfo":
                return MyBox.Box(&fireInfo);
            case "owner_game":
                return MyBox.Box!(GameObject)(owner);
            default:
                return MyBox();
        }
    }

    void fireRound(Action sender) {
        //if the outer fire action is a list, called every loop, else once
        //before firing
    }

    void fire(FireInfo info) {
        if (mFireAction) {
            //try to interrupt
            interruptFiring();
            //if still active: no.
            if (mFireAction)
                return;
        }

        fireInfo = info;
        fireInfo.pos = owner.physics.pos;
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

    override void interruptFiring() {
        mFireAction.abort();
    }
}
