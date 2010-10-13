module game.controller;

import framework.config; //for some debug stuff?
import common.animation;
import common.resset;
import game.core;
import game.events;
import game.game;
import game.gfxset;
import game.input;
import game.worm;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.teamtheme;
import game.sequence;
import game.setup;
import game.wcontrol;
import physics.all;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.misc;
import utils.array;
import utils.queue;

import math = tango.math.Math;
import tango.util.Convert : to;

//time for which it takes to add/remove 1 health point in the animation
const Time cTimePerHealthTick = timeMsecs(4);

//starting to blow itself up
//xxx is this really needed
alias DeclareEvent!("team_member_start_die", TeamMember) OnTeamMemberStartDie;
alias DeclareEvent!("team_member_set_active", TeamMember, bool)
    OnTeamMemberSetActive;
//first time a team does an action (should probably be per team member?)
//xxx actually those should be WormControl events?
alias DeclareEvent!("team_on_first_action", Team) OnTeamFirstAction;
alias DeclareEvent!("team_member_on_lost_control", TeamMember) OnTeamMemberLostControl;
alias DeclareEvent!("team_set_active", Team, bool) OnTeamSetActive;
alias DeclareEvent!("team_skipturn", Team) OnTeamSkipTurn;
alias DeclareEvent!("team_surrender", Team) OnTeamSurrender;
//the team wins; all OnVictory events will be raised before game_end (so you can
//  know exactly who wins, even if there can be 0 or >1 winners)
alias DeclareEvent!("team_victory", Team) OnVictory;


class Team : GameObject2 {
    char[] mName = "unnamed team";
    TeamTheme teamColor;
    int gravestone;
    WeaponSet weapons;
    //WeaponClass defaultWeapon;
    int initialPoints; //on loading
    GameController parent;
    bool forcedFinish;

    private {
        TeamMember[] mMembers;  //all members (will not change in-game)
        TeamMember mCurrent;  //active worm that will receive user input
        TeamMember mLastActive;  //worm that played last (to choose next)
        bool mActive;         //is this team playing?

        InputGroup mInput;

        bool mAlternateControl;
        bool mAllowSelect;   //can next worm be selected by user (tab)
        char[] mTeamId, mTeamNetId;

        int mGlobalWins;
        //incremented for each crate; xxx take over to next round
        int mDoubleDmg, mCrateSpy;

        bool mActionNotified;
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        super(parent.engine, "team");
        this.parent = parent;
        mName = node.name;
        char[] colorId = parent.checkTeamColor(node.getSubNode("color"));
        teamColor = engine.singleton!(GfxSet)().teamThemes[colorId];
        initialPoints = node.getIntValue("power", 100);
        //graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new TeamMember(value, this);
            mMembers ~= worm;
        }
        if (mMembers.length == 0) {
            engine.log.warn("Team '{}' has no members!", name);
        }
        weapons = parent.initWeaponSet(node["weapon_set"]);
        gravestone = node.getIntValue("grave", 0);
        mAlternateControl =
            node.getStringValue("control", "default") != "default";
        mTeamId = node["id"];
        mTeamNetId = node["net_id"];

        //per-team commands
        //(NOTE: each team member adds its input to mInput later, see place())
        mInput = new InputGroup();
        mInput.add("next_member", &inpChooseWorm);
        mInput.add("remove_control", &inpRemoveControl);

