module game.gamemodes.mdebug;

import framework.framework;
import utils.timesource;
import game.game;
import game.controller;
import game.controller_events;
import game.gamemodes.base;

import utils.array;
import utils.configfile;
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

    this(GameEngine a_engine, ConfigNode config) {
        super(a_engine);
    }

    override void simulate(float dt) {
        super.simulate(dt);
        //if active team is dead or so, pick new one
        foreach (Team t; logic.teams) {
            if (t.alive) {
                if (!t.active) {
                    if (mPreviousTeam) {
                        mPreviousTeam.active = false;
                    }
                    t.active = true;
                }
                mPreviousTeam = t;
                break;
            }
        }
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("debug");
    }
}
