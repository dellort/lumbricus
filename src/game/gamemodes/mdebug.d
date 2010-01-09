module game.gamemodes.mdebug;

import framework.framework;
import utils.timesource;
import game.game;
import game.controller;
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
        Team mPreviousTeam;
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
    }

    this(ReflectCtor c) {
        super(c);
    }

    void simulate() {
        super.simulate();
        //if active team is dead or so, pick new one
        foreach (Team t; logic.teams) {
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

    static this() {
        GamemodeFactory.register!(typeof(this))("debug");
    }
}
