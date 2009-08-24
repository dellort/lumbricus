module game.weapon.melee;

import game.game;
import game.gobject;
import physics.world;
import game.action.base;
import game.sprite;
import game.weapon.weapon;
import game.gamepublic;
import game.gfxset;
import game.weapon.actionweapon;
import tango.math.Math: PI;
import utils.vector2;
import utils.configfile;
import utils.color;
import utils.log;
import utils.random;
import utils.time;
import utils.reflection;

class MeleeWeapon: ActionWeapon {
    int dist = 10;

    this(GfxSet gfx, ConfigNode node) {
        super(gfx, node);
        //always directed with fixed strength
        fireMode.variableThrowStrength = false;
        node.getValue!(int)("distance", dist);
    }

    //xxx class
    this (ReflectCtor c) {
        super(c);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    MeleeShooter createShooter(GObjectSprite owner, GameEngine engine) {
        return new MeleeShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(typeof(this))("melee");
    }
}

class MeleeShooter: ActionShooter {
    MeleeWeapon base;

    this(MeleeWeapon base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
        this.base = base;
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void fireRound() {
        fireInfo.info.pos = owner.physics.pos + fireInfo.info.dir*base.dist;

        //away from shooting object, so don't use radius
        fireInfo.info.shootbyRadius = 0;
    }
}
