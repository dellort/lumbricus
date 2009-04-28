module game.gamemodes.realtime;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.roundbased_shared;

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
            logic.deactivateAll();
            if (engine.checkForActivity)
                return;
            logic.updateHealth();
            if (logic.checkDyingWorms())
                return;
            mGameEndedInt = true;
            if (aliveCount == 0) {
                logic.messageAdd("msgnowin");
            } else {
                lastteam.youWinNow();
                logic.messageAdd("msgwin", [lastteam.name]);
            }
        }

        //----------------- Sudden death ----------------

        if (mStatus.gameRemaining <= Time.Null && !mStatus.suddenDeath) {
            mStatus.suddenDeath = true;
            engine.callbacks.nukeSplatEffect();
            logic.messageAdd("msgsuddendeath");
        }
        if (mStatus.suddenDeath && wait(mWaterInterval, 1)) {
            engine.raiseWater(mSuddenDeathWaterRaise);
        }

        //------------ one crate every mCrateInterval -------------

        if (wait(mCrateInterval) && engine.countSprites("crate") < mMaxCrates) {
            logic.messageAdd("msgcrate");
            logic.dropCrate();
        }

        //----------- Team activating ---------------

        //xxx worm blowup every frame, better ideas?
        logic.checkDyingWorms();
        //check if we need to activate or deactivate a team
        foreach (t; logic.teams()) {
            if (!t.active) {
                //if a worm was hit, force a cHitDelay pause on the team
                if ((!(t in mTeamDeactivateTime))
                    || (modeTime.current - mTeamDeactivateTime[t] > cHitDelay))
                {
                    logic.activateTeam(t);
                }
            } else if (!t.current || t.current.lifeLost()) {
                //worm change if the current worm was hit
                logic.activateTeam(t, false);
                //xxx what about other team members being hit? health
                //    may not update for a long time
                t.updateHealth();
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
