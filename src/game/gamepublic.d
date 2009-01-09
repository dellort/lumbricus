///This module contains everything the ClientEngine should see of the
///GameEngine, to make the client-server-link weaker
///NOTE: you must _not_ cast interface to not-statically-known other types
module game.gamepublic;

import framework.framework;
import framework.resset : Resource;
import framework.timesource;
import game.animation;
import game.gfxset : TeamTheme;
import game.glevel;
import game.weapon.types;
//import game.weapon.weapon;
import game.levelgen.level;
//import game.levelgen.landscape;
import game.levelgen.renderer;
import utils.configfile;
import utils.vector2;
import utils.time;
import utils.list2;
import utils.reflection;

//lol compiler breaks horribly with this selective import uncommented
import game.sequence;// : SequenceUpdate;

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
class GameConfig {
    Level level;
    ConfigNode saved_level; //is level.saved
    char[][] weaponsets;
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

    ConfigNode save() {
        //xxx: not nice. but for now...
        ConfigNode to = new ConfigNode();
        to.getSubNode("level").mixinNode(saved_level);
        to.getSubNode("teams").mixinNode(teams);
        to.getSubNode("weapons").mixinNode(weapons);
        to.getSubNode("gamemode").mixinNode(gamemode);
        to.getSubNode("levelobjects").mixinNode(levelobjects);
        to.getSubNode("gfx").mixinNode(gfx);
        to.setValueArray!(char[])("weaponsets", weaponsets);
        return to;
    }

    void load(ConfigNode n) {
        level = null;
        load_savegame = null;
        saved_level = n.getSubNode("level");
        teams = n.getSubNode("teams");
        weapons = n.getSubNode("weapons");
        gamemode = n.getSubNode("gamemode");
        levelobjects = n.getSubNode("levelobjects");
        gfx = n.getSubNode("gfx");
        weaponsets = n.getValueArray!(char[])("weaponsets");
    }

    //the following stuff should probably be moved to something in game.setup
    //it doesn't really affect the game itself, but rather how it's started

    bool as_pseudo_server;

    //xxx hack that was convenient BUT MUST DIE PLEASE KILL ME
    char[] load_savegame; //now a filename
}

//for now, these are concrete classes...
//generally, you have the problem, that these objects contain both server and
// client state, e.g. the position, the currently played animation, the position
// in the animation playback... so now, these classes contain all state (uh,
// most state) that is used by the client engine to display stuff, especially
// this is needed when saving & restoring is involved
//hurrr.... feel free to unhack it
//game engine shall only use the methods to access stuff
class GameEngineGraphics {
    //add_objects is for the client engine, to get to know about new objects
    List2!(Graphic) objects;
    //in the network case, delivers the server engine's time of the last update
    //for now, it's always the game time
    TimeSource timebase;
    //incremented on each update
    ulong current_frame = 1;
    //last frame when something was added to objects
    //(object changes/removal requires the client to poll the object's state)
    ulong last_objects_frame;

    this (TimeSource ts) {
        objects = new typeof(objects);
        timebase = ts;
    }
    this (ReflectCtor c) {
        c.types().registerClass!(typeof(objects))();
    }

    void remove(Graphic n) {
        if (objects.contains(n.node)) {
            objects.remove(n.node);
        } else {
            //if (!n.removed)
            //    std.stdio.writefln(n);
            assert (n.removed);
        }
        n.removed = true;
    }

    private void doadd(Graphic g) {
        g.node = objects.add(g);
        g.frame_added = current_frame;
        last_objects_frame = current_frame;
    }

    AnimationGraphic createAnimation() {
        auto n = new AnimationGraphic(this);
        doadd(n);
        return n;
    }

    LineGraphic createLine() {
        auto n = new LineGraphic(this);
        doadd(n);
        return n;
    }

    TargetCross createTargetCross(TeamTheme theme, SequenceUpdate attach) {
        auto n = new TargetCross(this);
        n.theme = theme;
        n.attach = attach;
        doadd(n);
        return n;
    }

