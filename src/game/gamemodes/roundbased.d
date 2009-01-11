module game.gamemodes.roundbased;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.roundbased_shared;

import utils.array;
import utils.time;
import utils.misc;
import utils.mybox;

class ModeRoundbased : Gamemode {
    private {
        RoundState mCurrentRoundState = RoundState.nextOnHold;
        Time mWinRemaining, mCleanupWait;

        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;

        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        RoundbasedStatus mStatus;
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mTimePerRound = timeSecs(config.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(
            config.getIntValue("hotseattime",5));
    }

    override void initialize() {
        super.initialize();
    }

    override void startGame() {
        super.startGame();
    }

    void simulate() {
        Time dt = engine.gameTime.difference;
        RoundState next = doState(dt);
        if (next != mCurrentRoundState)
            transition(next);
    }

    //utility functions to get/set active team (and ensure only one is active)
    private void currentTeam(ServerTeam c) {
        if (mCurrentTeam)
            logic.activateTeam(mCurrentTeam, false);
        mCurrentTeam = c;
        if (mCurrentTeam)
            logic.activateTeam(mCurrentTeam);
    }
    private ServerTeam currentTeam() {
        return mCurrentTeam;
    }

    //lol, just like before
    private RoundState doState(Time deltaT) {
        switch (mCurrentRoundState) {
            case RoundState.prepare:
                mStatus.prepareRemaining = mStatus.prepareRemaining - deltaT;
                if (mCurrentTeam.teamAction())
                    //worm moved -> exit prepare phase
                    return RoundState.playing;
                if (mStatus.prepareRemaining < timeMusecs(0))
                    return RoundState.playing;
                break;
            case RoundState.playing:
                mStatus.roundRemaining = max(mStatus.roundRemaining - deltaT, timeNull);
                if (!mCurrentTeam.current)
                    return RoundState.waitForSilence;
                if (mStatus.roundRemaining <= timeMusecs(0))   //timeout
                {
                    //check if we need to wait because worm is performing
                    //a non-abortable action
                    if (!mCurrentTeam.current.delayedAction)
                        return RoundState.waitForSilence;
                }
                if (!mCurrentTeam.current.isAlive       //active worm dead
                    || mCurrentTeam.current.lifeLost)   //active worm damaged
                {
                    mCurrentTeam.current.forceAbort();
                    return RoundState.waitForSilence;
                }
                break;
            case RoundState.waitForSilence:
                if (!engine.checkForActivity) {
                    //hope the game stays inactive
                    return RoundState.cleaningUp;
                }
                break;
            case RoundState.cleaningUp:
                mStatus.roundRemaining = timeSecs(0);
                mCleanupWait = max(mCleanupWait - deltaT, timeNull);
                //not yet
                if (mCleanupWait <= timeMusecs(0))
                    return logic.checkDyingWorms()
                        ? RoundState.waitForSilence : RoundState.nextOnHold;
                break;
            case RoundState.nextOnHold:
                if (logic.messageIsIdle() && logic.objectsIdle())
                    return RoundState.prepare;
                break;
            case RoundState.winning:
                mWinRemaining -= deltaT;
                if (mWinRemaining < timeMusecs(0))
                    return RoundState.end;
                break;
            case RoundState.end:
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
    again:
        assert(st != mCurrentRoundState);
        logic.mLog("state transition %s -> %s", cast(int)mCurrentRoundState,
            cast(int)st);
        mCurrentRoundState = st;
        switch (st) {
            case RoundState.prepare:
                mStatus.roundRemaining = mTimePerRound;
                mStatus.prepareRemaining = mHotseatSwitchTime;

                //select next team/worm
                ServerTeam next = arrayFindNextPred(logic.teams, mLastTeam,
                    (ServerTeam t) {
                        return t.isAlive();
                    }
                );
                currentTeam = null;

                //check if at least two teams are alive
                int aliveTeams;
                foreach (t; logic.teams) {
                    aliveTeams += t.isAlive() ? 1 : 0;
                }

                assert((aliveTeams == 0) != !!next); //no teams, no next

                if (aliveTeams < 2) {
                    if (aliveTeams == 0) {
                        logic.messageAdd("msgnowin");
                        st = RoundState.end;
                    } else {
                        next.youWinNow();
                        logic.messageAdd("msgwin", [next.name]);
                        st = RoundState.winning;
                    }
                    //very sry
                    goto again;
                }

                mLastTeam = next;
                currentTeam = next;
                logic.mLog("active: %s", next);

                break;
            case RoundState.playing:
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(false);
                mStatus.prepareRemaining = timeMusecs(0);
                break;
            case RoundState.waitForSilence:
                //no control while blowing up worms
                if (mCurrentTeam)
                    mCurrentTeam.setOnHold(true);
                //if it's the round's end, also take control early enough
                currentTeam =  null;
                break;
            case RoundState.cleaningUp:
                mCleanupWait = timeMsecs(400);
                logic.updateHealth(); //hmmm
                //see doState()
                break;
            case RoundState.nextOnHold:
                currentTeam = null;
                logic.messageAdd("msgnextround");
                mStatus.roundRemaining = timeMusecs(0);
                break;
            case RoundState.winning:
                //how long winning animation is showed
                mWinRemaining = timeSecs(5);
                break;
            case RoundState.end:
                logic.messageAdd("msggameend");
                currentTeam = null;
                break;
        }
    }

    bool ended() {
        return mCurrentRoundState == RoundState.end;
    }

    int state() {
        return mCurrentRoundState;
    }

    MyBox getStatus() {
        return MyBox.Box(mStatus);
    }

    static this() {
        GamemodeFactory.register!(typeof(this))(cRoundbased);
    }
}
