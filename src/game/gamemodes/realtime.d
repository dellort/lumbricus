module game.gamemodes.realtime;

import utils.timesource;
import game.controller;
import game.core;
import game.game;
import game.plugins;
import game.plugin.crate;
import game.gamemodes.base;
import game.hud.gametimer;
import game.hud.preparedisplay;

import utils.array;
import utils.configfile;
import utils.time;
import utils.misc;
import utils.mybox;
import utils.log;

//multiple players at the same time
class ModeRealtime : Gamemode {
    private {
        //static LogStruct!("gamemodes.mdebug") log;
        bool mGameEndedInt, mGameEnded;

        struct ModeConfig {
            //regular crate drops
            Time crate_interval = timeSecs(10);
            //after gametime expired, raise water every xx secs
            Time water_interval = timeSecs(15);
            Time gametime = timeSecs(120);
            //max number of crates in the field
            int maxcrates = 10;
            int water_raise = 32;
            //only take control if that many hp were lost
            int stamina_power = 10;
        }
        ModeConfig config;

        enum cWinTime = timeSecs(4);
        //time from being hit until you can move again
        enum cHitDelay = timeMsecs(1000);
        //time of inactivity until health update / worm blowup
        enum cUpdateDelay = timeSecs(2.5f);
        //time of inactivity until a worm can become active
        enum cActivateDelay = timeMsecs(500);
        //how long you can still move before control is taken on victory
        enum cWinRetreatTime = timeSecs(10);
        Time[Team] mTeamDeactivateTime;
        HudGameTimer mStatus;
        bool mSuddenDeath;
        CratePlugin mCratePlugin;
    }

    this(GameCore a_engine, ConfigNode config) {
        super(a_engine);
        //all teams would be constantly flashing
        mTeamView.flashActive = false;
        mStatus = new HudGameTimer(engine);
        mStatus.showGameTime = true;
        this.config = config.getCurValue!(ModeConfig)();
    }

    override void startGame() {
        super.startGame();
        mCratePlugin = engine.querySingleton!(CratePlugin);
    }

    override void simulate() {
        super.simulate();
        mStatus.gameRemaining = max(config.gametime - modeTime.current(),
            Time.Null);

        //--------- Winning and game end ----------------

        if (mGameEndedInt) {
            if (!mGameEnded && wait(cWinTime, 2, false)) {
                logic.endGame();
                mGameEnded = true;
            }
            return;
        }
        Team lastteam;
        int aliveCount = aliveTeams(lastteam);
        if (aliveCount < 2) {
            //"Controlled shutdown": deactivate teams, wait for silence,
            //  blow up worms, end game
            mStatus.showGameTime = false;
            mStatus.showTurnTime = true;
            modeTime.paused = true;
            bool engAct = engine.checkForActivity;
            if (lastteam && lastteam.active) {
                //the winner is still trying to get to safety
                mStatus.turnRemaining = waitRemain(cWinRetreatTime,2,false);
                if (engAct && mStatus.turnRemaining > Time.Null)
                    return;
                logic.deactivateAll();
            }
            mStatus.turnRemaining = Time.Null;
            mStatus.showTurnTime = false;
            if (engAct)
                return;
            logic.updateHealth();
            if (logic.checkDyingWorms())
                return;
            mGameEndedInt = true;
            waitReset(2);
            if (aliveCount > 0) {
                assert(!!lastteam);
                lastteam.youWinNow();
            }
            return;
        }

        //----------------- Sudden death ----------------

        if (mStatus.gameRemaining <= Time.Null && !mSuddenDeath) {
            mSuddenDeath = true;
            logic.startSuddenDeath();
        }
        if (mSuddenDeath && wait(config.water_interval, 1)) {
            engine.raiseWater(config.water_raise);
        }

        //------------ one crate every mCrateInterval -------------

        if (mCratePlugin && wait(config.crate_interval)
            && engine.countSprites("crate") < config.maxcrates)
        {
            mCratePlugin.dropCrate();
        }

        //----------- Team activating ---------------

        //check if we need to activate or deactivate a team
        foreach (t; logic.teams()) {
            //check for dying worms
            foreach (TeamMember m; t) {
                //only blow up inactive worms
                //Note: might blow up several worms concurrently,
                //      I don't see any problems
                if (engine.gameTime.current - m.control.lastActivity
                    > cUpdateDelay)
                {
                    m.checkDying();
                    m.updateHealth();
                }
            }
            if (!t.active) {
                //if a worm was hit, force a cHitDelay pause on the team
                if ((!(t in mTeamDeactivateTime))
                    || (modeTime.current - mTeamDeactivateTime[t] > cHitDelay))
                {
                    //only activate worms that are not currently moving
                    if (t.nextWasIdle(cActivateDelay)) {
                        t.active = true;
                    }
                }
            } else if (!t.current || t.current.lifeLost(config.stamina_power)) {
                //worm change if the current worm was hit
                t.active = false;
                mTeamDeactivateTime[t] = modeTime.current();
            }
        }
    }

    static this() {
        GamePluginFactory.register!(typeof(this))("realtime");
    }
}
