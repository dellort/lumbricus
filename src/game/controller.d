module game.controller;

import common.animation;
import common.common;
import common.scene;
import framework.commandline;
import game.game;
import game.gfxset;
import game.gobject;
import game.worm;
import game.crate;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.temp;
import game.sequence;
import game.setup;
import game.gamemodes.base;
import game.controller_events;
import game.wcontrol;
import physics.world;
import utils.vector2;
import utils.configfile;
import utils.log;
import utils.time;
import utils.md;
import utils.misc;
import utils.array;
import utils.queue;
import utils.reflection;

import math = tango.math.Math;
import tango.util.Convert : to;

//time for which it takes to add/remove 1 health point in the animation
const Time cTimePerHealthTick = timeMsecs(4);


class Team : GameObject {
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
    }

    //node = the node describing a single team
    this(ConfigNode node, GameController parent) {
        super(parent.engine, "team");
        this.parent = parent;
        mName = node.name;
        //xxx: error handling (when team-theme not found)
        char[] colorId = parent.checkTeamColor(node["color"]);
        teamColor = engine.gfx.teamThemes[colorId];
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

    this (ReflectCtor c) {
        super(c);
    }

    // --- start Team

    char[] name() {
        return mName;
    }

    char[] id() {
        return mTeamId;
    }

    TeamTheme color() {
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

    bool active() {
        return mActive;
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

    TeamMember[] getMembers() {
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
    }
    int crateSpy() {
        return mCrateSpy;
    }

    void doubleDmg(int dblCount) {
        mDoubleDmg = dblCount;
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
    ///only for a member, not the team, use setActive for team
    void current(TeamMember cur) {
        if (cur is mCurrent)
            return;
        if (mCurrent)
            mCurrent.setActive(false);
        mCurrent = cur;
        if (cur)
            mLastActive = cur;
        if (mCurrent) {
            mCurrent.setActive(true);
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
    //module-private (not to be used by gamemodes)
    private void setActive(bool act) {
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

    override void simulate(float deltaT) {
        bool has_active_worm;

        foreach (m; mMembers) {
            has_active_worm |= m.active;
        }

        if (!has_active_worm)
            setActive(false);

        if (current && current.control.actionPerformed())
            mAllowSelect = false;
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
            m.sprite.pleasedie();
        }
    }

    void addDoubleDamage() {
        mDoubleDmg++;
    }

    void addCrateSpy() {
        mCrateSpy++;
    }
}

//member of a team, currently (and maybe always) capsulates a WormSprite object
class TeamMember : GameObject {
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
    }

    this(char[] a_name, Team a_team) {
        super(a_team.engine, "team_member");
        this.mName = a_name;
        this.mTeam = a_team;
        internal_active = true;
    }

    this (ReflectCtor c) {
        super(c);
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

    bool active() {
        return mActive;
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
        assert (!mWormControl);
        //create and place into the landscape
        //habemus lumbricus
        Sprite worm = engine.createSprite("worm");
        WormSprite xworm = castStrict!(WormSprite)(worm); //xxx no WormSprite
        assert(worm !is null);
        worm.physics.lifepower = mTeam.initialPoints;
        mWormControl = new WormControl(worm);
        mWormControl.setWeaponSet(mTeam.weapons);
        mWormControl.setAlternateControl(mTeam.alternateControl);
        mWormControl.setDelayedDeath();
        mTeam.parent.addMemberGameObject(this, worm);
        mLastKnownLifepower = health;
        mCurrentHealth = mHealthTarget = health;
        updateHealth();
        //take control over dying, so we can let them die on end of turn
        xworm.gravestone = mTeam.gravestone;
        xworm.teamColor = mTeam.color;
        //let Controller place the worm
        engine.queuePlaceOnLandscape(worm);
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

    void setActive(bool act) {
        mWormControl.setEngaged(act);
        if (mActive == act)
            return;
        mActive = act;
        if (act) {
            mLastKnownLifepower = health;

            OnTeamMemberActivate.raise(this);
        } else {
            OnTeamMemberDeactivate.raise(this);
        }
    }

    override void simulate(float deltaT) {
        mWormControl.simulate();

        //mWormControl deactivates itself if the worm was e.g. injured
        if (!mWormControl.engaged())
            setActive(false);

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
class GameController {
    private {
        GameEngine mEngine;
        static LogStruct!("game.controller") log;

        Team[] mTeams;

        TeamMember[GameObject] mGameObjectToMember;

        //xxx for loading only
        ConfigNode[char[]] mWeaponSets;
        WeaponSet mCrateSet;

        bool mIsAnythingGoingOn; // (= hack)

        Gamemode mGamemode;
        char[] mGamemodeId;

        CrateSprite mLastCrate;  //just to drop it on spacebar
        bool mGameEnded;

        //Medkit, medkit+tool, medkit+tool+unrigged weapon
        //  (rest is rigged weapon)
        const cCrateProbs = [0.20f, 0.40f, 0.95f];
        //list of tool crates that can drop
        char[][] mActiveCrateTools;
        int[] mTeamColorCache;

        GamePlugin[char[]] mPluginLookup;
        GamePlugin[] mPlugins;
        //xxx this should be configurable
        const char[][] cLoadPlugins = ["messages", "statistics", "persistence"];
    }

    //when a worm collects a tool from a crate
    ChainDelegate!(TeamMember, CollectableTool) collectTool;

    this(GameEngine engine, GameConfig config) {
        mEngine = engine;
        mEngine.setController(this);

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

        mGamemodeId = config.gamemode["mode"];
        mGamemode = GamemodeFactory.instantiate(mGamemodeId, this,
            config.gamemode);

        //only valid while loading
        mWeaponSets = null;

        foreach (pid; cLoadPlugins) {
            //only load once
            if (!(pid in mPluginLookup)) {
                mPlugins ~= GamePluginFactory.instantiate(pid, engine);
                mPluginLookup[pid] = mPlugins[$-1];
            }
        }

        mEngine.finishPlace();

        collectTool ~= &doCollectTool;
    }

    this (ReflectCtor c) {
        Types t = c.types();
        t.registerMethod(this, &doCollectTool, "doCollectTool");
    }

    //--- start GameLogicPublic

    char[] gamemodeId() {
        return mGamemodeId;
    }

    ///True if game has ended
    bool gameEnded() {
        return mGamemode.ended;
    }

    ///Status of selected gamemode (may contain timing, scores or whatever)
    Gamemode gamemode() {
        return mGamemode;
    }

    ///Request interface to a plugin; returns null if the plugin is not loaded
    Object getPlugin(char[] id) {
        return aaIfIn(mPluginLookup, id);
    }

    //--- end GameLogicPublic

    void addCrateTool(char[] id) {
        assert(arraySearch(mActiveCrateTools, id) < 0);
        mActiveCrateTools ~= id;
    }

    GameEngine engine() {
        return mEngine;
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
        //lol, see gamemode comments for how this should really be used
        mGamemode.initialize();
        mGamemode.startGame();
    }

    void simulate() {
        Time diffT = mEngine.gameTime.difference;

        if (!mIsAnythingGoingOn) {
            startGame();
        } else {
            mGamemode.simulate();

            if (mLastCrate) {
                if (!mLastCrate.activity) mLastCrate = null;
            }

            if (mGamemode.ended() && !mGameEnded) {
                mGameEnded = true;

                OnGameEnd.raise(engine.globalEvents);

                //increase total round count
                engine.persistentState.setValue("round_counter",
                    currentRound + 1);

                debug {
                    saveConfig(engine.persistentState,
                        "persistence_debug.conf");
                }
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

    //this function now is no longer special, can use t.setActive directly
    void activateTeam(Team t, bool active = true) {
        t.setActive(active);
    }

    void deactivateAll() {
        foreach (t; mTeams) {
            activateTeam(t, false);
        }
    }

    //actually still stupid debugging code
    private void spawnWorm(Vector2i pos) {
        //now stupid debug code in another way
        auto w = mEngine.createSprite("worm");
        w.activate(toVector2f(pos));
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

    WeaponSet initWeaponSet(char[] id, bool forCrate = false) {
        ConfigNode ws;
        if (id in mWeaponSets)
            ws = mWeaponSets[id];
        else
            ws = mWeaponSets["default"];
        if (!ws)
            throw new Exception("Weapon set " ~ id ~ " not found.");
        return new WeaponSet(mEngine, ws, forCrate);
    }

    //like "weapon_sets" in gamemode.conf, but renamed according to game config
    private void loadWeaponSets(ConfigNode config) {
        //1. complete sets
        char[] firstId;
        foreach (ConfigNode item; config) {
            if (firstId.length == 0)
                firstId = item.name;
            if (item.value.length == 0)
                mWeaponSets[item.name] = item;
        }
        //2. referenced sets
        foreach (ConfigNode item; config) {
            if (item.value.length > 0) {
                if (!(item.value in mWeaponSets))
                    throw new Exception("Weapon set " ~ item.value
                        ~ " not found.");
                mWeaponSets[item.name] = mWeaponSets[item.value];
            }
        }
        if (mWeaponSets.length == 0)
            throw new Exception("No weapon sets defined.");
        //we always need a default set
        assert(firstId in mWeaponSets);
        if (!("default" in mWeaponSets))
            mWeaponSets["default"] = mWeaponSets[firstId];
        //crate weapon set is named "crate_set" (will fall back to "default")
        mCrateSet = initWeaponSet("crate_set", true);
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
                for (int n = 0; n < cnt; n++) {
                    //try {
                        mEngine.queuePlaceOnLandscape(
                            mEngine.createSprite(sub["type"]));
                    /*} catch {
                        log("Warning: Placing {} objects failed", sub["type"]);
                        continue;
                    }*/
                }
            } else {
                log("warning: unknown placing mode: '{}'", sub["mode"]);
            }
        }
        log("done placing level objects");
    }

    //associate go with member; used i.e. for who-damages-who reporting
    //NOTE: tracking membership of projectiles generated by worms works slightly
    //  differently (projectiles form a singly linked list to who fired them)
    void addMemberGameObject(TeamMember member, GameObject go) {
        //NOTE: the GameObject stays in this AA for forever
        //  in some cases, it could be released again (i.e. after a new round
        //  was started)
        assert(!go.createdBy, "fix memberFromGameObject and remove this");
        mGameObjectToMember[go] = member;
    }

    //transitive:
    //  false = go must be a team member worm; if not, return null
    //  true = like false, but if go was created by a team member, also return
    //      that team member
    TeamMember memberFromGameObject(GameObject go, bool transitive) {
        //typically, GameObject is transitively (consider spawning projectiles!)
        //created by a Worm
        //"victim" from reportViolence should be directly a Worm

        while (transitive && go.createdBy) {
            go = go.createdBy;
        }

        return aaIfIn(mGameObjectToMember, go);
    }

    WeaponClass weaponFromGameObject(GameObject go) {
        //commonly, everything causing damage is transitively created by
        //  a Shooter, but not always (consider landscape objects/crates/
        //  exploding worms)
        Shooter sh;
        while ((sh = cast(Shooter)go) is null && go.createdBy) {
            go = go.createdBy;
        }
        if (sh !is null)
            return sh.weapon;
        return null;
    }

    //return WormControl, by which go is controlled
    //  transitive: go can also be something spawned by that WormControl
    WormControl controlFromGameObject(GameObject go, bool transitive) {
        TeamMember m = memberFromGameObject(go, transitive);
        return m ? m.control : null;
    }

    void reportViolence(GameObject cause, Sprite victim, float damage) {
        assert(!!cause && !!victim);
        OnDamage.raise(victim, cause, damage);
    }

    void reportDemolition(int pixelCount, GameObject cause) {
        assert(!!cause);
        OnDemolish.raise(cause, pixelCount);
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
    bool dropCrate(bool silent = false) {
        Vector2f from, to;
        if (!engine.placeObjectRandom(10, 25, from, to)) {
            log("couldn't find a safe drop-position");
            return false;
        }

        Sprite s = engine.createSprite("crate");
        CrateSprite crate = cast(CrateSprite)s;
        assert(!!crate);
        //put stuffies into it
        crate.stuffies = fillCrate();
        //actually start it
        crate.activate(from);
        mLastCrate = crate;
        if (!silent) {
            //xxx move into CrateSprite.activate()
            OnCrateDrop.raise(crate);
        }
        log("drop {} -> {}", from, to);
        return true;
    }

    void instantDropCrate() {
        if (mLastCrate)
            mLastCrate.unParachute();
    }

    private bool doCollectTool(TeamMember collector, CollectableTool tool)
    {
        if (auto t = cast(CollectableToolCrateSpy)tool) {
            collector.team.addCrateSpy();
            return true;
        }
        if (auto t = cast(CollectableToolDoubleDamage)tool) {
            collector.team.addDoubleDamage();
            return true;
        }
        return false;
    }

    //show effects of sudden death start
    //doesn't raise water / affect gameplay
    void startSuddenDeath() {
        engine.addEarthQuake(500, timeSecs(4.5f), true);
        engine.callbacks.nukeSplatEffect();
        OnSuddenDeath.raise(engine.globalEvents);
    }
}
