module game.gamemodes.roundbased;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.roundbased_shared;
import game.crate;

import utils.array;
import utils.configfile;
import utils.reflection;
import utils.time;
import utils.misc;
import utils.log;

class ModeRoundbased : Gamemode {
    private {
        RoundState mCurrentRoundState = RoundState.waitForSilence;
        static LogStruct!("gamemodes.roundbased") log;

        //time a round takes
        Time mTimePerRound;
        //extra time before round time to switch seats etc
        Time mHotseatSwitchTime;
        //time the worm can still move after firing a weapon
        Time mRetreatTime;
        //total time for one game until sudden death begins
        Time mGameTime;
        //can the active worm be chosen in prepare state?
        bool mAllowSelect;
        //multi-shot mode (true -> firing a weapon doesn't end the round)
        bool mMultishot;
        float mCrateProb = 0.9f;
        int mMaxCrates = 8;
        int mSuddenDeathWaterRaise = 50;

        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        RoundbasedStatus mStatus;
        int mCleanupCtr = 1;

        const cSilenceWait = timeMsecs(400);
        const cNextRoundWait = timeMsecs(750);
        //how long winning animation is shown
        const cWinTime = timeSecs(5);
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mStatus = new RoundbasedStatus();
        mTimePerRound = timeSecs(config.getIntValue("roundtime",15));
        mHotseatSwitchTime = timeSecs(config.getIntValue("hotseattime",5));
        mRetreatTime = timeSecs(config.getIntValue("retreattime",5));
        mGameTime = timeSecs(config.getIntValue("gametime",300));
        mAllowSelect = config.getBoolValue("allowselect", mAllowSelect);
        mMultishot = config.getBoolValue("multishot", mMultishot);
        mCrateProb = config.getFloatValue("crateprob", mCrateProb);
        mMaxCrates = config.getIntValue("maxcrates", mMaxCrates);
        mSuddenDeathWaterRaise = config.getIntValue("water_raise",
            mSuddenDeathWaterRaise);

        parent.collectTool ~= &doCollectTool;
    }

    this(ReflectCtor c) {
        super(c);
    }

    override void initialize() {
        super.initialize();
    }

    override void startGame() {
        super.startGame();
        modeTime.paused = true;
    }

