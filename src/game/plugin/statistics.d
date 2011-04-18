module game.plugin.statistics;

import game.controller;
import game.core;
import game.sprite;
import game.plugins;
import game.plugin.crate;
import game.weapon.weapon;
import game.weapon.weaponset;
import physics.all;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.time;

//stupid simple statistics module
//this whole thing is more or less debugging code
//
//currently missing:
//  - Team/Worm-based statistics
//  - Proper output/sending to clients
//  - timecoded events, with graph drawing?
//  - gamemode dependency?
class ControllerStats : GameObject {
    private {
        static LogStruct!("gameevents") log;

        struct Stats {
            //damage: all, damage to neutral stuff, damage when object
            //  was already dead, damage by drowning (if object was
            //  not already dead), damage caused by neutral stuff
            float totalDmg = 0f, collateralDmg = 0f, overDmg = 0f,
                waterDmg = 0f, neutralDamage = 0f;
            //casualties (total = died + drowned)
            int wormsDied, wormsDrowned;
            //shots by all weapons (refire not counted)
            int shotsFired;
            //collected crates
            int crateCount;
            int[string] weaponStats;

            //dump everything to console
            void output() {
                log("Worms killed: {} ({} died, {} drowned)", wormsDied
                    + wormsDrowned, wormsDied, wormsDrowned);
                log("Total damage caused: {}", totalDmg);
                log("Damage by water: {}", waterDmg);
                log("Collateral damage caused: {}", collateralDmg);
                log("Damage by neutral objects: {}", neutralDamage);
                log("Total overdamage: {}", overDmg);
                log("Shots fired: {}", shotsFired);
                int c = -1;
                string maxwName;
                foreach (string wc, int count; weaponStats) {
                    if (count > c) {
                        maxwName = wc;
                        c = count;
                    }
                }
                if (maxwName.length > 0)
                    log("Favorite weapon: {} ({} shots)", maxwName, c);
                log("Crates collected: {}", crateCount);
            }
        }
        Stats mStats;
        GameController mController;
    }

    this(GameCore c, ConfigNode o) {
        super(c, "stats_plugin");
        mController = engine.singleton!(GameController)();
        OnGameEnd.handler(engine.events, &onGameEnd);
        OnDamage.handler(engine.events, &onDamage);
        OnSpriteDie.handler(engine.events, &onSpriteDie);
//        OnCrateCollect.handler(engine.events, &onCrateCollect);
        OnFireWeapon.handler(engine.events, &onFireWeapon);
    }

    private void onDamage(Sprite victim, GameObject cause, DamageCause type,
        float damage)
    {
        string wname = "unknown_weapon";
        WeaponClass wclass = mController.weaponFromGameObject(cause);
        if (wclass)
            wname = wclass.name;
        auto m1 = mController.memberFromGameObject(cause, true);
        auto m2 = mController.memberFromGameObject(victim, false);
        string dmgs = myformat("{}", damage);
        if (victim.physics.lifepower < 0) {
            float ov = min(-victim.physics.lifepower, damage);
            mStats.overDmg += ov;
            dmgs = myformat("{} ({} overdmg)", damage, ov);
        }
        mStats.totalDmg += damage;
        if (m1 && m2) {
            if (m1 is m2)
                log("worm {} injured himself by {} with {}", m1, dmgs, wname);
            else
                log("worm {} injured {} by {} with {}", m1, m2, dmgs, wname);
        } else if (m1 && !m2) {
            mStats.collateralDmg += damage;
            log("worm {} caused {} collateral damage with {}", m1, dmgs,
                wname);
        } else if (m2 && type == DamageCause.fall) {
            assert(!cause);
            log("worm {} took {} fall damage", m2, dmgs);
        } else if (!m1 && m2) {
            //neutral damage is not caused by weapons
            assert(wclass is null, "some createdBy relation wrong");
            mStats.neutralDamage += damage;
            log("victim {} received {} damage from neutral objects", m2,
                dmgs);
        } else {
            //most likely level objects blowing up other objects
            //  -> count as collateral
            mStats.collateralDmg += damage;
            log("unknown damage {}", dmgs);
        }
    }

    private void onFireWeapon(WeaponClass wclass, bool refire) {
        string wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        log("Fired weapon (refire={}): {}",refire,wname);
        if (!refire) {
            if (!(wname in mStats.weaponStats))
                mStats.weaponStats[wname] = 1;
            else
                mStats.weaponStats[wname] += 1;
            mStats.shotsFired++;
        }
    }

    private void onSpriteDie(Sprite sprite) {
        TeamMember m = mController.memberFromGameObject(sprite, false);
        if (!m)
            return;
        bool drowned = sprite.isUnderWater();
        if (!drowned) {
            log("Worm die: {}", m);
            mStats.wormsDied++;
        } else {
            int dh = m.currentHealth() - m.health();
            log("Worm drown (floating label would say: {}): {} ", dh, m);
            if (m.health(true) > 0)
                mStats.waterDmg += m.health(true);
            mStats.wormsDrowned++;
        }
    }

/+
    private void onCrateCollect(CrateSprite crate, TeamMember m) {
        log("{} collects crate: {}", m, crate.stuffies);
        mStats.crateCount++;
    }
+/

    private void onGameEnd() {
        debug mStats.output();
        engine.persistentState.setValue("stats", mStats);
    }

    override bool activity() {
        return false;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("statistics");
    }
}
