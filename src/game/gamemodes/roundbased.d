module game.gamemodes.roundbased;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.roundbased_shared;

import utils.array;
import utils.reflection;
import utils.time;
import utils.misc;
import utils.mybox;

class ModeRoundbased : Gamemode {
    private {
        RoundState mCurrentRoundState = RoundState.waitForSilence;
        Time mWaitStart;

        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;
        //time the worm can still move after firing a weapon
        Time mRetreatTime;
        //can the active worm be chosen in prepare state?
        bool mAllowSelect;
        //multi-shot mode (true -> firing a weapon doesn't end the round)
        bool mMultishot;
        float mCrateProb = 0.9f;
        int mMaxCrates = 8;

        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        RoundbasedStatus mStatus;
        int mCrateCtr = 1;

        const cSilenceWait = timeMsecs(400);
        const cNextRoundWait = timeMsecs(750);
        //how long winning animation is shown
        const cWinTime = timeSecs(5);
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mTimePerRound = timeSecs(config.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(config.getIntValue("hotseattime",5));
        mRetreatTime = timeSecs(config.getIntValue("retreattime",5));
        mAllowSelect = config.getBoolValue("allowselect", mAllowSelect);
        mMultishot = config.getBoolValue("multishot", mMultishot);
        mCrateProb = config.getFloatValue("crateprob", mCrateProb);
        mMaxCrates = config.getIntValue("maxcrates", mMaxCrates);
    }

    this(ReflectCtor c) {
        super(c);
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
                mStatus.roundRemaining = max(mStatus.roundRemaining - deltaT,
                    timeNull);
                if (!mCurrentTeam.current)
                    return RoundState.waitForSilence;
                if (mStatus.roundRemaining <= timeMusecs(0))   //timeout
                {
                    //check if we need to wait because worm is performing
                    //a non-abortable action
                    if (!mCurrentTeam.current.delayedAction)
                        return RoundState.waitForSilence;
                }
                //if not in multishot mode, firing ends the round
                if (!mMultishot && mCurrentTeam.current.weaponUsed)
                    return RoundState.retreat;
                if (!mCurrentTeam.current.isAlive       //active worm dead
                    || mCurrentTeam.current.lifeLost)   //active worm damaged
                {
                    return RoundState.waitForSilence;
                }
                break;
            //only used if mMultishot == false
            case RoundState.retreat:
                //give him some time to run, hehe
                if (engine.gameTime.current-mWaitStart > mRetreatTime
                    || !mCurrentTeam.current.isAlive
                    || mCurrentTeam.current.lifeLost)
                    return RoundState.waitForSilence;
                break;
            case RoundState.waitForSilence:
                //check over a period, to avoid one-frame errors
                if (!engine.checkForActivity) {
                    if (engine.gameTime.current-mWaitStart > cSilenceWait) {
                        //hope the game stays inactive
                        return RoundState.cleaningUp;
                    }
                } else {
                    mWaitStart = engine.gameTime.current;
                }
                break;
            case RoundState.cleaningUp:
                mStatus.roundRemaining = timeSecs(0);
                //if there are more to blow up, go back to waiting
                if (logic.checkDyingWorms())
                    return RoundState.waitForSilence;

                //wait some msecs to show the health labels
                if (engine.gameTime.current-mWaitStart > cNextRoundWait) {
                    //check if at least two teams are alive
                    int aliveTeams;
                    ServerTeam firstAlive;
                    foreach (t; logic.teams) {
                        if (t.isAlive()) {
                            aliveTeams++;
                            firstAlive = t;
                        }
                    }

                    if (aliveTeams < 2) {
                        if (aliveTeams == 0) {
                            logic.messageAdd("msgnowin");
                            return RoundState.end;
                        } else {
                            assert(firstAlive);
                            firstAlive.youWinNow();
                            logic.messageAdd("msgwin", [firstAlive.name]);
                            return RoundState.winning;
                        }
                    }

                    //probably drop a crate, if not too many on the field already
                    if (mCrateCtr > 0 && engine.rnd.nextDouble2 < mCrateProb
                        && engine.countSprites("crate") < mMaxCrates)
                    {
                        mCrateCtr--;
                        if (logic.dropCrate()) {
                            logic.messageAdd("msgcrate");
                            return RoundState.waitForSilence;
                        }
                    }

                    return RoundState.nextOnHold;
                }
                break;
            case RoundState.nextOnHold:
                if (logic.messageIsIdle() && logic.objectsIdle())
                    return RoundState.prepare;
                break;
            case RoundState.winning:
                if (engine.gameTime.current-mWaitStart > cWinTime)
                    return RoundState.end;
                break;
            case RoundState.end:
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
        assert(st != mCurrentRoundState);
        logic.mLog("state transition %s -> %s", cast(int)mCurrentRoundState,
            cast(int)st);
        mCurrentRoundState = st;
        switch (st) {
            case RoundState.prepare:
                mStatus.roundRemaining = mTimePerRound;
                mStatus.prepareRemaining = mHotseatSwitchTime;
                mCrateCtr = 1;

                //select next team/worm
                ServerTeam next = arrayFindNextPred(logic.teams, mLastTeam,
                    (ServerTeam t) {
                        return t.isAlive();
                    }
                );
                currentTeam = null;

                assert(next); //should've dropped out in nextOnHold otherwise

                mLastTeam = next;
                currentTeam = next;
                if (mAllowSelect)
                    mCurrentTeam.allowSelect = true;
                logic.mLog("active: %s", next);

                break;
            case RoundState.playing:
                assert(mCurrentTeam);
                mCurrentTeam.setOnHold(false);
                if (mAllowSelect)
                    mCurrentTeam.allowSelect = false;
                mStatus.prepareRemaining = timeMusecs(0);
                break;
            case RoundState.retreat:
                mWaitStart = engine.gameTime.current;
                mCurrentTeam.current.setLimitedMode();
                break;
            case RoundState.waitForSilence:
                mWaitStart = engine.gameTime.current;
                //no control while blowing up worms
                if (mCurrentTeam) {
                    mCurrentTeam.current.forceAbort();
                    mCurrentTeam.setOnHold(true);
                }
                //if it's the round's end, also take control early enough
                currentTeam =  null;
                break;
            case RoundState.cleaningUp:
                //next call causes health countdown, so wait a little
                mWaitStart = engine.gameTime.current;
                logic.updateHealth(); //hmmm
                //see doState()
                break;
            case RoundState.nextOnHold:
                currentTeam = null;
                logic.messageAdd("msgnextround");
                mStatus.roundRemaining = timeMusecs(0);
                break;
            case RoundState.winning:
                mWaitStart = engine.gameTime.current;
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
