module game.action.wcontext;

import game.action.base;
import game.game;
import game.gobject;
import game.sprite;
import game.actionsprite;
import game.weapon.weapon;
import game.weapon.projectile;
import utils.reflection;

class WeaponContext : ActionContext {
    WrapFireInfo fireInfo;
    GameObject createdBy;
    GObjectSprite ownerSprite;
    ProjectileFeedback feedback;

    this(GameEngine eng) {
        super(eng);
    }
    this(ReflectCtor c) {
        super(c);
    }

    bool doubleDamage() {
        if (auto as = cast(ActionSprite)createdBy) {
            return as.doubleDamage;
        }
        if (auto m = engine.controller.memberFromGameObject(createdBy, true)) {
            return m.serverTeam.hasDoubleDamage();
        }
        return false;
    }
}

