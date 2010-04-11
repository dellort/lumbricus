module game.controller;

import common.animation;
import common.common;
import common.scene;
import common.resset;
import framework.commandline;
import game.core;
import game.events;
import game.game;
import game.gfxset;
import game.worm;
import game.crate;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.weapon.weaponset;
import game.teamtheme;
import game.sequence;
import game.setup;
import game.wcontrol;
import physics.world;
import utils.factory;
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
//hack for message display
alias DeclareEvent!("team_member_collect_crate", TeamMember, CrateSprite)
    OnTeamMemberCollectCrate;
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
//when a worm collects a tool from a crate
alias DeclareEvent!("collect_tool", TeamMember, CollectableTool) OnCollectTool;

//make crates fall faster by pressing "space" (also known as unParachute)
alias DeclareGlobalEvent!("game_crate_skip") OnGameCrateSkip;


//class Team : TeamRef {
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
        //xxx: error handling (when team-theme not found)
        char[] colorId = parent.checkTeamColor(node["color"]);
        teamColor = engine.singleton!(GfxSet)().teamThemes[colorId];
        initialPoints = node.getIntValue("power", 100);
        //graveStone = node.getIntValue("grave", 0);
        //the worms currently aren't loaded by theirselves...
        foreach (char[] name, char[] value; node.getSubNode("member_names")) {
            auto worm = new TeamMember(value, this);
            mMembers ~= worm;
        }
        //xxx error handling
        weapons = parent.initWeaponSet(node["weapon_set"]);
        //what's a default weapon? I don't know, so I can't bring it back
        //defaultWeapon = weapons.byId(node["default_weapon"]);
        gravestone = node.getIntValue("grave", 0);
        mAlternateControl = node.getStringValue("control") != "worms";
        mTeamId = node["id"];
        mTeamNetId = node["net_id"];
        internal_active = true;
    }

    // --- start Team

    char[] name() {
        return mName;
    }

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
        return active;
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
    alias members getMembers; //legacy

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

    // --- end Team

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
    void doChooseWorm() {
        if (!allowSelect())
            return;
        //activates next, and deactivates current
        //special case: only one left -> current() will do nothing
        activateNextInRow();
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
        crate_spy = team.hasCrateSpy();
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
        return active;
    }

    bool alive() {
        //currently by havingwormspriteness... since dead worms haven't
        return control.isAlive();
    }

    //send new health value to client
    void updateHealth() {
        mHealthTarget = max(0, health());
    }

    bool needUpdateHealth() {
        return mCurrentHealth != mHealthTarget;
    }

    //the displayed health value; this is only updated at special points in the
    //  game (by calling updateHealth()), and then the health value is counted
    //  down/up over time (like an animation)
    //always capped to 0
    int currentHealth() {
        return mCurrentHealth;
    }

    //what currentHealth will become (during animating)
    int healthTarget() {
        return mHealthTarget;
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
            int c = min(abs(diff), change);
            mCurrentHealth += (diff < 0) ? -c : c;
        }
    }

    //(unlike currentHealth() the _actual_ current health value)
    int health(bool realHp = false) {
        //hack to display negative values
        //the thing is that a worm can be dead even if the physics report a
        //positive value - OTOH, we do want these negative values... HACK GO!
        //mLastKnownPhysicHealth is there because mWorm could disappear
        auto h = mWormControl.sprite.physics.lifepowerInt;
        if (mWormControl.isAlive() || realHp) {
            return h;
        } else {
            return h < 0 ? h : 0;
        }
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
        //take control over dying, so we can let them die on end of turn
        mWormControl.setDelayedDeath();
        mLastKnownLifepower = health;
        mCurrentHealth = mHealthTarget = health;
        updateHealth();

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

    void active(bool act) {
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
}

//the GameController controlls the game play; especially, it converts keyboard
//events into worm moves (or weapon moves!), controlls which object is focused
//by the "camera", and also manages worm teams
//xxx: move gui parts out of this
class GameController : GameObject2 {
    private {
        static LogStruct!("game.controller") log;

        Team[] mTeams;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        WeaponSet mCrateSet;

        bool mIsAnythingGoingOn; // (= hack)

        bool mGameEnded;

        //Medkit, medkit+tool, medkit+tool+unrigged weapon
        //  (rest is rigged weapon)
        const cCrateProbs = [0.20f, 0.40f, 0.95f];
        //list of tool crates that can drop
        char[][] mActiveCrateTools;
        int[] mTeamColorCache;
    }

    this(GameCore a_engine) {
        super(a_engine, "controller");

        engine.scripting.addSingleton(this);
        engine.addSingleton(this);

        GameConfig config = engine.gameConfig;

        assert(engine.onOffworld is null);
        engine.onOffworld = &onOffworld;

        //those work for all gamemodes
        addCrateTool("cratespy");
        addCrateTool("doubledamage");

        if (config.weapons) {
            loadWeaponSets(config.weapons);
        }
        if (config.teams) {
            loadTeams(config.teams);
        }
        if (config.levelobjects) {
            loadLevelObjects(config.levelobjects);
        }

        //only valid while loading
        mWeaponSets = null;

        engine.finishPlace();

        OnCollectTool.handler(engine.events, &doCollectTool);
        OnCrateCollect.handler(engine.events, &collectCrate);

        internal_active = true;
    }

    private void onOffworld(Sprite x) {
        auto member = memberFromGameObject(x, false);
        if (!member)
            return; //I don't know, try firing lots of mine airstrikes
        if (member.active)
            member.active(false);
    }

    //--- start GameLogicPublic

    ///True if game has ended
    bool gameEnded() {
        return mGameEnded;
    }

    //--- end GameLogicPublic

    void addCrateTool(char[] id) {
        assert(arraySearch(mActiveCrateTools, id) < 0);
        mActiveCrateTools ~= id;
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

    private char[] checkTeamColor(char[] col) {
        int colId = 0;  //default to first color
        foreach (int idx, char[] tc; TeamTheme.cTeamColors) {
            if (col == tc) {
                colId = idx;
                break;
            }
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
                engine.error("Weapon set {} not found.", id);
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
            engine.error("No weapon sets defined.");
            //create empty default set
            firstSet = new ConfigNode();
        }
        //2. referenced sets
        foreach (ConfigNode item; config) {
            if (item.value.length > 0) {
                if (!(item.value in mWeaponSets)) {
                    engine.error("Weapon set {} not found.", item.value);
                    continue;
                }
                mWeaponSets[item.name] = mWeaponSets[item.value];
            }
        }
        //we always need a default set
        assert(!!firstSet);
        if (!("default" in mWeaponSets))
            mWeaponSets["default"] = firstSet;
        //crate weapon set is named "crate_set" (will fall back to "default")
        mCrateSet = initWeaponSet("crate_set", true, true);
    }

    //create and place worms when necessary
    private void placeWorms() {
        log("placing worms...");

        foreach (t; mTeams) {
            t.placeMembers();
        }

        log("placing worms done.");
    }

    private void loadLevelObjects(ConfigNode objs) {
        log("placing level objects");
        foreach (ConfigNode sub; objs) {
            auto mode = sub.getStringValue("mode", "unknown");
            if (mode == "random") {
                auto cnt = sub.getIntValue("count");
                log("count {} type {}", cnt, sub["type"]);
                try {
                    for (int n = 0; n < cnt; n++) {
                        engine.queuePlaceOnLandscape(engine.resources
                            .get!(SpriteClass)(sub["type"]).createSprite());
                    }
                } catch (ResourceException e) {
                    engine.error("Warning: Placing {} objects failed",
                        sub["type"]);
                    continue;
                }
            } else {
                engine.error("Warning: unknown placing mode: '{}'",
                    sub["mode"]);
            }
        }
        log("done placing level objects");
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

    Collectable[] fillCrate() {
        Collectable[] ret;
        float r = engine.rnd.nextDouble2();
        if (r < cCrateProbs[0]) {
            //medkit
            ret ~= new CollectableMedkit(50);
        } else if (r < cCrateProbs[1]) {
            //tool
            ret ~= CrateToolFactory.instantiate(
                mActiveCrateTools[engine.rnd.next($)]);
        } else {
            //weapon
            auto content = mCrateSet.chooseRandomForCrate();
            if (content) {
                ret ~= new CollectableWeapon(content, content.crateAmount);
                if (r > cCrateProbs[2]) {
                    //add a bomb to that :D
                    ret ~= new CollectableBomb();
                }
            } else {
                log("failed to create crate contents");
            }
        }
        return ret;
    }

    //  silent = true to prevent generating an event (for debug drop, to
    //           prevent message spam)
    bool dropCrate(bool silent = false, Collectable[] contents = null) {
        Vector2f from, to;
        if (!engine.placeObjectRandom(10, 25, from, to)) {
            log("couldn't find a safe drop-position");
            return false;
        }

        Sprite s = engine.resources.get!(SpriteClass)("x_crate").createSprite();
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        if (!contents.length) {
            crate.stuffies = fillCrate();
        } else {
            crate.stuffies = contents;
        }
        //actually start it
        crate.activate(from);
        if (!silent) {
            //xxx move into CrateSprite.activate()
            OnCrateDrop.raise(crate);
        }
        log("drop {} -> {}", from, to);
        return true;
    }

    void instantDropCrate() {
        OnGameCrateSkip.raise(engine.events);
    }

    //xxx wouldn't need this anymore, but doubletime still makes it a bit messy
    private void doCollectTool(TeamMember collector, CollectableTool tool) {
        if (auto t = cast(CollectableToolCrateSpy)tool) {
            collector.team.addCrateSpy();
        }
        if (auto t = cast(CollectableToolDoubleDamage)tool) {
            collector.team.addDoubleDamage();
        }
    }

    //show effects of sudden death start
    //doesn't raise water / affect gameplay
    void startSuddenDeath() {
        engine.addEarthQuake(500, timeSecs(4.5f), true);
        engine.nukeSplatEffect();
        OnSuddenDeath.raise(engine.events);
    }

    private void collectCrate(CrateSprite crate, GameObject finder) {
        if (crate.wasCollected())
            return;
        //for some weapons like animal-weapons, transitive should be true
        //and normally a non-collecting weapon should just explode here??
        auto member = memberFromGameObject(finder, true);
        if (!member)
            return;
        //only collect crates when it's your turn
        if (!member.active)
            return;
        OnTeamMemberCollectCrate.raise(member, crate);
        //transfer stuffies
        foreach (Collectable c; crate.stuffies) {
            c.collect(crate, finder);
            if (auto tc = cast(TeamCollectable)c)
                tc.teamcollect(crate, member);
        }
        //and destroy crate
        crate.collected();
    }
}

class TeamCollectable : Collectable {
    override void collect(CrateSprite parent, GameObject finder) {
    }

    abstract void teamcollect(CrateSprite parent, TeamMember member);
}

///Adds a weapon to your inventory
class CollectableWeapon : TeamCollectable {
    WeaponClass weapon;
    int quantity;

    this(WeaponClass w, int quantity = 1) {
        weapon = w;
        this.quantity = quantity;
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        member.team.addWeapon(weapon, quantity);
    }

    CrateType type() {
        return CrateType.weapon;
    }

    char[] id() {
        return "weapons." ~ weapon.name;
    }

    override void blow(CrateSprite parent) {
        //think about the crate-sheep
        //ok, made more generic
        OnWeaponCrateBlowup.raise(weapon, parent);
    }
}

///Gives the collecting worm some health
class CollectableMedkit : TeamCollectable {
    int amount;

    this(int amount = 50) {
        this.amount = amount;
    }

    CrateType type() {
        return CrateType.med;
    }

    char[] id() {
        return "game_msg.crate.medkit";
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        member.addHealth(amount);
    }
}

abstract class CollectableTool : TeamCollectable {
    this() {
    }

    CrateType type() {
        return CrateType.tool;
    }

    void teamcollect(CrateSprite parent, TeamMember member) {
        //roundabout way, but I hope it makes a bit sense with double time tool?
        OnCollectTool.raise(member, this);
    }
}

StaticFactory!("CrateTools", CollectableTool) CrateToolFactory;

//xxx reduce bloat by making the type (e.g. "cratespy") just a member variable?

class CollectableToolCrateSpy : CollectableTool {
    this() {
    }

    char[] id() {
        return "game_msg.crate.cratespy";
    }

    static this() {
        CrateToolFactory.register!(typeof(this))("cratespy");
    }
}

//for now only for turnbased gamemode, but maybe others will follow
class CollectableToolDoubleTime : CollectableTool {
    this() {
    }

    char[] id() {
        return "game_msg.crate.doubletime";
    }

    static this() {
        CrateToolFactory.register!(typeof(this))("doubletime");
    }
}

class CollectableToolDoubleDamage : CollectableTool {
    this() {
    }

    char[] id() {
        return "game_msg.crate.doubledamage";
    }

    static this() {
        CrateToolFactory.register!(typeof(this))("doubledamage");
    }
}

