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
        Time mCrateInterval, mWaterInterval;
        Time mGameTime;
        int mMaxCrates = 10;
        int mSuddenDeathWaterRaise = 32;

        const cWinTime = timeSecs(5);
        //time from being hit until you can move again
        const cHitDelay = timeMsecs(1000);
        //time of inactivity until health update / worm blowup
        const cUpdateDelay = timeSecs(2.5f);
        //time of inactivity until a worm can become active
        const cActivateDelay = timeMsecs(500);
        Time[ServerTeam] mTeamDeactivateTime;
        RealtimeStatus mStatus;
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mStatus = new RealtimeStatus();
        mCrateInterval = timeSecs(config.getIntValue("crate_interval", 10));
        mWaterInterval = timeSecs(config.getIntValue("water_interval", 15));
        mGameTime = timeSecs(config.getIntValue("gametime", 120));
        mMaxCrates = config.getIntValue("maxcrates", mMaxCrates);
        mSuddenDeathWaterRaise = config.getIntValue("water_raise",
            mSuddenDeathWaterRaise);
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
        mStatus.gameRemaining = max(mGameTime - modeTime.current(), Time.Null);

        //--------- Winning and game end ----------------

        if (mGameEndedInt) {
            if (wait(cWinTime, 2, false))
                mGameEnded = true;
            return;
        }
        int aliveCount;
        ServerTeam lastteam;
        foreach (t; logic.teams()) {
            if (t.alive()) {
                aliveCount++;
                lastteam = t;
            }
        }
        if (aliveCount < 2) {
            //"Controlled shutdown": deactivate teams, wait for silence,
            //  blow up worms, end game
            modeTime.paused = true;
            logic.deactivateAll();
            if (engine.checkForActivity)
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
            engine.events.call("onVictory", lastteam);
            return;
        }

        //----------------- Sudden death ----------------

        if (mStatus.gameRemaining <= Time.Null && !mStatus.suddenDeath) {
            mStatus.suddenDeath = true;
            logic.startSuddenDeath();
        }
        if (mStatus.suddenDeath && wait(mWaterInterval, 1)) {
            engine.raiseWater(mSuddenDeathWaterRaise);
        }

        //------------ one crate every mCrateInterval -------------

        if (wait(mCrateInterval) && engine.countSprites("crate") < mMaxCrates) {
            logic.dropCrate();
        }

        //----------- Team activating ---------------

        //check if we need to activate or deactivate a team
        foreach (t; logic.teams()) {
            //check for dying worms
            foreach (ServerTeamMember m; t) {
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
            } else if (!t.current || t.current.lifeLost()) {
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
