///This module contains everything the ClientEngine should see of the
///GameEngine, to make the client-server-link weaker
///NOTE: you must _not_ cast interface to not-statically-known other types
module game.gamepublic;

import framework.framework;
import framework.resset : Resource;
import game.animation;
import game.gfxset : TeamTheme;
import game.glevel;
import game.weapon.weapon;
import game.levelgen.level;
//import game.levelgen.landscape;
import game.levelgen.renderer;
import utils.configfile;
import utils.vector2;
import utils.time;

import game.sequence;

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
    //objects which shall be created and placed into the level at initialization
    //(doesn't include the worms, ???)
    ConfigNode levelobjects;
    //infos for the graphicset, current items:
    // - config: string with the name of the gfx set, ".conf" will be appended
    //   to get the config filename ("wwp" becomes "wwp.conf")
    // - waterset: string with the name of the waterset (like "blue")
    //probably should be changed etc., so don't blame me
    ConfigNode gfx;
}

interface Graphic {
    //centered object position
    Rect2i bounds();

    //kill this graphic
    void remove();
}

//NOTE: in module game.sequence, there's "interface Sequence : Graphic {...}"

interface LineGraphic : Graphic {
    void setPos(Vector2i p1, Vector2i p2);
    void setColor(Color c);
    Rect2i bounds();
}

interface TargetCross : Graphic {
    //where position and angle are read from
    void attach(Sequence dest);
    //value between 0.0 and 1.0 for the fire strength indicator
    void setLoad(float load);
    //won't return anything useful lol
    Rect2i bounds();
}

//this is the level bitmap (aka Landscape etc.); it is precreated in the level
//generation/rendering step and it is modified by punching holes into it
//  damage() isn't listed as method here
interface LandscapeGraphic : Graphic {
    void setPos(Vector2i pos);
    //what LandscapeBitmap bitmap();

    //xxx these methods should be moved out to GameEngineGraphics?
    //pos is in world coordinates for both methods
    void damage(Vector2i pos, int radius);
    void insert(Vector2i pos, Resource!(Surface) bitmap);
}

///all graphics which are sent from server to client
interface GameEngineGraphics {
    Sequence createSequence(SequenceObject type);
    LineGraphic createLine();
    //target cross is always themed
    TargetCross createTargetCross(TeamTheme team);
    //the second parameter can be null; if it isn't, it's the directly shared
    //LandscapeBitmap instance between the server and client code
    LandscapeGraphic createLandscape(LevelLandscape from,
        LandscapeBitmap shared);
    //meh I don't know, maybe this should be put here
    //void damageLandscape(...);
}

///GameEngine public interface
interface GameEnginePublic {
    /+
    ///callbacks (only at most one callback interface possible)
    void setGameEngineCalback(GameEngineCallback gec);

    ///called if the client did setup everything
    ///i.e. if the client-engine was initialized, all callbacks set...
    void signalReadiness();
    +/

    ///get an administrator interface (xxx add some sort of protection)
    GameEngineAdmin requestAdmin();

    ///current water offset
    int waterOffset();

    ///current wind speed
    float windSpeed();

    ///return how strong the earth quake is, 0 if no earth quake active
    float earthQuakeStrength();

    ///get controller interface
    //ControllerPublic controller();

    ///level being played
    Level level();

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

    Graphic getGraphic();
}

//a trivial list of weapons and quantity
alias WeaponListItem[] WeaponList;
struct WeaponListItem {
    WeaponClass type;
    //quantity or the magic value QUANTITY_INFINITE if unrestricted amount
    int quantity;

    const int QUANTITY_INFINITE = int.max;

    ///return if a weapon is available
    bool available() {
        return quantity > 0;
    }
}

interface Team {
    char[] name();
    TeamTheme color();

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
    void weaponFire(bool is_down);
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

