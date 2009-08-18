module game.gamemodes.realtime;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.turnbased_shared;

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

        const cWinTime = timeSecs(4);
        //time from being hit until you can move again
        const cHitDelay = timeMsecs(1000);
        //time of inactivity until health update / worm blowup
        const cUpdateDelay = timeSecs(2.5f);
        //time of inactivity until a worm can become active
        const cActivateDelay = timeMsecs(500);
        //how long you can still move before control is taken on victory
        const cWinRetreatTime = timeSecs(10);
        Time[Team] mTeamDeactivateTime;
        RealtimeStatus mStatus;
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mStatus = new RealtimeStatus();
        this.config = config.getCurValue!(ModeConfig)();
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
        mStatus.gameRemaining = max(config.gametime - modeTime.current(),
            Time.Null);

        //--------- Winning and game end ----------------

        if (mGameEndedInt) {
            if (wait(cWinTime, 2, false))
                mGameEnded = true;
            return;
        }
        Team lastteam;
        int aliveCount = aliveTeams(lastteam);
        if (aliveCount < 2) {
            //"Controlled shutdown": deactivate teams, wait for silence,
            //  blow up worms, end game
            mStatus.gameEnding = true;
            modeTime.paused = true;
            bool engAct = engine.checkForActivity;
            if (lastteam && lastteam.active) {
                //the winner is still trying to get to safety
                mStatus.retreatRemaining = waitRemain(cWinRetreatTime,2,false);
                if (engAct && mStatus.retreatRemaining > Time.Null)
                    return;
                logic.deactivateAll();
            }
            mStatus.retreatRemaining = Time.Null;
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
            logic.events.onVictory(lastteam);
            return;
        }

        //----------------- Sudden death ----------------

        if (mStatus.gameRemaining <= Time.Null && !mStatus.suddenDeath) {
            mStatus.suddenDeath = true;
            logic.startSuddenDeath();
        }
        if (mStatus.suddenDeath && wait(config.water_interval, 1)) {
            engine.raiseWater(config.water_raise);
        }

        //------------ one crate every mCrateInterval -------------

        if (wait(config.crate_interval) && engine.countSprites("crate")
            < config.maxcrates)
        {
            logic.dropCrate();
        }

        //----------- Team activating ---------------

        //check if we need to activate or deactivate a team
        foreach (t; logic.teams()) {
            //check for dying worms
            foreach (TeamMember m; t) {
                //only blow up inactive worms
                //Note: might blow up several worms concurrently,
                //      I don't see any problems
                if (engine.gameTime.current - m.lastActivity > cUpdateDelay) {
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
                    auto next = t.nextActive();
                    if (next && engine.gameTime.current
                        - next.lastActivity > cActivateDelay)
                    {
                        logic.activateTeam(t);
                    }
                }
            } else if (!t.current || t.current.lifeLost(config.stamina_power)) {
                //worm change if the current worm was hit
                logic.activateTeam(t, false);
                mTeamDeactivateTime[t] = modeTime.current();
            }
        }
    }

    bool ended() {
        return mGameEnded;
    }

    Object getStatus() {
        return mStatus;
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("realtime");
    }
}
