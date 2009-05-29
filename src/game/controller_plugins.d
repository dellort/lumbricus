module game.controller_plugins;

import common.config;
import game.controller_events;
import game.gamepublic;
import game.controller;
import game.game;
import game.gobject;
import game.sprite;
import game.crate;
import game.weapon.weapon;
import utils.reflection;
import utils.log;
import utils.configfile;
import utils.misc;


//the idea was that the whole game state should be observable (including
//events), so you can move displaying all messages into a separate piece of
//code, instead of creating messages directly
class ControllerMsgs : ControllerPlugin {
    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onGameStart", "onSelectWeapon", "onWormEvent",
        "onTeamEvent", "onCrateDrop", "onCrateCollect", "onSuddenDeath",
        "onVictory", "onGameEnded"]));

    private void onGameStart() {
        controller.messageAdd("msggamestart", null);
    }

    private void onSelectWeapon(ServerTeamMember m, WeaponClass wclass) {
        //xxx just copying old code... maybe this can be extended to show
        //    grenade timer messages (like in wwp)
        /*if (wclass) {
            controller.messageAdd("msgselweapon", ["_.weapons." ~ wclass.name],
                m.team, m.team);
        } else {
            controller.messageAdd("msgnoweapon", null, m.team, m.team);
        }*/
    }

    private void onWormEvent(WormEvent id, ServerTeamMember m) {
        switch (id) {
            case WormEvent.wormActivate:
                controller.messageAdd("msgwormstartmove", [m.name], m.team,
                    m.team);
                break;
            case WormEvent.wormDrown:
                controller.messageAdd("msgdrown", [m.name], m.team);
                break;
            case WormEvent.wormDie:
                controller.messageAdd("msgdie", [m.name], m.team);
                break;
            default:
        }
    }

    private void onTeamEvent(TeamEvent id, ServerTeam t) {
        switch (id) {
            case TeamEvent.skipTurn:
                controller.messageAdd("msgskipturn", [t.name()], t);
                break;
            case TeamEvent.surrender:
                controller.messageAdd("msgsurrender", [t.name()], t);
                break;
            default:
        }
    }

    private void onCrateDrop(CrateType type) {
        switch (type) {
            case CrateType.med:
                controller.messageAdd("msgcrate_medkit");
                break;
            case CrateType.tool:
                controller.messageAdd("msgcrate_tool");
                break;
            default:
                controller.messageAdd("msgcrate");
        }
    }

    private void onCrateCollect(ServerTeamMember member,
        Collectable[] stuffies)
    {
        foreach (item; stuffies) {
            if (auto weapon = cast(CollectableWeapon)item) {
                //weapon
                controller.messageAdd("collect_item", [member.name(),
                    "_." ~ item.id(), to!(char[])(weapon.quantity)],
                    member.team, member.team);
            } else if (auto medkit = cast(CollectableMedkit)item) {
                //medkit
                controller.messageAdd("collect_medkit", [member.name(),
                    to!(char[])(medkit.amount)], member.team, member.team);
            } else if (auto tool = cast(CollectableTool)item) {
                //tool
                controller.messageAdd("collect_tool", [member.name(),
                    "_." ~ item.id()], member.team, member.team);
            } else if (auto bomb = cast(CollectableBomb)item) {
                //crate with bomb
                controller.messageAdd("collect_bomb", [member.name()],
                    member.team, member.team);
            }
        }
    }

    private void onSuddenDeath() {
        controller.messageAdd("msgsuddendeath");
    }

    private void onVictory(Team winner) {
        if (winner) {
            controller.messageAdd("msgwin", [winner.name], winner);
        } else {
            controller.messageAdd("msgnowin");
        }
    }

    private void onGameEnded() {
        //xxx is this really useful? I would prefer showing the
        //  "team xxx won" message longer
        controller.messageAdd("msggameend");
    }

    static this() {
        ControllerPluginFactory.register!(typeof(this))("messages");
    }
}