    ExplosionGfx createExplosionGfx(Vector2i pos, int diameter) {
        auto n = new ExplosionGfx(this);
        n.pos = pos;
        n.diameter = diameter;
        n.start = timebase.current();
        doadd(n);
        return n;
    }

    //xxx stuff about sharing etc. removed (it is still in r533)
    //    the idea was that with networking (= unshared LandscapeBitmap), on
    //    creation, only a game.levelgen.landscape.Landscape is passed, and
    //    further modifications to the landscape are replicated by transfering
    //    only damage(pos, radius) calls etc.
    //    when networking is introduced, one has to care about this again
    LandscapeGraphic createLandscape(Vector2i pos, LandscapeBitmap shared) {
        auto n = new LandscapeGraphic(this);
        n.pos = pos;
        n.shared = shared;
        doadd(n);
        return n;
    }
}

class Graphic {
    GameEngineGraphics owner;
    ListNode node;
    bool removed;
    ulong frame_added;

    this (GameEngineGraphics a_owner) {
        owner = a_owner;
    }
    this (ReflectCtor c) {
    }

    void remove() {
        owner.remove(this);
    }
}

class AnimationGraphic : Graphic {
    Animation animation;
    Time animation_start;
    int set_timestamp; //incremented everytime the animation is reset
    //xxx use SequenceUpdate directly?
    Vector2i pos;
    AnimationParams params;
    //xxx this is a hack only to make something in gameview.d work again
    //    I don't know what we really should do here etc....
    //    maybe make Sequence a "client" object again?
    SequenceUpdate more;

    this (GameEngineGraphics a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
    }

    final void update(ref Vector2i a_pos, ref AnimationParams a_params) {
        pos = a_pos;
        params = a_params;
    }
    final void update(ref Vector2i a_pos) {
        pos = a_pos;
    }

    final void setAnimation(Animation a_animation, Time startAt = Time.Null) {
        animation = a_animation;
        animation_start = owner.timebase.current() + startAt;
        set_timestamp++;
    }

    //don't know if this is consistent with Animator.hasFinished()
    //but here, it returns true if currently a frame is displayed
    //stupid code duplication with common.animation
    final bool hasFinished() {
        if (!animation)
            return true;
        if (animation.repeat || animation.keepLastFrame)
            return false;
        return (owner.timebase.current
            >= animation_start + animation.duration());
    }
}

class LineGraphic : Graphic {
    Vector2i p1, p2;
    Color color;

    this (GameEngineGraphics a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
    }

    void setPos(Vector2i a_p1, Vector2i a_p2) {
        p1 = a_p1;
        p2 = a_p2;
    }

    void setColor(Color c) {
        color = c;
    }
}

class TargetCross : Graphic {
    TeamTheme theme;
    SequenceUpdate attach; //where position and angle are read from
    float load = 0.0f;
    bool doreset;

    this (GameEngineGraphics a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
    }

    //value between 0.0 and 1.0 for the fire strength indicator
    void setLoad(float a_load) {
        load = a_load;
    }

    void reset() {
        doreset = true;
    }
}

class ExplosionGfx : Graphic {
    Vector2i pos;
    int diameter;
    Time start;

    this (GameEngineGraphics a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
    }
}

class LandscapeGraphic : Graphic {
    LandscapeBitmap shared; //special handling when the game is saved
    Vector2i pos;

    this (GameEngineGraphics a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
    }

    //pos is in world coordinates for both methods
    //void damage(Vector2i pos, int radius);
    //void insert(Vector2i pos, Resource!(Surface) bitmap);
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

    ///xxx really should return a level (both server and client should have it)
    ///total size of game world and camera start
    Vector2i worldSize();
    Vector2i worldCenter();

    ///is the game time paused?
    bool paused();

    ///time flow multiplier
    float slowDown();

    ///return the GameLogic singleton
    GameLogicPublic logic();

