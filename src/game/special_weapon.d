module game.special_weapon;

import game.game;
import game.weapon;
import game.gobject;
import utils.configfile;
import utils.log;

static this() {
    gWeaponClassFactory.register!(SpecialWeapon)("specialw_mc");
}

class SpecialWeapon : WeaponClass {
    this(GameObjectHandler handler, GameEngine aengine, ConfigNode node) {
        super(handler, aengine, node);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    Shooter createShooter() {
        return new SpecialShooter(this, mHandler, engine);
    }
}

private class SpecialShooter : Shooter {
    this(WeaponClass base, GameObjectHandler handler, GameEngine engine) {
        super(base, handler, engine);
    }

    void fire(FireInfo info) {
        gDefaultLog("do whatever you want");
    }
}
