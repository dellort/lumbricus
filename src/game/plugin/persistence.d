module game.plugin.persistence;

import game.controller;
import game.core;
import game.plugins;
import game.weapon.weapon;
import game.weapon.weaponset;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.time;

//this plugin adds persistence functionality for teams (wins / weapons)
//  (overengineering ftw)
class ControllerPersistence : GameObject {
    private {
        const cKeepWeaponsDef = false;
        const cGiveWeaponsDef = int.max;   //default: always give
        const cVictoryDef = "absolute";
        const cVictoryCountDef = 2;
        GameController mController;
    }

    this(GameCore c, ConfigNode o) {
        super(c, "persist_plugin");
        mController = engine.singleton!(GameController)();
        OnGameStart.handler(engine.events, &onGameStart);
        OnGameEnd.handler(engine.events, &onGameEnd);
        OnVictory.handler(engine.events, &onVictory);
    }

    private void onGameStart() {
        foreach (t; mController.teams) {
            load(t);
        }
    }

    private void onGameEnd() {
        foreach (t; mController.teams) {
            save(t);
        }

        //reduce round count for giving weapons
        int curGiveWeapons = engine.persistentState.getValue("give_weapons",
            cGiveWeaponsDef);
        engine.persistentState.setValue("give_weapons", curGiveWeapons - 1);

        //check if we have a game winner (!= round winner)
        //if the victory condition triggered, the "winner" field will be set,
        //  which can be checked by the GUI
        Team winner;
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
    }

    //called when a round winner is determined
    private void onVictory(Team winner) {
        //store winner of current round
        if (winner) {
            engine.persistentState.setStringValue("round_winner",
                winner.uniqueId);
        } else {
            //draw
            engine.persistentState.setStringValue("round_winner", "");
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
        if (mController.teams.length == 0)
            return true;
        if (mController.teams.length == 1) {
            winner = mController.teams[0];
            return true;
        }

        //determine first and second by number of wins
        Team first, second;
        foreach (t; mController.teams) {
            if (!first || t.globalWins >= first.globalWins) {
                second = first;
                first = t;
            } else if (!second || t.globalWins >= second.globalWins) {
                second = t;
            }
        }
        assert(!!first && !!second);

        //now check victory condition
        int rounds = mController.currentRound + 1;
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

    override bool activity() {
        return false;
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("persistence");
    }
}
