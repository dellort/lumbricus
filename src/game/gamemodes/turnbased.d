module game.gamemodes.turnbased;

import framework.framework;
import framework.timesource;
import game.game;
import game.controller;
import game.gamepublic;
import game.gamemodes.base;
import game.gamemodes.turnbased_shared;
import game.crate;

import utils.array;
import utils.configfile;
import utils.reflection;
import utils.time;
import utils.misc;
import utils.log;

class ModeTurnbased : Gamemode {
    private {
        TurnState mCurrentTurnState = TurnState.waitForSilence;
        static LogStruct!("gamemodes.turnbased") log;

        struct ModeConfig {
            //time a turn takes
            Time turntime = timeSecs(15);
            //extra time before turn time to switch seats etc
            Time hotseattime = timeSecs(5);
            //time the worm can still move after firing a weapon
            Time retreattime = timeSecs(5);
            //total time for one game until sudden death begins
            Time gametime = timeSecs(300);
            //can the active worm be chosen in prepare state?
            bool allowselect;
            //multi-shot mode (true -> firing a weapon doesn't end the turn)
            bool multishot;
            float crateprob = 0.9f;
            int maxcrates = 8;
            //max number of beam-ins while worm is moving (crate rain)
            //  (no more than maxcrates total)
            int maxcratesperturn = 0;
            int water_raise = 50;
        }
        ModeConfig config;

        ServerTeam mCurrentTeam;
        ServerTeam mLastTeam;

        TurnbasedStatus mStatus;
        int mTurnCrateCounter = 0;
        int mInTurnActivity = cInTurnActCheckC;
        int mCleanupCtr = 1;
        int[] mTeamPerm;

        const cSilenceWait = timeMsecs(400);
        const cNextRoundWait = timeMsecs(750);
        //how long winning animation is shown
        const cWinTime = timeSecs(5);
        //delay for crate rain
        const cTurnCrateDelay = timeSecs(5);
        const cInTurnActCheckC = 3;
    }

    this(GameController parent, ConfigNode config) {
        super(parent, config);
        mStatus = new TurnbasedStatus();
        this.config = config.getCurValue!(ModeConfig)();

        parent.collectTool ~= &doCollectTool;
    }

    this(ReflectCtor c) {
        super(c);
        Types t = c.types();
        t.registerMethod(this, &doCollectTool, "doCollectTool");
    }

    override void initialize() {
        super.initialize();
        //we want teams to be activated in a random order that stays the same
        //  over all rounds
        mTeamPerm = engine.persistentState.getValue!(int[])("team_order", null);
        if (mTeamPerm.length != logic.teams.length) {
            //either the game just started, or a player left -> new random order
            mTeamPerm.length = logic.teams.length;
            for (int i = 0; i < mTeamPerm.length; i++) {
                mTeamPerm[i] = i;
            }
            engine.rnd.randomizeArray(mTeamPerm);
            engine.persistentState.setValue("team_order", mTeamPerm);
        }
        logic.addCrateTool("doubletime");
    }

    override void startGame() {
        super.startGame();
        modeTime.paused = true;
    }

