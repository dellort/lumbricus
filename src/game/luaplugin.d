module game.luaplugin;

import framework.framework;
import game.controller;
import game.controller_events;
import game.game;
import game.gfxset;
import game.gobject;
import game.sprite;
import game.weapon.weapon;
import game.weapon.types;
import utils.configfile;
import utils.misc;
import utils.time;

//lua script as generic GameObject (only good for plugin loading)
//questionable way to load scripts, but needed for game mode right now
class LuaPlugin : GameObject {
    private {
        struct Config {
            char[] filename;
        }
        Config config;
    }

    this(GameEngine a_engine, ConfigNode cfgNode) {
        super(a_engine, "luaplugin");
        config = cfgNode.getCurValue!(Config)();

        engine.loadScript(config.filename);
    }

    override bool activity() {
        return false;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("lua");
    }
}

//copy and pasted from weapon.d
struct WeaponParams {
    int value = 0;  //see config file
    char[] category = "none"; //category-id for this weapon
    bool isAirstrike = false; //needed to exlude it from cave levels
    bool allowSecondary = false;  //allow selecting and firing a second
                                  //weapon while active
    bool dontEndRound = false;
    bool deselectAfterFire = false;
    Time cooldown = Time.Null;
    int crateAmount = 1;

    //for the weapon selection; only needed on client-side
    Surface icon;

    FireMode fireMode;

    //weapon-holding animations
    char[] animation;
}

class LuaWeaponClass : WeaponClass {
    Shooter delegate(Sprite) onCreateShooter;
    WeaponSelector delegate(Sprite) onCreateSelector;

    this(GfxSet gfx, char[] a_name) {
        super(gfx, a_name);
    }

    void setParams(WeaponParams p) {
        value = p.value;
        category = p.category;
        isAirstrike = p.isAirstrike;
        allowSecondary = p.allowSecondary;
        dontEndRound = p.dontEndRound;
        deselectAfterFire = p.deselectAfterFire;
        cooldown = p.cooldown;
        crateAmount = p.crateAmount;
        icon = p.icon;
        fireMode = p.fireMode;
        animation = p.animation;
    }

    override WeaponSelector createSelector(Sprite selected_by) {
        if (!onCreateSelector)
            return null;
        return onCreateSelector(selected_by);
    }

    override Shooter createShooter(Sprite go, GameEngine engine) {
        assert(!!onCreateShooter, "no shooter set");
        return onCreateShooter(go);
    }
}