//stupid simple statistics module
//this whole thing is more or less debugging code
//
//currently missing:
//  - Team/Worm-based statistics
//  - Proper output/sending to clients
//  - timecoded events, with graph drawing?
//  - gamemode dependency?
class ControllerStats : ControllerPlugin {
    private {
        static LogStruct!("gameevents") log;
    }

    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onDamage", "onDemolition", "onFireWeapon",
        "onWormEvent", "onCrateCollect", "onGameEnded"]));

    private void onDamage(GameObject cause, GObjectSprite victim, float damage,
        WeaponClass wclass)
    {
        char[] wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        auto m1 = controller.memberFromGameObject(cause, true);
        auto m2 = controller.memberFromGameObject(victim, false);
        char[] dmgs = myformat("{}", damage);
        if (victim.physics.lifepower < 0) {
            float ov = min(-victim.physics.lifepower, damage);
            mOverDmg += ov;
            dmgs = myformat("{} ({} overdmg)", damage, ov);
        }
        mTotalDmg += damage;
        if (m1 && m2) {
            if (m1 is m2)
                log("worm {} injured himself by {} with {}", m1, dmgs, wname);
            else
                log("worm {} injured {} by {} with {}", m1, m2, dmgs, wname);
        } else if (m1 && !m2) {
            mCollateralDmg += damage;
            log("worm {} caused {} collateral damage with {}", m1, dmgs,
                wname);
        } else if (!m1 && m2) {
            //neutral damage is not caused by weapons
            assert(wclass is null, "some createdBy relation wrong");
            mNeutralDamage += damage;
            log("victim {} received {} damage from neutral objects", m2,
                dmgs);
        } else {
            //most likely level objects blowing up other objects
            //  -> count as collateral
            mCollateralDmg += damage;
            log("unknown damage {}", dmgs);
        }
    }

    private void onDemolition(int pixelCount, GameObject cause) {
        mPixelsDestroyed += pixelCount;
        //log("blasted {} pixels of land", pixelCount);
    }

    private void onFireWeapon(WeaponClass wclass, bool refire = false) {
        char[] wname = "unknown_weapon";
        if (wclass)
            wname = wclass.name;
        log("Fired weapon (refire={}): {}",refire,wname);
        if (!refire) {
            if (!(wclass in mWeaponStats))
                mWeaponStats[wclass] = 1;
            else
                mWeaponStats[wclass] += 1;
            mShotsFired++;
        }
    }

    private void onWormEvent(WormEvent id, ServerTeamMember m) {
        switch (id) {
            case WormEvent.wormActivate:
                log("Worm activate: {}", m);
                break;
            case WormEvent.wormDeactivate:
                log("Worm deactivate: {}", m);
                break;
            case WormEvent.wormDie:
                log("Worm die: {}", m);
                mWormsDied++;
                break;
            case WormEvent.wormDrown:
                int dh = m.currentHealth() - m.health();
                log("Worm drown (floating label would say: {}): {} ", dh, m);
                if (m.health(true) > 0)
                    mWaterDmg += m.health(true);
                mWormsDrowned++;
                break;
            default:
        }
    }

    private void onCrateCollect(ServerTeamMember m, Collectable[] stuffies) {
        log("{} collects crate: {}", m, stuffies);
        mCrateCount++;
    }

    private void onGameEnded() {
        output();
    }

    //xxx for debugging only

    private {
        float mTotalDmg = 0f, mCollateralDmg = 0f, mOverDmg = 0f,
            mWaterDmg = 0f, mNeutralDamage = 0f;
        int mWormsDied, mWormsDrowned, mShotsFired, mPixelsDestroyed,
            mCrateCount;
        int[WeaponClass] mWeaponStats;
    }

    //dump everything to console
    void output() {
        log("Worms killed: {} ({} died, {} drowned)", mWormsDied+mWormsDrowned,
            mWormsDied, mWormsDrowned);
        log("Total damage caused: {}", mTotalDmg);
        log("Damage by water: {}", mWaterDmg);
        log("Collateral damage caused: {}", mCollateralDmg);
        log("Damage by neutral objects: {}", mNeutralDamage);
        log("Total overdamage: {}", mOverDmg);
        log("Shots fired: {}", mShotsFired);
        int c = -1;
        WeaponClass maxw;
        foreach (WeaponClass wc, int count; mWeaponStats) {
            if (count > c) {
                maxw = wc;
                c = count;
            }
        }
        if (maxw)
            log("Favorite weapon: {} ({} shots)", maxw.name, c);
        log("Landscape destroyed: {} pixels", mPixelsDestroyed);
        log("Crates collected: {}", mCrateCount);
    }

    static this() {
        ControllerPluginFactory.register!(typeof(this))("statistics");
    }
}