    void simulate() {
        super.simulate();
        mStatus.gameRemaining = max(mGameTime - modeTime.current(), Time.Null);
        //this ensures that after each transition(), doState() is also run
        //in the same frame
        RoundState next;
        while ((next = doState()) != mCurrentRoundState) {
            transition(next);
        }
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
    private RoundState doState() {
        switch (mCurrentRoundState) {
            case RoundState.prepare:
                mStatus.prepareRemaining = waitRemain(mHotseatSwitchTime, 1,
                    false);
                if (mCurrentTeam.teamAction())
                    //worm moved -> exit prepare phase
                    return RoundState.playing;
                if (mStatus.prepareRemaining <= Time.Null)
                    return RoundState.playing;
                break;
            case RoundState.playing:
                mStatus.roundRemaining = waitRemain!(true)(mTimePerRound, 1,
                    false);
                if (!mCurrentTeam.current)
                    return RoundState.waitForSilence;
                if (mCurrentTeam.allowSelect && mCurrentTeam.teamAction())
                    //no changing worm after action
                    mCurrentTeam.allowSelect = false;
                if (mStatus.roundRemaining <= Time.Null)   //timeout
                {
                    //check if we need to wait because worm is performing
                    //a non-abortable action
                    if (!mCurrentTeam.current.delayedAction)
                        return RoundState.waitForSilence;
                }
                //if not in multishot mode, firing ends the round
                if (!mMultishot && mCurrentTeam.current.weaponUsed)
                    return RoundState.retreat;
                if (!mCurrentTeam.current.alive       //active worm dead
                    || mCurrentTeam.current.lifeLost)   //active worm damaged
                {
                    return RoundState.waitForSilence;
                }
                break;
            //only used if mMultishot == false
            case RoundState.retreat:
                //give him some time to run, hehe
                if (wait(mRetreatTime)
                    || !mCurrentTeam.current.alive
                    || mCurrentTeam.current.lifeLost)
                    return RoundState.waitForSilence;
                break;
            case RoundState.waitForSilence:
                //check over a period, to avoid one-frame errors
                if (!engine.checkForActivity) {
                    if (wait(cSilenceWait)) {
                        //hope the game stays inactive
                        return RoundState.cleaningUp;
                    }
                } else {
                    waitReset();
                }
                break;
            case RoundState.cleaningUp:
                mStatus.roundRemaining = Time.Null;
                //if there are more to blow up, go back to waiting
                if (logic.checkDyingWorms())
                    return RoundState.waitForSilence;

                //wait some msecs to show the health labels
                if (wait(cNextRoundWait) && logic.messageIsIdle()) {
                    //check if at least two teams are alive
                    int aliveTeams;
                    ServerTeam firstAlive;
                    foreach (t; logic.teams) {
                        if (t.alive()) {
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

                    if (mStatus.gameRemaining <= Time.Null
                        && !mStatus.suddenDeath)
                    {
                        mStatus.suddenDeath = true;
                        engine.graphics.add(new NukeSplatEffect());
                        logic.messageAdd("msgsuddendeath");
                    }

                    if (mCleanupCtr > 1) {
                        mCleanupCtr--;
                        if (mStatus.suddenDeath) {
                            engine.raiseWater(mSuddenDeathWaterRaise);
                            return RoundState.waitForSilence;
                        }
                    }
                    //probably drop a crate, if not too many out already
                    if (mCleanupCtr > 0) {
                        mCleanupCtr--;
                        if (engine.rnd.nextDouble2 < mCrateProb
                            && engine.countSprites("crate") < mMaxCrates)
                        {
                            if (logic.dropCrate()) {
                                logic.messageAdd("msgcrate");
                                return RoundState.waitForSilence;
                            }
                        }
                    }

                    return RoundState.nextOnHold;
                }
                break;
            case RoundState.nextOnHold:
                if (logic.messageIsIdle() && logic.membersIdle())
                    return RoundState.prepare;
                break;
            case RoundState.winning:
                if (wait(cWinTime))
                    return RoundState.end;
                break;
            case RoundState.end:
                break;
        }
        return mCurrentRoundState;
    }

    private void transition(RoundState st) {
        assert(st != mCurrentRoundState);
        log("state transition {} -> {}", cast(int)mCurrentRoundState,
            cast(int)st);
        mCurrentRoundState = st;
        switch (st) {
            case RoundState.prepare:
                modeTime.paused = true;
                mStatus.roundRemaining = mTimePerRound;
                waitReset(1);
                waitReset!(true)(1);
                mCleanupCtr = 2;

                //select next team/worm
                ServerTeam next = arrayFindNextPred(logic.teams, mLastTeam,
                    (ServerTeam t) {
                        return t.alive();
                    }
                );
                currentTeam = null;

                assert(next); //should've dropped out in nextOnHold otherwise

                mLastTeam = next;
                currentTeam = next;
                if (mAllowSelect)
                    mCurrentTeam.allowSelect = true;
                log("active: {}", next);

                break;
            case RoundState.playing:
                assert(mCurrentTeam);
                modeTime.paused = false;
                mCurrentTeam.setOnHold(false);
                mStatus.prepareRemaining = Time.Null;
                break;
            case RoundState.retreat:
                modeTime.paused = false;
                mCurrentTeam.current.setLimitedMode();
                break;
            case RoundState.waitForSilence:
                modeTime.paused = true;
                //no control while blowing up worms
                if (mCurrentTeam) {
                    if (mCurrentTeam.current)
                        mCurrentTeam.current.forceAbort();
                    mCurrentTeam.setOnHold(true);
                }
                //if it's the round's end, also take control early enough
                currentTeam =  null;
                break;
            case RoundState.cleaningUp:
                modeTime.paused = true;
                //next call causes health countdown, so wait a little
                logic.updateHealth(); //hmmm
                //see doState()
                break;
            case RoundState.nextOnHold:
                modeTime.paused = true;
                currentTeam = null;
                engine.randomizeWind();
                logic.messageAdd("msgnextround");
                mStatus.roundRemaining = Time.Null;
                break;
            case RoundState.winning:
                modeTime.paused = true;
                break;
            case RoundState.end:
                modeTime.paused = true;
                logic.messageAdd("msggameend");
                currentTeam = null;
                break;
        }
    }

    bool ended() {
        return mCurrentRoundState == RoundState.end;
    }

    Object getStatus() {
        //xxx: this is bogus, someone else could read the fields at any time
        //     because an object reference is returned (not a struct anymore)
        mStatus.state = mCurrentRoundState;
        mStatus.timePaused = modeTime.paused;
        return mStatus;
    }

    private bool doCollectTool(ServerTeamMember member,
        CollectableTool tool)
    {
        if (auto t = cast(CollectableToolDoubleTime)tool) {
            waitAddTimeLocal(1, mStatus.roundRemaining);
            return true;
        }
        return false;
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("roundbased");
    }
}
