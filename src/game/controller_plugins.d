module game.controller_plugins;

import framework.i18n;
import game.controller_events;
import game.controller;
import game.core;
import game.game;
import game.sprite;
import game.crate;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.gamemodes.base;
import physics.misc;
import utils.factory;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.time;

import tango.util.Convert : to;

static this() {
}


//base class for custom plugins
//now I don't really know what the point of this class was anymore
//xxx: this is only for "compatibility"; GamePluginFactory now produces
//  GameObjects (not GamePlugins)
abstract class GamePlugin : GameObject2 {
    private GameController mController;

    this(GameCore c, ConfigNode opts) {
        super(c, "plugin");
        internal_active = true;
    }

    protected GameController controller() {
        if (!mController)
            mController = engine.singleton!(GameController)();
        return mController;
    }

    override bool activity() {
        return false;
    }
}

//and another factory...
//plugins register here, so the Controller can load them
alias StaticFactory!("GamePlugins", GameObject, GameCore, ConfigNode)
    GamePluginFactory;

//the idea was that the whole game state should be observable (including
//events), so you can move displaying all messages into a separate piece of
//code, instead of creating messages directly
class ControllerMsgs : GamePlugin {
    private {
        const cMessageTime = timeSecs(1.5f);
        Time mLastMsgTime;
        int mMessageCounter;
        GameMessage[] mPendingMessages;
        TeamMember mLastMember;
        Team mWinner;
    }

    this(GameCore c, ConfigNode o) {
        super(c, o);
        auto ev = engine.events;
        OnGameStart.handler(ev, &onGameStart);
        OnGameEnd.handler(ev, &onGameEnd);
        OnSuddenDeath.handler(ev, &onSuddenDeath);
        OnSpriteDie.handler(ev, &onSpriteDie);
        OnTeamMemberStartDie.handler(ev, &onTeamMemberStartDie);
        OnTeamMemberSetActive.handler(ev, &onTeamMemberSetActive);
        OnTeamSkipTurn.handler(ev, &onTeamSkipTurn);
        OnTeamSurrender.handler(ev, &onTeamSurrender);
        OnCrateDrop.handler(ev, &onCrateDrop);
        OnTeamMemberCollectCrate.handler(ev, &onCrateCollect);
        OnVictory.handler(ev, &onVictory);
    }

    private void onGameStart(GameObject dummy) {
        messageAdd("msggamestart", null);
    }

    private void onTeamMemberSetActive(TeamMember m, bool active) {
        if (active) {
            messageAdd("msgwormstartmove", [m.name], m.team, true);
        } else {
            mLastMember = m;
        }
    }

    private void onSpriteDie(Sprite sprite) {
        if (!sprite.isUnderWater())
            return;
        TeamMember m = controller.memberFromGameObject(sprite, false);
        if (!m)
            return;
        messageAdd("msgdrown", [m.name], m.team);
    }

    private void onTeamMemberStartDie(TeamMember m) {
        messageAdd("msgdie", [m.name], m.team);
    }

    private void onTeamSkipTurn(Team t) {
        messageAdd("msgskipturn", [t.name()], t);
    }

    private void onTeamSurrender(Team t) {
        messageAdd("msgsurrender", [t.name()], t);
    }

    private void onCrateDrop(CrateSprite sprite) {
        switch (sprite.crateType()) {
            case CrateType.med:
                messageAdd("msgcrate_medkit");
                break;
            case CrateType.tool:
                messageAdd("msgcrate_tool");
                break;
            default:
                messageAdd("msgcrate");
        }
    }

    private void onCrateCollect(TeamMember member, CrateSprite crate) {
        foreach (item; crate.stuffies) {
            //someone lieks code duplication...
            if (auto weapon = cast(CollectableWeapon)item) {
                //weapon
                messageAdd("collect_item", [member.name(),
                    "_." ~ item.id(), to!(char[])(weapon.quantity)],
                    member.team, true);
            } else if (auto medkit = cast(CollectableMedkit)item) {
                //medkit
                messageAdd("collect_medkit", [member.name(),
                    to!(char[])(medkit.amount)], member.team, true);
            } else if (auto tool = cast(CollectableTool)item) {
                //tool
                messageAdd("collect_tool", [member.name(),
                    "_." ~ item.id()], member.team, true);
            } else if (auto bomb = cast(CollectableBomb)item) {
                //crate with bomb
                messageAdd("collect_bomb", [member.name()],
                    member.team, true);
            }
        }
    }

    private void onSuddenDeath(GameObject dummy) {
        messageAdd("msgsuddendeath");
    }

    private void onVictory(Team member) {
        mWinner = member;
        if (mLastMember && mLastMember.team !is mWinner) {
            //xxx this should only be executed for "turnbased" game mode,
            //  but there must be a better way than checking the mode
            //  explicitly
            messageAdd("msgwinstolen",
                [mWinner.name, mLastMember.team.name], mWinner);
        } else {
            messageAdd("msgwin", [mWinner.name], mWinner);
        }
    }

    private void onGameEnd(GameObject dummy) {
        if (!mWinner) {
            messageAdd("msgnowin");
        }
        //xxx is this really useful? I would prefer showing the
        //  "team xxx won" message longer
        messageAdd("msggameend");
    }

    private void messageAdd(char[] msg, char[][] args = null, Team actor = null,
        bool is_private = false)
    {
        activity(); //maybe reset wait time
        if (mMessageCounter == 0)
            mLastMsgTime = engine.gameTime.current;
        mMessageCounter++;

        GameMessage gameMsg;
        gameMsg.lm.id = msg;
        gameMsg.lm.args = args;
        gameMsg.lm.rnd = engine.rnd.next;
        gameMsg.actor = actor;
        gameMsg.is_private = is_private;
        OnGameMessage.raise(engine.globalEvents, gameMsg);
    }