//this plugin adds persistence functionality for teams (wins / weapons)
//  (overengineering ftw)
class ControllerPersistence : ControllerPlugin {
    private {
        const cKeepWeaponsDef = false;
        const cGiveWeaponsDef = int.max;   //default: always give
        const cVictoryDef = "absolute";
        const cVictoryCountDef = 2;
    }

    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
    }

    mixin(genRegFunc(["onGameStart", "onGameEnded"]));

    private void onGameStart() {
        foreach (t; controller.teams) {
            load(t);
        }
    }

    private void onGameEnded() {
        foreach (t; controller.teams) {
            save(t);
        }

        //reduce round count for giving weapons
        int curGiveWeapons = engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef);
        engine.persistentState.setValue("give_weapons", curGiveWeapons - 1);

        //increase total round count
        engine.persistentState.setValue("round_counter",
            engine.persistentState.getValue("round_counter", 0) + 1);

        //check if we have a winner
        //if the victory condition triggered, the "winner" field will be set,
        //  which can be checked by the GUI
        ServerTeam winner;
        if (checkVictory(engine.persistentState.getStringValue("victory_type",
            cVictoryDef), winner))
        {
            //this was the final round, game is over
            if (winner) {
                engine.persistentState.setStringValue("winner",
                    winner.netId ~ "." ~ winner.id);
            } else {
                //no winner (e.g. game lasted a fixed number of rounds)
                //the game is over anyway, set "winner" field as marker
                engine.persistentState.setStringValue("winner", "draw");
            }
        }

        debug {
            gConf.saveConfig(engine.persistentState, "persistence_debug.conf");
        }
    }

    private void load(ServerTeam t) {
        auto node = persistNode(t);
        t.globalWins = node.getValue!(int)("global_wins", 0);

        //start with empty weapon set if give_weapons not set
        if (engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef) <= 0)
        {
            t.weapons = new WeaponSet(engine);
        }
        //add weapons from last round
        if (engine.persistentState.getValue("keep_weapons", cKeepWeaponsDef)) {
            scope lastRoundWeapons = new WeaponSet(engine,
                node.getSubNode("weapons"));
            t.weapons.addSet(lastRoundWeapons);
        }

        t.crateSpy = node.getValue("crate_spy", t.crateSpy);
        t.doubleDmg = node.getValue("double_damage", t.doubleDmg);
    }

    private void save(ServerTeam t) {
        auto node = persistNode(t);
        node.setValue!(int)("global_wins", t.globalWins);

        //save this round's weapons
        if (engine.persistentState.getValue("keep_weapons", cKeepWeaponsDef)) {
            t.weapons.saveToConfig(node.getSubNode("weapons"));
        }

        node.setValue("crate_spy", t.crateSpy);
        node.setValue("double_damage", t.doubleDmg);
    }

    //return true if the game is over
    //xxx this does not have to be here, all needed information is in
    //    engine.persistentState
    private bool checkVictory(char[] condition, out ServerTeam winner) {
        //first check error cases (0 or 1 team in the game)
        //Note: even if teams surrender or leave during game, they are not
        //      removed from this list
        if (controller.teams.length == 0)
            return true;
        if (controller.teams.length == 1) {
            winner = controller.teams[0];
            return true;
        }

        //determine first and second by number of wins
        ServerTeam first, second;
        foreach (t; controller.teams) {
            if (!first || t.globalWins >= first.globalWins) {
                second = first;
                first = t;
            }
        }
        assert(!!first && !!second);

        //now check victory condition
        int rounds = engine.persistentState.getValue("round_counter", 1);
        int victoryCount = engine.persistentState.getValue("victory_count",
            cVictoryCountDef);
        switch (condition) {
            case "difference":
                //need at least victoryCount more than second place
                if (first.globalWins >= second.globalWins + victoryCount)
                {
                    winner = first;
                    return true;
                }
                break;
            case "rounds":
                //play a fixed number of rounds
                if (rounds >= victoryCount) {
                    //best team wins
                    if (first.globalWins > second.globalWins)
                        winner = first;
                    return true;
                }
                break;
            case "absolute":
            default:  //"absolute" is the default
                //win if a fixed number of points is reached
                if (first.globalWins >= victoryCount) {
                    winner = first;
                    return true;
                }
                break;
        }
        return false;
    }

    private ConfigNode persistNode(ServerTeam t) {
        return engine.persistentState.getSubNode(
            t.netId ~ "." ~ t.id);
    }

    static this() {
        ControllerPluginFactory.register!(typeof(this))("persistence");
    }
}
