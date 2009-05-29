module game.gamemodes.mdebug;

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

//maximum freedom + possibly some debugging foo
class ModeDebug : Gamemode {
    private {
        //static LogStruct!("gamemodes.mdebug") log;
        ServerTeam mPreviousTeam;
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
        logic.messageAdd("msgdebuground");
    }

    void simulate() {
        super.simulate();
        //if active team is dead or so, pick new one
        foreach (ServerTeam t; logic.teams) {
            if (t.alive) {
                if (!t.active) {
                    if (mPreviousTeam) {
                        logic.activateTeam(mPreviousTeam, false);
                    }
                    logic.activateTeam(t);
                }
                mPreviousTeam = t;
                break;
            }
        }
    }

    bool ended() {
        return false;
    }

    Object getStatus() {
        return null;
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("debug");
    }
}
