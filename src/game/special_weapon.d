module game.special_weapon;

import game.game;
import game.weapon;
import game.gobject;
import game.sprite;
import utils.configfile;
import utils.log;

class SpecialWeapon : WeaponClass {
    this(GameEngine aengine, ConfigNode node) {
        super(aengine, node);
    }

    //using SpecialShooter here leads to dmd lockup (at least with dsss)
    Shooter createShooter(GObjectSprite owner) {
        return new SpecialShooter(this, owner, engine);
    }

    static this() {
        WeaponClassFactory.register!(SpecialWeapon)("specialw_mc");
    }
}

private class SpecialShooter : Shooter {
    this(WeaponClass base, GObjectSprite a_owner, GameEngine engine) {
        super(base, a_owner, engine);
    }

    bool activity() {
        return active;
    }

    void fire(FireInfo info) {
        gDefaultLog("do whatever you want");
    }
}
