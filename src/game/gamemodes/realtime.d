module game.gamemodes.realtime;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;

import utils.array;
import utils.configfile;
import utils.reflection;
import utils.time;
import utils.misc;
import utils.mybox;
import utils.log;

//multiple players at the same time
class ModeRealtime : Gamemode {
    private {
        //static LogStruct!("gamemodes.mdebug") log;
        bool mGameEnded;
        const cCrateDelay = timeSecs(10);
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
    }

    this(ReflectCtor c) {
        super(c);
    }

    override void initialize() {
        super.initialize();
    }

    override void startGame() {
        super.startGame();
        foreach (t; logic.teams()) {
            logic.activateTeam(t);
        }
    }

    void simulate() {
        super.simulate();
        int a;
        ServerTeam lastteam;
        foreach (t; logic.teams()) {
            if (t.alive()) {
                a++;
                lastteam = t;
            }
        }
        if (a == 0) {
            logic.messageAdd("msgnowin");
            mGameEnded = true;
        } else if (a == 1) {
            lastteam.youWinNow();
            logic.messageAdd("msgwin", [lastteam.name]);
            mGameEnded = true;
        }
        if (mGameEnded)
            return;

        if (wait(cCrateDelay)) {
            logic.dropCrate();
        }

        logic.checkDyingWorms();
        //if active team is dead or so, pick new one
        foreach (t; logic.teams()) {
            if (!t.current || t.current.lifeLost()) {
                logic.activateTeam(t, false);
                t.updateHealth();
                logic.activateTeam(t);
            }
        }
    }

    bool ended() {
        return mGameEnded;
    }

    Object getStatus() {
        return null;
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("realtime");
    }
}