    override bool activity() {
        //xxx actually, this is a bit wrong, because even messages the client
        //    won't see (viewer field set) count for wait time
        //    But to stay deterministic, we can't consider that
        //in other words, all clients wait for the same time
        if (mLastMsgTime + cMessageTime*mMessageCounter
            <= engine.gameTime.current)
        {
            //did wait long enough
            mMessageCounter = 0;
            return false;
        }
        return true;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("messages");
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
class ControllerStats : GamePlugin {
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
            int[char[]] weaponStats;

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
                char[] maxwName;
                foreach (char[] wc, int count; weaponStats) {
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
    }

    this(GameCore c, ConfigNode o) {
        super(c, o);
        OnGameEnd.handler(engine.events, &onGameEnd);
        OnDamage.handler(engine.events, &onDamage);
        OnSpriteDie.handler(engine.events, &onSpriteDie);
//        OnCrateCollect.handler(engine.events, &onCrateCollect);
        OnFireWeapon.handler(engine.events, &onFireWeapon);
    }

    private void onDamage(Sprite victim, GameObject cause, DamageCause type,
        float damage)
    {
        char[] wname = "unknown_weapon";
        WeaponClass wclass = controller.weaponFromGameObject(cause);
        if (wclass)
            wname = wclass.name;
        auto m1 = controller.memberFromGameObject(cause, true);
        auto m2 = controller.memberFromGameObject(victim, false);
        char[] dmgs = myformat("{}", damage);
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

    private void onFireWeapon(Shooter sender, bool refire) {
        char[] wname = "unknown_weapon";
        WeaponClass wclass = sender.weapon;
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
        TeamMember m = controller.memberFromGameObject(sprite, false);
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

    private void onGameEnd(GameObject dummy) {
        debug mStats.output();
        engine.persistentState.setValue("stats", mStats);
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("statistics");
    }
}

//this plugin adds persistence functionality for teams (wins / weapons)
//  (overengineering ftw)
class ControllerPersistence : GamePlugin {
    private {
        const cKeepWeaponsDef = false;
        const cGiveWeaponsDef = int.max;   //default: always give
        const cVictoryDef = "absolute";
        const cVictoryCountDef = 2;
    }

    this(GameCore c, ConfigNode o) {
        super(c, o);
        OnGameStart.handler(engine.events, &onGameStart);
        OnGameEnd.handler(engine.events, &onGameEnd);
    }

    private void onGameStart(GameObject dummy) {
        foreach (t; controller.teams) {
            load(t);
        }
    }

    private void onGameEnd(GameObject dummy) {
        foreach (t; controller.teams) {
            save(t);
        }

        //reduce round count for giving weapons
        int curGiveWeapons = engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef);
        engine.persistentState.setValue("give_weapons", curGiveWeapons - 1);

        //check if we have a winner
        //if the victory condition triggered, the "winner" field will be set,
        //  which can be checked by the GUI
        Team winner;
        if (checkVictory(engine.persistentState.getStringValue("victory_type",
            cVictoryDef), winner))
        {
            //this was the final round, game is over
            if (winner) {
                //xxx round_winner used to be in OnVictory, no idea why this was
                //  duplicated here
                engine.persistentState.setStringValue("round_winner",
                    winner.uniqueId);
                engine.persistentState.setStringValue("winner",
                    winner.uniqueId);
            } else {
                //no winner (e.g. game lasted a fixed number of rounds)
                //the game is over anyway, set "winner" field as marker
                engine.persistentState.setStringValue("round_winner", "");
                engine.persistentState.setStringValue("winner", "");
            }
        } else {
            engine.persistentState.remove("winner");
        }
    }

    private void load(Team t) {
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
            //memorial for bug in revision 1019
            auto lastRoundWeapons = new WeaponSet(engine,
                node.getSubNode("weapons"));
            t.weapons.addSet(lastRoundWeapons);
            lastRoundWeapons.kill();
        }

        t.crateSpy = node.getValue("crate_spy", t.crateSpy);
        t.doubleDmg = node.getValue("double_damage", t.doubleDmg);
    }

    private void save(Team t) {
        auto node = persistNode(t);

        //store some team info (for GUI display)
        //  (engine.persistentState should be all a game summary dialog needs)
        node["name"] = t.name;
        node["id"] = t.id;
        node["net_id"] = t.netId;
        node["color"] = t.color.name;

        node.setValue!(int)("global_wins", t.globalWins);

        //save this round's weapons
        if (engine.persistentState.getValue("keep_weapons", cKeepWeaponsDef)) {
            t.weapons.saveToConfig(node.getSubNode("weapons"));
        }

        //crate spy lasts one round
        node.setValue("crate_spy", max(t.crateSpy - 1, 0));
        //double damage is decreased elsewhere (lasts one turn)
        node.setValue("double_damage", t.doubleDmg);
    }

    //return true if the game is over
    //xxx this does not have to be here, all needed information is in
    //    engine.persistentState
    private bool checkVictory(char[] condition, out Team winner) {
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
        Team first, second;
        foreach (t; controller.teams) {
            if (!first || t.globalWins >= first.globalWins) {
                second = first;
                first = t;
            } else if (!second || t.globalWins >= second.globalWins) {
                second = t;
            }
        }
        assert(!!first && !!second);

        //now check victory condition
        int rounds = controller.currentRound + 1;
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

    private ConfigNode persistNode(Team t) {
        return engine.persistentState.getSubNode("teams").getSubNode(
            t.uniqueId);
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("persistence");
    }
}