    void simulate() {
        super.simulate();
        mStatus.gameRemaining = max(config.gametime - modeTime.current(),
            Time.Null);
        //this ensures that after each transition(), doState() is also run
        //in the same frame
        TurnState next;
        while ((next = doState()) != mCurrentTurnState) {
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
    private TurnState doState() {
        switch (mCurrentTurnState) {
            case TurnState.prepare:
                mStatus.prepareRemaining = waitRemain(config.hotseattime, 1,
                    false);
                if (mCurrentTeam.teamAction())
                    //worm moved -> exit prepare phase
                    return TurnState.playing;
                if (mStatus.prepareRemaining <= Time.Null)
                    return TurnState.playing;
                break;
            case TurnState.playing:
                mStatus.turnRemaining = waitRemain!(true)(config.turntime, 1,
                    false);
                if (!mCurrentTeam.current)
                    return TurnState.waitForSilence;
                if (mStatus.turnRemaining <= Time.Null)   //timeout
                {
                    //check if we need to wait because worm is performing
                    //a non-abortable action
                    if (!mCurrentTeam.current.delayedAction)
                        return TurnState.waitForSilence;
                }
                //if not in multishot mode, firing ends the turn
                if (!config.multishot && mCurrentTeam.current.weaponUsed)
                    return TurnState.retreat;
                if (!mCurrentTeam.current.alive       //active worm dead
                    || mCurrentTeam.current.lifeLost)   //active worm damaged
                {
                    return TurnState.waitForSilence;
                }
                if (wait!(true)(cTurnCrateDelay, 3) && mTurnCrateCounter > 0
                    && engine.countSprites("crate") < config.maxcrates)
                {
                    logic.dropCrate();
                    mTurnCrateCounter--;
                }
                //check for silence every 500ms
                if (wait!(true)(timeMsecs(500), 4)) {
                    if (!engine.checkForActivity
                        && !mCurrentTeam.current.delayedAction)
                    {
                        mInTurnActivity--;
                        if (mInTurnActivity <= 0) {
                            //no activity for cInTurnActCheckC checks -> cleanup
                            ServerTeam tmp;
                            //check if we really need a cleanup
                            if (aliveTeams(tmp) < 2 || logic.needUpdateHealth)
                                return TurnState.inTurnCleanup;
                        }
                    } else {
                        mInTurnActivity = cInTurnActCheckC;
                    }
                }
                break;
            //quick cleanup, turn continues (time paused)
            case TurnState.inTurnCleanup:
                ServerTeam tmp;
                if (aliveTeams(tmp) < 2)
                    return TurnState.waitForSilence;
                if (!engine.checkForActivity) {
                    logic.updateHealth();
                    if (!logic.checkDyingWorms()) {
                        if (wait(cNextRoundWait, 3))
                            return TurnState.playing;
                    }
                } else {
                    waitReset(3);
                }
                break;
            //only used if config.multishot == false
            case TurnState.retreat:
                //give him some time to run, hehe
                if (wait(config.retreattime)
                    || !mCurrentTeam.current.alive
                    || mCurrentTeam.current.lifeLost)
                    return TurnState.waitForSilence;
                break;
            case TurnState.waitForSilence:
                //check over a period, to avoid one-frame errors
                if (!engine.checkForActivity) {
                    if (wait(cSilenceWait)) {
                        //hope the game stays inactive
                        return TurnState.cleaningUp;
                    }
                } else {
                    waitReset();
                }
                break;
            case TurnState.cleaningUp:
                mStatus.turnRemaining = Time.Null;
                //if there are more to blow up, go back to waiting
                if (logic.checkDyingWorms())
                    return TurnState.waitForSilence;

                //wait some msecs to show the health labels
                if (wait(cNextRoundWait, 0, false) && logic.isIdle()) {
                    waitReset(0);
                    //check if at least two teams are alive
                    ServerTeam firstAlive;
                    int aliveTeams = aliveTeams(firstAlive);

                    if (aliveTeams < 2) {
                        if (aliveTeams > 0) {
                            assert(!!firstAlive);
                            firstAlive.youWinNow();
                        }
                        logic.events.onVictory(firstAlive);
                        if (aliveTeams == 0) {
                            return TurnState.end;
                        } else {
                            return TurnState.winning;
                        }
                    }

                    if (mStatus.gameRemaining <= Time.Null
                        && !mStatus.suddenDeath)
                    {
                        mStatus.suddenDeath = true;
                        logic.startSuddenDeath();
                    }

                    if (mCleanupCtr > 1) {
                        mCleanupCtr--;
                        if (mStatus.suddenDeath) {
                            engine.raiseWater(config.water_raise);
                            return TurnState.waitForSilence;
                        }
                    }
                    //probably drop a crate, if not too many out already
                    if (mCleanupCtr > 0) {
                        mCleanupCtr--;
                        if (engine.rnd.nextDouble2 < config.crateprob
                            && engine.countSprites("crate") < config.maxcrates)
                        {
                            if (logic.dropCrate()) {
                                return TurnState.waitForSilence;
                            }
                        }
                    }

                    return TurnState.nextOnHold;
                }
                break;
            case TurnState.nextOnHold:
                if (logic.isIdle())
                    return TurnState.prepare;
                break;
            case TurnState.winning:
                if (wait(cWinTime))
                    return TurnState.end;
                break;
            case TurnState.end:
                break;
        }
        return mCurrentTurnState;
    }

    private void transition(TurnState st) {
        assert(st != mCurrentTurnState);
        log("state transition {} -> {}", cast(int)mCurrentTurnState,
            cast(int)st);
        mCurrentTurnState = st;
        switch (st) {
            case TurnState.prepare:
                modeTime.paused = true;
                mStatus.turnRemaining = config.turntime;
                waitReset(1);
                waitReset!(true)(1);
                mCleanupCtr = 2;

                ServerTeam next;
                //mix teams array according to mTeamPerm
                assert(mTeamPerm.length == logic.teams.length);
                scope ServerTeam[] teamsP;
                teamsP.length = logic.teams.length;
                for (int i = 0; i < logic.teams.length; i++) {
                    teamsP[i] = logic.teams[mTeamPerm[i]];
                }
                if (!mLastTeam) {
                    //game has just started, select first team (round-robin)
                    next = teamsP[logic.currentRound % teamsP.length];
                } else {
                    //select next team/worm
                    next = arrayFindNextPred(teamsP, mLastTeam,
                        (ServerTeam t) {
                            return t.alive();
                        }
                    );
                }
                currentTeam = null;

                assert(next); //should've dropped out in nextOnHold otherwise

                mLastTeam = next;
                currentTeam = next;
                if (config.allowselect)
                    mCurrentTeam.allowSelect = true;
                log("active: {}", next);
                mTurnCrateCounter = config.maxcratesperturn;

                break;
            case TurnState.playing:
                assert(mCurrentTeam);
                modeTime.paused = false;
                mCurrentTeam.setOnHold(false);
                mStatus.prepareRemaining = Time.Null;
                break;
            case TurnState.inTurnCleanup:
                assert(mCurrentTeam);
                modeTime.paused = true;
                mCurrentTeam.setOnHold(true);
                break;
            case TurnState.retreat:
                modeTime.paused = false;
                mCurrentTeam.current.setLimitedMode();
                break;
            case TurnState.waitForSilence:
                modeTime.paused = true;
                //no control while blowing up worms
                if (mCurrentTeam) {
                    if (mCurrentTeam.current)
                        mCurrentTeam.current.forceAbort();
                    mCurrentTeam.setOnHold(true);
                }
                //if it's the turn's end, also take control early enough
                currentTeam =  null;
                break;
            case TurnState.cleaningUp:
                modeTime.paused = true;
                //next call causes health countdown, so wait a little
                logic.updateHealth(); //hmmm
                //see doState()
                break;
            case TurnState.nextOnHold:
                modeTime.paused = true;
                currentTeam = null;
                engine.randomizeWind();
                //logic.messageAdd("msgnextround");
                mStatus.turnRemaining = Time.Null;
                break;
            case TurnState.winning:
                modeTime.paused = true;
                break;
            case TurnState.end:
                modeTime.paused = true;
                currentTeam = null;
                break;
        }
    }

    bool ended() {
        return mCurrentTurnState == TurnState.end;
    }

    Object getStatus() {
        //xxx: this is bogus, someone else could read the fields at any time
        //     because an object reference is returned (not a struct anymore)
        mStatus.state = mCurrentTurnState;
        mStatus.timePaused = modeTime.paused;
        return mStatus;
    }

    private bool doCollectTool(ServerTeamMember member,
        CollectableTool tool)
    {
        if (auto t = cast(CollectableToolDoubleTime)tool) {
            waitAddTimeLocal(1, mStatus.turnRemaining);
            return true;
        }
        return false;
    }

    static this() {
        GamemodeFactory.register!(typeof(this))("turnbased");
    }
}
