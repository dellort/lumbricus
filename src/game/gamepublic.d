///This module contains everything the ClientEngine should see of the
///GameEngine, to make the client-server-link weaker
///NOTE: you must _not_ cast interface to not-statically-known other types
module game.gamepublic;

import framework.framework;
import game.animation;
import game.glevel;
import game.weapon;
import levelgen.level;
import utils.configfile;
import utils.vector2;
import utils.time;

public import game.temp;

/+
Possible game setups
--------------------------
We have to think about which setups shall be possible in the feature.
I thought of these (first level hardware setup, second one game setups).
- Fully local, one screen, one keyboard for all:
    - Normal round-based multiplayer
        . 1 TeamMemberControl for all
    - Arcade/Realtime, where several players are at once active.
- Local, splitscreen:
    - Arcade: Need somehow to share the keyboard...
        . 2 TeamMemberControl (one for each player)
    (- Round based: Uh, isn't useful here.)
- Multiplayer, one screen on each PC:
    - Round based_
        . 2 TeamMemberControl (one for each player)
    - Arcade:
        . as in round based case
xxx complete this :)
currently, only local-roundbased-one-screen is the only possible setup
+/

///Initial game configuration
struct GameConfig {
    Level level;
    ConfigNode teams;
    ConfigNode weapons;
    ConfigNode gamemode;
}

enum GraphicEventType {
    None,
    Add,
    Change,
    Remove,
}

const long cInvalidUID = -1;

struct GraphicEvent {
    GraphicEvent* next; //ad-hoc linked list

    GraphicEventType type;
    long uid;
    GraphicSetEvent setevent;
}

struct GraphicSetEvent {
    Vector2i pos;
    Vector2f dir; //direction + velocity
    int p1, p2;
    bool do_set_ani;
    AnimationResource set_animation; //network had to transfer animation id
    bool set_force;
}

///GameEngine public interface
interface GameEnginePublic {
    ///callbacks (only at most one callback interface possible)
    void setGameEngineCalback(GameEngineCallback gec);

    ///called if the client did setup everything
    ///i.e. if the client-engine was initialized, all callbacks set...
    void signalReadiness();

    ///get an administrator interface (xxx add some sort of protection)
    GameEngineAdmin requestAdmin();

    ///current water offset
    int waterOffset();

    ///current wind speed
    float windSpeed();

    ///list of graphics events for the client to process
    GraphicEvent* currentEvents();

    ///clear list of currently pending events
    void clearEvents();

    ///get controller interface
    //ControllerPublic controller();

    ///level being played
    Level level();

    ///another level (xxx maybe join those?)
    GameLevel gamelevel();

    ///total size of game world
    Vector2i worldSize();

    ///is the game time paused?
    bool paused();

    ///time flow multiplier
    float slowDown();

    ///return the GameLogic singleton
    GameLogicPublic logic();
}

///administrator interface to game
///contains functions to change game/world state
interface GameEngineAdmin {
    ///raise water level
    void raiseWater(int by);

    ///change wind speed
    void setWindSpeed(float speed);

    ///pause game
    void setPaused(bool paused);

    ///slow down game time
    void setSlowDown(float slow);
}

///calls from engine into clients
interface GameEngineCallback {
    ///cause damage; if explode is true, play corresponding particle effects
    //void damage(Vector2i pos, int radius, bool explode);

    ///called on the following events:
    ///- Water or wind changed,
    ///- paused-state toggled,
    ///- or slowdown set.
    void onEngineStateChanged();
}

enum RoundState {
    prepare,    //player ready
    playing,    //round running
    waitForSilence, //before entering cleaningUp: wait for no-activity
    cleaningUp, //worms losing hp etc, may occur during round
    nextOnHold, //next round about to start (drop crates, ...)
    winning,    //short state to show the happy survivors
    end,        //everything ended!
}

///interface to the server's GameLogic
///the server can have this per-client to do client-specific actions
///it's not per-team
///xxx: this looks as if it work only work
interface GameLogicPublic {
    ///only one callback possible
    void setGameLogicCallback(GameLogicPublicCallback glpc);

    ///all participating teams (even dead ones)
    Team[] getTeams();

    //xxx Team[] getActiveTeams();

    RoundState currentRoundState();

    //BIIIIG xxxXXXXXXXXXXX:
    //why can it query the current time all the time? what about network?

    //display this to the user when RoundState.playing or .prepare
    Time currentRoundTime();

    ///only for RoundState.prepare
    Time currentPrepareTime();

    ///xxx: should return an array for the case where two teams are active on
    ///on client at the same time?
    TeamMemberControl getControl();
}

//to be implemented by the client
interface GameLogicPublicCallback {
    ///Time remaining of teams' round time, shown ticking down if not paused
    ///not all game modes have to use this
    void gameLogicRoundTimeUpdate(Time t, bool timePaused);

    //called if currentRoundState() changed
    void gameLogicUpdateRoundState();

