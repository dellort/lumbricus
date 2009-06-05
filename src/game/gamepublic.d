///This module contains everything the ClientEngine should see of the
///GameEngine, to make the client-server-link weaker
///NOTE: you must _not_ cast interface to not-statically-known other types
module game.gamepublic;

import framework.i18n : LocalizedMessage;
import framework.framework;
import common.resset : Resource;
import framework.timesource;
import game.animation;
import game.gfxset;
//import game.glevel;
import game.weapon.types;
import game.weapon.weapon;
import game.levelgen.level;
//import game.levelgen.landscape;
import game.levelgen.renderer;
import utils.configfile;
import utils.vector2;
import utils.time;
import utils.list2;
import utils.md;
import utils.reflection;

//lol compiler breaks horribly with this selective import uncommented
import game.sequence;// : SequenceUpdate;

public import game.temp;


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
    char[] randomSeed;

    //state that survives multiple rounds, e.g. worm statistics and points
    ConfigNode gamestate;

    ConfigNode save() {
        //xxx: not nice. but for now...
        ConfigNode to = new ConfigNode();
        to.addNode("level", saved_level.copy);
        to.addNode("teams", teams.copy);
        to.addNode("weapons", weapons.copy);
        to.addNode("gamemode", gamemode.copy);
        to.addNode("levelobjects", levelobjects.copy);
        to.addNode("gfx", gfx.copy);
        to.addNode("gamestate", gamestate.copy);
        to.setValueArray!(char[])("weaponsets", weaponsets);
        to.setStringValue("random_seed", randomSeed);
        return to;
    }

    void load(ConfigNode n) {
        level = null;
        saved_level = n.getSubNode("level");
        teams = n.getSubNode("teams");
        weapons = n.getSubNode("weapons");
        gamemode = n.getSubNode("gamemode");
        levelobjects = n.getSubNode("levelobjects");
        gfx = n.getSubNode("gfx");
        gamestate = n.getSubNode("gamestate");
        weaponsets = n.getValueArray!(char[])("weaponsets");
        randomSeed = n["random_seed"];
    }
}

//blergh
class GameEngineGraphics {
    GameEnginePublic engine;
    //add_objects is for the client engine, to get to know about new objects
    ObjectList!(Graphic, "node") objects;
    //== engine.gameTime()
    TimeSourcePublic timebase;

    this (GameEnginePublic a_engine) {
        objects = new typeof(objects);
        engine = a_engine;
        timebase = engine.gameTime;
    }
    this (ReflectCtor c) {
        c.types().registerClass!(typeof(objects))();
    }

    void remove(Graphic n) {
        if (objects.contains(n)) {
            objects.remove(n);
            n.removed = true;
            engine.callbacks.removeGraphic(n);
        } else {
            //if (!n.removed)
            //    Trace.formatln(n);
            assert (n.removed);
        }
    }

    void add(Graphic g) {
        assert(!g.owner);
        g.owner = this;
        objects.add(g);
        engine.callbacks.newGraphic(g);
    }
}

//xxx this crap is a relict of the now dead pseudo network stuff
//    remove/redo this if you feel like it
abstract class Graphic {
    GameEngineGraphics owner;
    ObjListNode!(typeof(this)) node;
    bool removed;