        internal_active = true;
    }

    //human readable team name (specified by user)
    char[] name() {
        return mName;
    }

    //unique ID; this also may correspond to the client_id in network mode
    char[] id() {
        return mTeamId;
    }

    //the naming sucks, superseded by theme()
    TeamTheme color() {
        return teamColor;
    }

    TeamTheme theme() {
        return teamColor;
    }

    //if there's any alive worm
    bool alive() {
        foreach (m; mMembers) {
            if (m.alive())
                return true;
        }
        return false;
    }

    override bool activity() {
        //xxx see comment for TeamMember.activity()
        return false;
    }

    int totalHealth() {
        int h;
        foreach (t; mMembers) {
            //no negative values
            //(it's sad - but the other team member don't care about the
            // wounded! it's a cruel game.)
            h += t.health < 0 ? 0 : t.health;
        }
        return h;
    }

    int totalCurrentHealth() {
        int h;
        foreach (t; mMembers) {
            h += t.currentHealth();
        }
        return h;
    }

    TeamMember[] members() {
        return mMembers;
    }

    bool allowSelect() {
        if (!mActive || !mCurrent)
            return false;
        return mAllowSelect;
    }

    void allowSelect(bool allow) {
        mAllowSelect = allow;
    }

    int globalWins() {
        return mGlobalWins;
    }

    bool hasCrateSpy() {
        return mCrateSpy > 0;
    }

    bool hasDoubleDamage() {
        return mActive && (mDoubleDmg > 0);
    }

    //not sure what this is; probably for the net GUI
    char[] netId() {
        return mTeamNetId;
    }

    //returns an id that is a) unique over all teams in the game, and
    //  b) will remain the same over all played rounds
    char[] uniqueId() {
        return mTeamNetId ~ "." ~ mTeamId;
    }

    void globalWins(int wins) {
        mGlobalWins = wins;
    }

    void crateSpy(int spyCount) {
        mCrateSpy = spyCount;
        updateHacks();
    }
    int crateSpy() {
        return mCrateSpy;
    }

    void doubleDmg(int dblCount) {
        mDoubleDmg = dblCount;
        updateHacks();
    }
    int doubleDmg() {
        return mDoubleDmg;
    }

    bool alternateControl() {
        return mAlternateControl;
    }

    private void placeMembers() {
        foreach (TeamMember m; mMembers) {
            m.place();
        }
    }

    //wraps around, if w==null, return first element, if any
    private TeamMember doFindNext(TeamMember w) {
        return arrayFindNext(mMembers, w);
    }

    TeamMember findNext(TeamMember w, bool must_be_alive = false) {
        return arrayFindNextPred(mMembers, w,
            (TeamMember t) {
                return !must_be_alive || t.alive;
            }
        );
    }

    ///activate a member for playing
    ///only for a member, not the team, use active setter for team
    void current(TeamMember cur) {
        if (cur is mCurrent)
            return;
        if (mCurrent)
            mCurrent.active = false;
        mCurrent = cur;
        if (cur)
            mLastActive = cur;
        if (mCurrent) {
            mCurrent.active = true;
        }
    }
    ///get active member (can be null)
    TeamMember current() {
        return mCurrent;
    }

    bool isControllable() {
        return current ? current.control.isControllable : false;
    }

    void setOnHold(bool hold) {
        if (current)
            current.control.setOnHold(hold);
    }

    ///set if this team should be able to move/play
    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
        if (act) {
            //activating team
            if (!activateNextInRow()) {
                //no worm could be activated (i.e. all dead)
                mActive = false;
                return;
            }
            forcedFinish = false;
            assert(!!current);
            /+ already in TeamMember?
            foreach (e; parent.mEvents) {
                e.onWormEvent(WormEvent.wormActivate, current);
            }
            +/
        } else {
            //deactivating
            current = null;
            if (mDoubleDmg > 0) {
                mDoubleDmg--;
            }
            mAllowSelect = false;
        }
        mActionNotified = false;
        updateHacks();
        OnTeamSetActive.raise(this, act);
    }

    bool active() {
        return mActive;
    }

    ///select the worm to play when team becomes active
    bool activateNextInRow() {
        if (!mActive)
            return false;
        auto next = nextActive();
        //this will activate the worm
        current = next;
        return !!current;
    }

    ///get the worm that would be next-in-row to move
    ///returns null if none left
    TeamMember nextActive() {
        return findNext(mLastActive, true);
    }

    //returns true if a next-active worm was found and did not move for idleTime
    //(helper function for gamemodes)
    bool nextWasIdle(Time idleTime) {
        auto next = nextActive();
        if (next && engine.gameTime.current
            - next.control.lastActivity > idleTime)
        {
            return true;
        }
        return false;
    }

    ///choose next in reaction to user keypress
    private bool inpChooseWorm() {
        if (!allowSelect())
            return false;
        //activates next, and deactivates current
        //special case: only one left -> current() will do nothing
        activateNextInRow();
        return true;
    }

    char[] toString() {
        return "[team '" ~ name ~ "']";
    }

    int opApply(int delegate(inout TeamMember member) del) {
        foreach (m; mMembers) {
            int res = del(m);
            if (res)
                return res;
        }
        return 0;
    }

    bool teamAction() {
        if (mCurrent) {
            return mCurrent.control.actionPerformed();
        }
        return false;
    }

    //check if some parts of the team are still moving
    //gamemode plugin may use this to wait for the next turn
    bool isIdle() {
        foreach (m; mMembers) {
            //check if any alive member is still moving around
            if (m.alive() && !m.control.isIdle())
                return false;
        }
        return true;
    }

    override void simulate() {
        bool has_active_worm;

        foreach (m; mMembers) {
            has_active_worm |= m.active;
        }

        if (!has_active_worm)
            active = false;

        bool action;

        if (current && current.control.actionPerformed()) {
            mAllowSelect = false;
            action = true;
        }

        if (action && !mActionNotified) {
            mActionNotified = true;
            OnTeamFirstAction.raise(this);
        }
    }

    bool checkDyingMembers() {
        foreach (m; mMembers) {
            if (m.checkDying())
                return true;
        }
        return false;
    }

    void youWinNow() {
        mGlobalWins++;
        foreach (m; mMembers) {
            m.youWinNow();
        }
        OnVictory.raise(this);
    }

    void updateHealth() {
        foreach (m; mMembers) {
            m.updateHealth();
        }
    }

    bool needUpdateHealth() {
        foreach (m; mMembers) {
            if (m.needUpdateHealth())
                return true;
        }
        return false;
    }

    void addWeapon(WeaponClass w, int quantity = 1) {
        weapons.addWeapon(w, quantity);
    }

    void skipTurn() {
        if (!mCurrent || !mActive)
            return;
        OnTeamSkipTurn.raise(this);
        current = null;
    }

    void prepareTurn() {
        foreach (m; mMembers) {
            m.prepareTurn();
        }
    }

    void surrenderTeam() {
        OnTeamSurrender.raise(this);
        current = null;
        //xxx: set worms to "white flag" animation first
        foreach (m; mMembers) {
            m.sprite.kill();
        }
    }

    void addDoubleDamage() {
        mDoubleDmg++;
        updateHacks();
    }

    void addCrateSpy() {
        mCrateSpy++;
        updateHacks();
    }

    void updateHacks() {
        foreach (m; mMembers) {
            m.updateHacks();
        }
    }

    //there's remove_control somewhere in cmdclient.d, and apparently this is
    //  called when a client disconnects; the teams owned by that client
    //  surrender
    private bool inpRemoveControl() {
        surrenderTeam();
        return true;
    }
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class TeamMember : Actor {
    private {
        Team mTeam;
        char[] mName = "unnamed worm";
        bool mActive;
        //Sprite mWorm;
        WormControl mWormControl;
        int mLastKnownLifepower;
        int mCurrentHealth; //health value reported to client
        int mHealthTarget;
        bool mDeathAnnounced; //show normal death msg only once
        Time mHealthChangeTime;
        bool mLostNotified;
    }

    this(char[] a_name, Team a_team) {
        super(a_team.engine, "team_member");
        mName = a_name;
        mTeam = a_team;
        team_theme = team.theme();
        updateHacks();
        internal_active = true;
    }

    //called by Team to update the Actor fields
    private void updateHacks() {
        damage_multiplier = team.hasDoubleDamage() ? 2.0f : 1.0f;
    }

    final WormControl control() {
        return mWormControl;
    }

    bool checkDying() {
        bool r = control.checkDying();
        if (r && !mDeathAnnounced) {
            mDeathAnnounced = true;
            OnTeamMemberStartDie.raise(this);
        }
        return r;
    }

    char[] name() {
        return mName;
    }

    Team team() {
        return mTeam;
    }

    override bool activity() {
        //returning "active" broke in-turn-cleanup for turnbased game mode
        //on one hand, the "activity" should indicate if any game object is
        //  doing something (and receiving input from the user and acting
        //  according to it definitely counts) => debatable
        //--return active;
        return false;
    }

    bool alive() {
        return control.isAlive();
    }

    //display new health value on screen (like health labels, team bars)
    void updateHealth() {
        mHealthTarget = health();
    }

    //if updateHealth() would actually trigger anything visible
    bool needUpdateHealth() {
        return health() != mHealthTarget;
    }

    //the displayed health value; this is only updated at special points in the
    //  game (by calling updateHealth()), and then the health value is counted
    //  down/up over time (like an animation)
    //capped: if true, capped to 0  (hmm, wtf)
    int currentHealth(bool capped = true) {
        return capped ? max(mCurrentHealth, 0) : mCurrentHealth;
    }

    //what currentHealth will become (during animating)
    int healthTarget(bool capped = true) {
        return capped ? max(mHealthTarget, 0) : mHealthTarget;
    }

    //take care of counting down (or up) the health value
    private void healthAnimation() {
        //if you have an event, which shall occur all duration times, return the
        //number of events which fit in t and return the rest time in t (divmod)
        static int removeNTimes(ref Time t, Time duration) {
            int r = t/duration;
            t -= duration*r;
            return r;
        }

        mHealthChangeTime += engine.gameTime.difference;
        int change = removeNTimes(mHealthChangeTime, cTimePerHealthTick);
        assert(change >= 0);
        int diff = mHealthTarget - mCurrentHealth;
        if (diff != 0) {
            int c = min(math.abs(diff), change);
            mCurrentHealth += (diff < 0) ? -c : c;
        }
    }

    //(unlike currentHealth() the _actual_ current health value)
    int health(bool realHp = false) {
        //hack to display negative values
        //the thing is that a worm can be dead even if the physics report a
        //positive value - OTOH, we do want these negative values... HACK GO!
        //mLastKnownPhysicHealth is there because mWorm could disappear
        float h = mWormControl.sprite.physics.lifepower;
        if (!(mWormControl.isAlive() || realHp)) {
            h = h < 0 ? h : 0;
        }
        //ceil: never display 0 if the worm is still alive
        return cast(int)(math.ceil(h));
    }

    private void place() {
        GameEngine rengine = team.engine;
        assert (!mWormControl);

        //create and place into the landscape
        //habemus lumbricus
        SpriteClass worm_cls = engine.resources.get!(SpriteClass)("x_worm");
        Sprite worm = worm_cls.createSprite();
        worm.createdBy = this;
        WormSprite xworm = castStrict!(WormSprite)(worm); //xxx no WormSprite
        assert(worm !is null);
        worm.physics.lifepower = mTeam.initialPoints;
        mWormControl = new WormControl(worm);
        mWormControl.setWeaponSet(mTeam.weapons);
        mWormControl.setAlternateControl(mTeam.alternateControl);
        //xxx maybe make this a bit better
        mTeam.mInput.addSub(mWormControl.input);
        //take control over dying, so we can let them die on end of turn
        mWormControl.setDelayedDeath();
        mLastKnownLifepower = health;
        mCurrentHealth = mHealthTarget = health;
        updateHealth();

        //xxx WormSprite dependency should go away
        xworm.gravestone = mTeam.gravestone;
        xworm.teamColor = mTeam.color;

        //let Controller place the worm
        rengine.queuePlaceOnLandscape(worm);
    }

    Sprite sprite() {
        return mWormControl.sprite;
    }

    char[] toString() {
        return "[tworm " ~ (mTeam ? mTeam.toString() : null) ~ ":'" ~ name ~ "']";
    }

    //xxx should be named: round lost?
    //apparently amount of lost healthpoints since last activation
    //tolerance: positive number of health points, whose loss can be tolerated
    //also xxx: tolerance should be a settable property of TeamMember
    bool lifeLost(int tolerance = 0) {
        return health() + tolerance < mLastKnownLifepower;
    }

    void addHealth(int amount) {
        if (!mWormControl.isAlive())
            return;
        mWormControl.sprite.physics.lifepower += amount;
        mLastKnownLifepower += amount;
        updateHealth();
    }

    bool active() {
        return mActive;
    }

    private void active(bool act) {
        mWormControl.setEngaged(act);
        if (mActive == act)
            return;
        mActive = act;
        if (act) {
            mLastKnownLifepower = health;
        }
        mLostNotified = false;
        OnTeamMemberSetActive.raise(this, act);
    }

    override void simulate() {
        mWormControl.simulate();

        if (!mLostNotified && lifeLost()) {
            mLostNotified = true;
            OnTeamMemberLostControl.raise(this);
        }

        //mWormControl deactivates itself if the worm was e.g. injured
        if (!mWormControl.engaged())
            active = false;

        healthAnimation();
    }

    void youWinNow() {
        control.youWinNow();
    }

    bool delayedAction() {
        return control.delayedAction;
    }

    void forceAbort() {
        //forced stop of all action (like when being damaged)
        control.forceAbort();
    }

    void prepareTurn() {
        control.prepareTurn();
    }
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController : GameObject2 {
    private {
        Team[] mTeams;

        //for instantiating new weapon sets
        ConfigNode[char[]] mWeaponSets;

        bool mIsAnythingGoingOn; // (= hack)

        bool mGameEnded;

        int[] mTeamColorCache;

        InputGroup mInput;

        //determines which network clients are allowed to control which teams
        //each array item is a pair of strings:
        // [client_id, team_id]
        //it means that that client is allowed to control that team
        char[][2][] mAccessMap;
    }

    this(GameCore a_engine) {
        super(a_engine, "controller");

        loadAccessMap(engine.gameConfig.management.getSubNode("access_map"));

        engine.scripting.addSingleton(this);
        engine.addSingleton(this);

        OnSpriteOffworld.handler(engine.events, &onOffworld);

        mInput = new InputGroup();
        //per-team input
        mInput.addSub(new InputProxy(&getTeamInput));
        //global input (always available)
        mInput.add("exec", &inpExec);
        engine.input.addSub(mInput);
    }

    //later construction; needs access to lots of sprite types (worms, mines)
    //will also place the worms
    //and prepares for calling startGame()
    void finishLoading() {
        GameConfig config = engine.gameConfig;

        if (config.weapons) {
            loadWeaponSets(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }
        if (config.levelobjects) {
            loadLevelObjects(config.levelobjects);
        }

        engine.finishPlace();

        OnPrepareTurn.handler(engine.events, &prepareTurn);

        //for startGame(); see simulate()
        internal_active = true;
    }

    private Log log() {
        return engine.log;
    }

    private void loadAccessMap(ConfigNode node) {
        foreach (ConfigNode sub; node) {
            //sub is "tag_name { "teamid1" "teamid2" ... }"
            foreach (char[] key, char[] value; sub) {
                mAccessMap ~= [sub.name, value];
            }
        }

        auto p = &log.trace;
        p("access map:");
        foreach (char[][2] a; mAccessMap) {
            p("  '{}' -> '{}'", a[0], a[1]);
        }
        p("access map end.");
    }

    bool checkAccess(char[] client_id, Team team) {
        //single player, no network
        if (client_id == "local")
            return true;
        //multi player, networked
        foreach (a; mAccessMap) {
            if (a[0] == client_id && a[1] == team.id)
                return true;
        }
        return false;
    }

    private Team getInputTeam(char[] client_id) {
        foreach (Team t; teams) {
            if (t.active) {
                if (checkAccess(client_id, t))
                    return t;
            }
        }
        return null;
    }

    //decide to which team input goes
    //in network & realtime mode, multiple teams can be active, and the
    //  client_id helps delivering a client's input to the right team
    //this is also needed for cheat-prevention (client_id is verified)
    private Input getTeamInput(char[] client_id) {
        //hurrr
        if (auto team = getInputTeam(client_id))
            return team.mInput;
        return null;
    }

    private bool inpExec(char[] client_id, char[] cmd) {
        //security? security is for idiots!
        //(all scripts are already supposed to be sandboxed; still this enables
        //  anyone who is connected to do anything to the game)
        //find input team, needed by cheats.lua
        Team client_team = getInputTeam(client_id);
        engine.scripting.scriptExec(`
            local client_team, cmd = ...
            _G._currentInputTeam = client_team
            ConsoleUtils.exec(cmd)
            _G._currentInputTeam = nil
        `, client_team, cmd);
        return true;
    }

    private void onOffworld(Sprite x) {
        auto member = memberFromGameObject(x, false);
        if (!member)
            return; //I don't know, try firing lots of mine airstrikes
        if (member.active)
            member.active(false);
    }

    ///True if game has ended
    bool gameEnded() {
        return mGameEnded;
    }

    bool isIdle() {
        foreach (t; mTeams) {
            if (!t.isIdle())
                return false;
        }
        return true;
    }

    void startGame() {
        assert(!mIsAnythingGoingOn);
        mIsAnythingGoingOn = true;
        //nothing happening? start a round

        deactivateAll();
        OnGameStart.raise(engine.events);
    }

    override void simulate() {
        //apparently only needed to "start" in the first frame...
        if (!mIsAnythingGoingOn) {
            internal_active = false;
            startGame();
        }
    }

    override bool activity() {
        return false;
    }

    ///Called by gamemode, when the game is over
    ///It is the Gamemode's task to make a team win before
    void endGame() {
        if (!mGameEnded) {
            //only call once
            mGameEnded = true;

            OnGameEnd.raise(engine.events);

            //increase total round count
            engine.persistentState.setValue("round_counter",
                currentRound + 1);

            debug {
                saveConfig(engine.persistentState,
                    "persistence_debug.conf");
            }
        }
    }

    //index of currently running game round (zero-based)
    //note: even during onGameEnded event, still returns the current index
    int currentRound() {
        return engine.persistentState.getValue("round_counter", 0);
    }

    void prepareTurn() {
        foreach (t; mTeams) {
            t.prepareTurn();
        }
    }

    //return true if there are dying worms
    bool checkDyingWorms() {
        foreach (t; mTeams) {
            //death is in no hurry, one worm a frame
            if (t.checkDyingMembers())
                return true;
        }
        return false;
    }

    //send clients new health values
    void updateHealth() {
        foreach (t; mTeams) {
            t.updateHealth();
        }
    }

    bool needUpdateHealth() {
        foreach (t; mTeams) {
            if (t.needUpdateHealth())
                return true;
        }
        return false;
    }

    //return true if health is being updated (like in the GUI)
    //xxx: not sure why this is different from needUpdateHealth(); bug?
    bool healthUpdating() {
        foreach (Team t; teams) {
            foreach (TeamMember tm; t.members) {
                if (tm.currentHealth != tm.healthTarget())
                    return true;
            }
        }
        return false;
    }

    ///all participating teams (even dead ones)
    Team[] teams() {
        return mTeams;
    }

    void deactivateAll() {
        foreach (t; mTeams) {
            t.active = false;
        }
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void loadTeams(ConfigNode config) {
        mTeams = null;
        foreach (ConfigNode sub; config) {
            addTeam(sub);
        }
        placeWorms();
    }

    //config = the "teams" node, i.e. from data/data/teams.conf
    private void addTeam(ConfigNode config) {
        auto team = new Team(config, this);
        mTeams ~= team;
    }

    private char[] checkTeamColor(ConfigNode colvalue) {
        char[] col = colvalue.value;
        int colId = -1;
        foreach (int idx, char[] tc; TeamTheme.cTeamColors) {
            if (col == tc) {
                colId = idx;
                break;
            }
        }

        if (colId < 0) {
            //hm would be nice to print the origin
            engine.log.error("invalid team color: '{}' in {}", col,
                colvalue.locationString());
            colId = 0; //default to first color
        }

        //assign the color least used, preferring the one requested
        mTeamColorCache.length = TeamTheme.cTeamColors.length;
        foreach (int idx, int count; mTeamColorCache) {
            if (count < mTeamColorCache[colId])
                colId = idx;
        }
        mTeamColorCache[colId]++;
        return TeamTheme.cTeamColors[colId];
    }

    WeaponSet initWeaponSet(char[] id, bool forCrate = false,
        bool noError = false)
    {
        ConfigNode ws;
        if (id in mWeaponSets)
            ws = mWeaponSets[id];
        else {
            if (!noError && id.length) {
                engine.log.warn("Weapon set {} not found.", id);
            }
            ws = mWeaponSets["default"];
        }
        //at least the "default" set has to exist
        assert(!!ws);
        return new WeaponSet(engine, ws, forCrate);
    }

    //like "weapon_sets" in gamemode.conf, but renamed according to game config
    private void loadWeaponSets(ConfigNode config) {
        //1. complete sets
        ConfigNode firstSet;
        foreach (ConfigNode item; config) {
            if (item.value.length == 0) {
                if (!firstSet)
                    firstSet = item;
                mWeaponSets[item.name] = item;
            }
        }
        if (!firstSet) {
            engine.log.error("No weapon sets defined.");
            //create empty default set
            firstSet = new ConfigNode();
        }
        //2. referenced sets
        foreach (ConfigNode item; config) {
            if (item.value.length > 0) {
                if (!(item.value in mWeaponSets)) {
                    engine.log.warn("Weapon set {} not found.", item.value);
                    continue;
                }
                mWeaponSets[item.name] = mWeaponSets[item.value];
            }
        }
        //we always need a default set
        assert(!!firstSet);
        if (!("default" in mWeaponSets)) {
            log.warn("enforcing default weaponset");
            mWeaponSets["default"] = firstSet;
        }
    }

    //create and place worms when necessary
    private void placeWorms() {
        log.minor("placing worms...");

        foreach (t; mTeams) {
            t.placeMembers();
        }

        log.minor("placing worms done.");
    }

    private void loadLevelObjects(ConfigNode objs) {
        log.minor("placing level objects");
        foreach (ConfigNode sub; objs) {
            auto mode = sub.getStringValue("mode", "unknown");
            if (mode == "random") {
                try {
                    auto cnt = sub.getIntValue("count");
                    log.trace("count {} type {}", cnt, sub["type"]);
                    for (int n = 0; n < cnt; n++) {
                        engine.queuePlaceOnLandscape(engine.resources
                            .get!(SpriteClass)(sub["type"]).createSprite());
                    }
                } catch (CustomException e) {
                    log.warn("Warning: Placing {} objects failed: {}",
                        sub["type"], e);
                    continue;
                }
            } else {
                log.warn("Warning: unknown placing mode: '{}'",
                    sub["mode"]);
            }
        }
        log.minor("done placing level objects");
    }

    //transitive:
    //  false = go must be a team member worm; if not, return null
    //  true = like false, but if go was created by a team member, also return
    //      that team member
    TeamMember memberFromGameObject(GameObject go, bool transitive = true) {
        //typically, GameObject is transitively (consider spawning projectiles!)
        //created by a Worm
        //"victim" from reportViolence should be directly a Worm

        GameObject cur = go;

        while (cur) {
            if (auto m = cast(TeamMember)cur) {
                if (!transitive && m.sprite() !is go)
                    return null;
                return m;
            }
            cur = cur.createdBy;
        }

        return null;
    }

    WeaponClass weaponFromGameObject(GameObject go) {
        //commonly, everything causing damage is transitively created by
        //  a Shooter, but not always (consider landscape objects/crates/
        //  exploding worms)
        Shooter sh;
        while ((sh = cast(Shooter)go) is null && go) {
            go = go.createdBy;
        }
        if (sh !is null)
            return sh.weapon;
        return null;
    }

    //return WormControl, by which go is controlled
    //  transitive: go can also be something spawned by that WormControl
    WormControl controlFromGameObject(GameObject go, bool transitive = true) {
        TeamMember m = memberFromGameObject(go, transitive);
        return m ? m.control : null;
    }

    //show effects of sudden death start
    //doesn't raise water / affect gameplay
    void startSuddenDeath() {
        engine.addEarthQuake(500, timeSecs(4.5f), true);
        engine.nukeSplatEffect();
        OnSuddenDeath.raise(engine.events);
    }
}
