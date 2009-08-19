//This module is outdated crap. It used to contain the complete interface
//between the game engine, and the "client" part, which consisted of rendering
//graphics, the hud, the GUI, low level input handling...
//But now, things have changed. Just don't think this would make any sense.
//(In the future, one should seperate the game into deterministic and non-
// deterministic parts... or something like this.)
module game.gamepublic;

import framework.i18n : LocalizedMessage;
import framework.framework;
import framework.timesource;
import common.scene;
import game.animation;
import game.gfxset;
import game.game;
import game.controller; //: Team, TeamMember
//import game.glevel;
import game.weapon.types;
import game.weapon.weapon;
import game.levelgen.level;
//import game.levelgen.landscape;
import game.levelgen.renderer;
import game.particles;
import utils.configfile;
import utils.vector2;
import utils.time;
import utils.list2;
import utils.md;
import utils.reflection;

import tango.math.Math : PI;

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
    //contains subnode "access_map", which maps tag-names to team-ids
    //the tag-name is passed as first arg to GameEngine.executeCmd(), see there
    ConfigNode managment;

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
        to.setValue!(char[][])("weaponsets", weaponsets);
        to.setStringValue("random_seed", randomSeed);
        to.addNode("managment", managment.copy);
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
        weaponsets = n.getValue!(char[][])("weaponsets");
        randomSeed = n["random_seed"];
        managment = n.getSubNode("managment");
    }
}


enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    Landscape,
    LevelWater,  //water before the level, but behind drowning objects
    Objects,
    Names,       //stuff drawn by gameview.d
    Crosshair,
    Effects, //whatw as that
    Particles,
    Clouds,
    FrontWater,
    RangeArrow,  //object-off-level-area arrow
    Splat,   //Fullscreen effect
}

//blergh
class GameEngineGraphics {
    GameEngine engine;
    //add_objects is for the client engine, to get to know about new objects
    ObjectList!(Graphic, "node") objects;
    //== engine.gameTime()
    TimeSourcePublic timebase;

    this (GameEngine a_engine) {
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



///calls from engine into clients
///for stuff that can't simply be polled
///anyone in the client engine can register callbacks here
class GameEngineCallback {
    ///called if the weapon list of any team changes
    ///value increments, if the weapon list of any team changes
    MDelegate!(Team) weaponsChanged;

    //very hacky *sigh* - maybe controller should always generate events for
    //  showing damage labels, instead of making gameview.d poll it?
    //args: (drowning member, lost healthpoints, out-of-screen position)
    MDelegate!(TeamMember, int, Vector2i) memberDrown;

    MDelegate!(Graphic) newGraphic;
    MDelegate!(Graphic) removeGraphic;

    MDelegate!() nukeSplatEffect;

    //looks like I'm turning this into a dumping ground for other stuff

    //for transient effects
    ParticleWorld particleEngine;
    Scene scene;

    //used for interpolated/extrapolated drawing (see GameShell.frame())
    //NOTE: changes in arbitrary way on replays (restoring snapshots)
    TimeSourcePublic interpolateTime;
}