    this() {
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

    //xxx for now just for the camera, might be subject to change
    Team owner_team;
    Time last_position_change; //actually, need time of last "action"?

    this (Team ownerTeam = null) {
        owner_team = ownerTeam;
    }
    this (ReflectCtor c) {
        super(c);
    }

    final void update(ref Vector2i a_pos, ref AnimationParams a_params) {
        assert(!!owner);
        if (pos != a_pos) {
            pos = a_pos;
            last_position_change = owner.timebase.current();
        }
        if (params != a_params) {
            params = a_params;
            last_position_change = owner.timebase.current();
        }
    }
    final void update(ref Vector2i a_pos) {
        pos = a_pos;
    }

    final void setAnimation(Animation a_animation, Time startAt = Time.Null) {
        assert(!!owner);
        animation = a_animation;
        animation_start = owner.timebase.current() + startAt;
        set_timestamp++;
    }

    //don't know if this is consistent with Animator.hasFinished()
    //but here, it returns true if currently a frame is displayed
    //stupid code duplication with common.animation
    final bool hasFinished() {
        assert(!!owner);
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
    int width = 1;
    Resource!(Surface) texture;
    int texoffset = 0;

    this () {
    }
    this (ReflectCtor c) {
        super(c);
    }

    void setPos(Vector2i a_p1, Vector2i a_p2) {
        p1 = a_p1;
        p2 = a_p2;
    }

    void setWidth(int w) {
        width = w;
    }

    void setColor(Color c) {
        color = c;
    }

    //if the backend is OpenGL, use a texture instead of the color to draw
    //the line; the line is as thick as the height of tex
    //both the color and the line width are ignored
    //SDL still will use the color to actually draw the line
    void setTexture(Resource!(Surface) tex) {
        texture = tex;
    }
    void setTextureOffset(int offs) {
        texoffset = offs;
    }
}

class CrosshairGraphic : Graphic {
    TeamTheme theme;
    SequenceUpdate attach; //where position and angle are read from
    float load = 0.0f;
    bool doreset;

    this (TeamTheme theme, SequenceUpdate attach) {
        this.theme = theme;
        this.attach = attach;
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

class LandscapeGraphic : Graphic {
    LandscapeBitmap shared; //special handling when the game is saved
    Vector2i pos;

    this (Vector2i pos, LandscapeBitmap shared) {
        this.pos = pos;
        this.shared = shared;
    }
    this (ReflectCtor c) {
        super(c);
    }

    //pos is in world coordinates for both methods
    //void damage(Vector2i pos, int radius);
    //void insert(Vector2i pos, Resource!(Surface) bitmap);
}

class TextGraphic : Graphic {
    char[] msgMarkup;
    Vector2i pos;
    //how the label-rect is attached to pos, for each axis 0.0-1.0
    //(0,0) is the upper left corner, (1,1) the bottom right corner
    Vector2f attach = {0, 0};
    //for isVisible(); see below
    bool delegate(TeamMember) visibleDg;

    //takes getControlledMember() result, returns if text is shown
    bool isVisible(TeamMember activeMember) {
        if (visibleDg)
            return visibleDg(activeMember);
        return true;
    }

    this () {
    }
    this (ReflectCtor c) {
        super(c);
    }
}


///GameEngine public interface
interface GameEnginePublic {
    ///current water offset
    int waterOffset();

    ///current wind speed
    float windSpeed();

    ///return how strong the earth quake is, 0 if no earth quake active
    float earthQuakeStrength();

    ///level being played, must not modify returned object
    Level level();

    ///game configuration, must not modify returned object
    GameConfig config();

    ///game resources, must not modify returned object
    GfxSet gfx();

    ///xxx really should return a level (both server and client should have it)
    ///total size of game world and camera start
    Vector2i worldSize();
    Vector2i worldCenter();

    ///return the GameLogic singleton
    GameLogicPublic logic();

    GameEngineGraphics getGraphics();

    GameEngineCallback callbacks();

    //carries time of last network update in networking case, I guess?
    TimeSourcePublic gameTime();

    ///list of _all_ possible weapons, which are useable during the game
    ///Team.getWeapons() must never return a Weapon not covered by this list
    WeaponClass[] weaponList();
}

///calls from engine into clients
///for stuff that can't simply be polled
///anyone in the client engine can register callbacks here
class GameEngineCallback {
    ///called if the weapon list of any team changes
    ///value increments, if the weapon list of any team changes
    MDelegate!(Team) weaponsChanged;

    MDelegate!(Graphic) newGraphic;
    MDelegate!(Graphic) removeGraphic;

    MDelegate!(Vector2i, int) explosionEffect;
    MDelegate!() nukeSplatEffect;
    MDelegate!(Animation, Vector2i, AnimationParams) animationEffect;
}

///interface to the server's GameLogic
///the server can have this per-client to do client-specific actions
///it's not per-team
///xxx: this looks as if it work only work
interface GameLogicPublic {

    ///all participating teams (even dead ones)
    Team[] getTeams();

    char[] gamemode();

    ///True if game has ended
    bool gameEnded();

    ///Status of selected gamemode (may contain timing, scores or whatever)
    Object gamemodeStatus();

    ///Request interface to a plugin; returns null if the plugin is not loaded
    Object getPlugin(char[] id);
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

    ///animation state, or something
    WormAniState wormState();

    WeaponClass getCurrentWeapon();
    ///show the weapon as an icon near the worm; used when the weapon can not be
    ///displayed directly (like when worm is on a jetpack)
    bool displayWeaponIcon();

    //messy, I decided this is always the controlled thing
    //(not always worm itself, e.g. this can point to a super sheep)
    Graphic getGraphic();
    Graphic getControlledGraphic();
}

//a trivial list of weapons and quantity
alias WeaponListItem[] WeaponList;
struct WeaponListItem {
    WeaponClass type;
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
    char[] id();
    TeamTheme color();

    ///at least one member with active() == true
    bool active();

    /// weapons of this team, always up-to-date
    /// might return null if it's "private" and you shouldn't see it
    WeaponList getWeapons();

    TeamMember[] getMembers();

    ///currently active worm, null if none
    TeamMember getActiveMember();

    ///is it possible to choose another worm (tab key)
    bool allowSelect();

    ///wins so far; normally incremented for the winner team on game end
    int globalWins();

    bool hasCrateSpy();

    bool hasDoubleDamage();
}

//calls from client to server which control a worm
//this should be also per-client, but it isn't per Team (!)
//i.e. in non-networked multiplayer mode, there's only one of this
interface ClientControl {
    ///TeamMember that would receive keypresses
    ///a member of one team from GameLogicPublic.getActiveTeams()
    ///_not_ always the same member or null
    TeamMember getControlledMember();

    ///The teams associated with this controller
    ///Does not mean any or all the teams can currently be controlled (they
    ///  can still be deactivated by controller)
    Team[] getOwnedTeams();

    void executeCommand(char[] cmd);
}
