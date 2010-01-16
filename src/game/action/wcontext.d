module game.action.wcontext;

import game.action.base;
import game.game;
import game.gobject;
import game.sprite;
import game.actionsprite;
import game.weapon.weapon;
import game.weapon.projectile;

//wtf? why not make FireInfo a class?
class WrapFireInfo { //wee so Java like
    FireInfo info;
    this () {
    }
}


//xxx: we really should have a more flexible/sane parameter passing mechanism
class SpriteContext : ActionContext {
    Sprite ownerSprite;

    this(GameEngine eng) {
        super(eng);
    }
}

class WeaponContext : SpriteContext {
    WrapFireInfo fireInfo;
    GameObject createdBy;
    Shooter shooter;
    ProjectileFeedback feedback;

    this(GameEngine eng) {
        super(eng);
    }

    bool doubleDamage() {
        if (auto as = cast(ActionSprite)createdBy) {
            return as.doubleDamage;
        }
        if (auto m = engine.controller.memberFromGameObject(createdBy, true)) {
            return m.team.hasDoubleDamage();
        }
        return false;
    }
}