    GameEngineGraphics getGraphics();
}

/+
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
+/

enum RoundState {
    prepare,    //player ready
    playing,    //round running
    waitForSilence, //before entering cleaningUp: wait for no-activity
    cleaningUp, //worms losing hp etc, may occur during round
    nextOnHold, //next round about to start (drop crates, ...)
    winning,    //short state to show the happy survivors
    end,        //everything ended!
}

class WeaponHandle {
    Resource!(Surface) icon;
    char[] name;
    int value;
    char[] category;

    //serializable for simplicity
    this () {}
    this (ReflectCtor c) {}
}

///interface to the server's GameLogic
///the server can have this per-client to do client-specific actions
///it's not per-team
///xxx: this looks as if it work only work
interface GameLogicPublic {

    ///all participating teams (even dead ones)
    Team[] getTeams();

    ///all currently playing teams (not just the controlled one)
    Team[] getActiveTeams();

    RoundState currentRoundState();

    bool gameEnded();

    //BIIIIG xxxXXXXXXXXXXX:
    //why can it query the current time all the time? what about network?

    //display this to the user when RoundState.playing or .prepare
    Time currentRoundTime();

    ///only for RoundState.prepare
    Time currentPrepareTime();

    ///list of _all_ possible weapons, which are useable during the game
    ///Team.getWeapons() must never return a Weapon not covered by this list
    WeaponHandle[] weaponList();

    ///let the client display a message (like it's done on round's end etc.)
    ///this is a bit complicated because message shall be translated on the
    ///client (i.e. one client might prefer Klingon, while the other is used
    ///to Latin); so msgid and args are passed to the translation functions
    ///this returns a value, that is incremented everytime a new message is
    ///available
    int getMessageChangeCounter();
    ///message can be read out with this
    void getLastMessage(out char[] msgid, out char[][] msg);

    ///value increments, if the weapon list of any team changes
    int getWeaponListChangeCounter();
}

interface TeamMember {
    char[] name();
    Team team();

    ///worm is healthy (synonym for health()>0)
    ///can return false even if worm is still shown on the screen
    bool alive();

    ///if there's at least one TeamMemberControl which refers to this (?)
    bool active();

    ///might be under 0
    ///the controller updates this from time to time, so it probably doesn't
    ///reflect the real situation
    int currentHealth();

    ///last time this worm did an action (or so)
    Time lastAction();

    WeaponHandle getCurrentWeapon();
    ///show the weapon as an icon near the worm; used when the weapon can not be
    ///displayed directly (like when worm is on a jetpack)
    bool displayWeaponIcon();

    Graphic getGraphic();
}

//a trivial list of weapons and quantity
alias WeaponListItem[] WeaponList;
struct WeaponListItem {
    WeaponHandle type;
    //quantity or the magic value QUANTITY_INFINITE if unrestricted amount
    int quantity;
    //if weapon is allowed by the game controller (e.g. no airstrikes in caves)
    bool enabled;

    //value is guaranteed to be an int > 0
    const int QUANTITY_INFINITE = int.max;

    ///return if a weapon is available
    //warning: rarely used, does not define when weapon is really available
    bool available() {
        return enabled && (quantity > 0);
    }
}

interface Team {
    char[] name();
    TeamTheme color();

    ///at least one member with active() == true
    bool active();

    /// weapons of this team, always up-to-date
    /// might return null if it's "private" and you shouldn't see it
    WeaponList getWeapons();

    TeamMember[] getMembers();

    ///currently active worm, null if none
    TeamMember getActiveMember();
}

//calls from client to server which control a worm
//this should be also per-client, but it isn't per Team (!)
//i.e. in non-networked multiplayer mode, there's only one of this
interface ClientControl {
    ///TeamMember that would receive keypresses
    ///a member of one team from GameLogicPublic.getActiveTeams()
    ///_not_ always the same member or null
    TeamMember getControlledMember();

    void executeCommand(char[] cmd);
}
