module game.controller_plugins;

import common.config;
import framework.i18n;
import game.controller_events;
import game.gamepublic;
import game.controller;
import game.game;
import game.gobject;
import game.sprite;
import game.crate;
import game.weapon.weapon;
import game.gamemodes.base;
import game.gamemodes.mdebug;
import utils.reflection;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.md;

import tango.util.Convert : to;

///let the client display a message (like it's done on round's end etc.)
///this is a bit complicated because message shall be translated on the
///client (i.e. one client might prefer Klingon, while the other is used
///to Latin); so msgid and args are passed to the translation functions
///this returns a value, that is incremented everytime a new message is
///available
///a random int is passed along, so all clients with the same locale
///will select the same message
struct GameMessage {
    LocalizedMessage lm;
    Team actor;    //who did the action (for message color), null for neutral
    Team viewer;   //who should see it (only players with Team
                   //  in getOwnedTeams() see the message), null for all
}

//the idea was that the whole game state should be observable (including
//events), so you can move displaying all messages into a separate piece of
//code, instead of creating messages directly
class ControllerMsgs : ControllerPlugin {
    private {
        const cMessageTime = timeSecs(1.5f);
        Time mLastMsgTime;
        int mMessageCounter;
        GameMessage[] mPendingMessages;
    }

    //clients register here to receive messages (not serialized)
    MDelegate!(GameMessage) showMessage;

    this(GameController c) {
        super(c);
    }
    this(ReflectCtor c) {
        super(c);
        c.transient(this, &showMessage);
    }

    mixin(genRegFunc(["onGameStart", "onSelectWeapon", "onWormEvent",
        "onTeamEvent", "onCrateDrop", "onCrateCollect", "onSuddenDeath",
        "onVictory", "onGameEnded"]));

    private void onGameStart(Gamemode mode) {
        messageAdd("msggamestart", null);
        if (cast(ModeDebug)mode) {
            messageAdd("msgdebuground");
        }
    }

    private void onSelectWeapon(ServerTeamMember m, WeaponClass wclass) {
        //xxx just copying old code... maybe this can be extended to show
        //    grenade timer messages (like in wwp)
        /*if (wclass) {
            messageAdd("msgselweapon", ["_.weapons." ~ wclass.name],
                m.team, m.team);
        } else {
            messageAdd("msgnoweapon", null, m.team, m.team);
        }*/
    }

    private void onWormEvent(WormEvent id, ServerTeamMember m) {
        switch (id) {
            case WormEvent.wormActivate:
                messageAdd("msgwormstartmove", [m.name], m.team,
                    m.team);
                break;
            case WormEvent.wormDrown:
                messageAdd("msgdrown", [m.name], m.team);
                break;
            case WormEvent.wormDie:
                messageAdd("msgdie", [m.name], m.team);
                break;
            default:
        }
    }

    private void onTeamEvent(TeamEvent id, ServerTeam t) {
        switch (id) {
            case TeamEvent.skipTurn:
                messageAdd("msgskipturn", [t.name()], t);
                break;
            case TeamEvent.surrender:
                messageAdd("msgsurrender", [t.name()], t);
                break;
            default:
        }
    }

    private void onCrateDrop(CrateType type) {
        switch (type) {
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

    private void onCrateCollect(ServerTeamMember member,
        Collectable[] stuffies)
    {
        foreach (item; stuffies) {
            if (auto weapon = cast(CollectableWeapon)item) {
                //weapon
                messageAdd("collect_item", [member.name(),
                    "_." ~ item.id(), to!(char[])(weapon.quantity)],
                    member.team, member.team);
            } else if (auto medkit = cast(CollectableMedkit)item) {
                //medkit
                messageAdd("collect_medkit", [member.name(),
                    to!(char[])(medkit.amount)], member.team, member.team);
            } else if (auto tool = cast(CollectableTool)item) {
                //tool
                messageAdd("collect_tool", [member.name(),
                    "_." ~ item.id()], member.team, member.team);
            } else if (auto bomb = cast(CollectableBomb)item) {
                //crate with bomb
                messageAdd("collect_bomb", [member.name()],
                    member.team, member.team);
            }
        }
    }

    private void onSuddenDeath() {
        messageAdd("msgsuddendeath");
    }

    private void onVictory(Team winner) {
        if (winner) {
            messageAdd("msgwin", [winner.name], winner);
        } else {
            messageAdd("msgnowin");
        }
    }

    private void onGameEnded() {
        //xxx is this really useful? I would prefer showing the
        //  "team xxx won" message longer
        messageAdd("msggameend");
    }

    private void messageAdd(char[] msg, char[][] args = null, Team actor = null,
        Team viewer = null)
    {
        isIdle(); //maybe reset wait time
        if (mMessageCounter == 0)
            mLastMsgTime = engine.gameTime.current;
        mMessageCounter++;

        GameMessage gameMsg;
        gameMsg.lm.id = msg;
        gameMsg.lm.args = args;
        gameMsg.lm.rnd = engine.rnd.next;
        gameMsg.actor = actor;
        gameMsg.viewer = viewer;
        showMessage(gameMsg);
    }

    override bool isIdle() {
        //xxx actually, this is a bit wrong, because even messages the client
        //    won't see (viewer field set) count for wait time
        //    But to stay deterministic, we can't consider that
        if (mLastMsgTime + cMessageTime*mMessageCounter
            <= engine.gameTime.current)
        {
            //did wait long enough
            mMessageCounter = 0;
            return true;
        }
        return false;
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

    mixin(genRegFunc(["onGameStart", "onGameEnded", "onVictory"]));

    private void onGameStart(Gamemode mode) {
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
                    winner.uniqueId);
            } else {
                //no winner (e.g. game lasted a fixed number of rounds)
                //the game is over anyway, set "winner" field as marker
                engine.persistentState.setStringValue("winner", "");
            }
        } else {
            engine.persistentState.remove("winner");
        }

        debug {
            gConf.saveConfig(engine.persistentState, "persistence_debug.conf");
        }
    }

    private void onVictory(Team winner) {
        //xxx why Team anyway?
        auto wst = cast(ServerTeam)winner;
        //store winner of current round
        if (wst) {
            engine.persistentState.setStringValue("round_winner",
                wst.uniqueId);
        } else {
            //draw
            engine.persistentState.setStringValue("round_winner", "");
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
            } else if (!second || t.globalWins >= second.globalWins) {
                second = t;
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
        return engine.persistentState.getSubNode("teams").getSubNode(
            t.uniqueId);
    }

    static this() {
        ControllerPluginFactory.register!(typeof(this))("persistence");
    }
}