    ///called when the WeaponList of a specific team updates
    ///team is null if for all teams
    ///xxx: does it belong here?
    void gameLogicWeaponListUpdated(Team team);

    ///let the client display a message (like it's done on round's end etc.)
    ///this is a bit complicated because message shall be translated on the
    ///client (i.e. one client might prefer Klingon, while the other is used
    ///to Latin); so msgid and args are passed to the translation functions
    void gameShowMessage(char[] msgid, char[][] args);

    ///you shall update all game stats; these are:
    ///- Healthiness of all teams.
    //xxx void gameLogicUpdateStats();
}

interface TeamMember {
    char[] name();
    Team team();

    ///worm is healthy (synonym for health()>0)
    ///i.e. can return false even if worm is still shown on the screen
    bool alive();

    ///if there's at least one TeamMemberControl which refers to this (?)
    bool active();

    int health();

    /// uid of the current member-graphic (maybe always the the worm)
    /// might return InvalidUID if worm dead, invisible, or similar
    long getGraphic();
}

//a trivial list of weapons and quantity
alias WeaponListItem[] WeaponList;
struct WeaponListItem {
    WeaponClass type;
    //quantity or the magic value QUANTITY_INFINITE if unrestricted amount
    int quantity;

    const int QUANTITY_INFINITE = int.max;
}

interface Team {
    char[] name();
    TeamColor color();

    ///at least one member with alive() == true
    bool alive();

    ///like in alive()
    bool active();

    int totalHealth();

    /// weapons of this team, always up-to-date
    /// might return null if it's "private" and you shouldn't see it
    WeaponList getWeapons();

    TeamMember[] getMembers();
    //??? TeamMember getActiveMember();
}

//calls from client to server which control a worm
//this should be also per-client, but it isn't per Team (!)
//i.e. in non-networked multiplayer mode, there's only one of this
interface TeamMemberControl {
    //there is only one callback interface
    void setTeamMemberControlCallback(TeamMemberControlCallback tmcc);

    ///currently active worm, null if none
    TeamMember getActiveMember();

    ///redundant to getActiveMember and TeamMember.team
    Team getActiveTeam();

    ///last time a worm did an action (or so)
    Time currentLastAction();

    ///select the next worm in row
    ///this does not have to work, nothing will happen if selecting is not
    ///possible
    void selectNextMember();

    ///what kind of movement control is possible
    WalkState walkState();

    ///make the active worm jump
    void jump(JumpMode mode);

    ///set jetpack mode
    //xxx making this a function assumes that the jetpack is not a weapon
    //xxx NOTE: we should have worm "vehicles" (weapons which control worm-
    //          movement, i.e. jetpack, beamer, rope, bengee, glider.)
    void jetpack(bool active);

    ///set the movement vector for the active worm
    ///only the sign counts, speed is always fixed
    ///the worm will move by this vector from this call on
    ///(0,0) to stop
    ///note that the worm may stop by itself for several explosive reasons
    void setMovement(Vector2i m);

    ///what kinds of weapons can be used at the current member state
    ///e.g. no weapons while in mid-air
    WeaponMode weaponMode();

    ///select weapon weaponId for the active worm
    void weaponDraw(WeaponClass weaponId);

    WeaponClass currentWeapon();

    ///set grenade timer (cf. Weapon for useful values)
    void weaponSetTimer(Time timer);

/+
xxx handled by setMovement()
    ///set firing angle, possible angles depend on selected weapon
    ///will be rounded for weapons with fixed angles
    void weaponAim(float angle);
+/

    ///set target of targetting weapon, showing a big X on the hated opponent
    ///how the target is accquired (e.g. mouse click, use same as last, ...)
    ///is handled by the client
    void weaponSetTarget(Vector2i targetPos);

    ///actually fire weapon with parameters set before
    ///needs a preceeding call of weaponStartFire with current weapon to work
    ///xxx weaponStartFire removed because I didn't know what it was for
    void weaponFire(float strength);
}

interface TeamMemberControlCallback {
    ///another team member has become active/inactive
    ///setting null means gaining/losing control of the current member
    ///one example is round-ended or worm switching
    void controlMemberChanged();

    void controlWalkStateChanged();

    ///what kinds of weapons can be used at the current member state
    ///e.g. no weapons while in mid-air
    void controlWeaponModeChanged();

    ///feedback for drawing weapons, as weapon selection may be changed by
    ///controller (out of ammo, jetpack activated, ...) (xxx should it be?)
    //void weaponDraw(char[] weaponId);
}

//Hint: there's a limited number of predefined colors; that's because sometimes
//colors are hardcoded in animations, etc.
//so, these are not just color names, but also linked to these animations
static const char[][] cTeamColors = [
    "red",
    "blue",
    "green",
    "yellow",
    "magenta",
    "cyan",
];

//use this datatype to clearly reference an cTeamColors entry
alias int TeamColor;
