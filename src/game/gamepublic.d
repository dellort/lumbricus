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
import utils.misc;

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


import common.visual;

//xxx: move into another module, or whatever
//does the annoying and disgusting job of wrapping unserializable FormattedText
//  in a serializable class
class RenderText {
    private {
        GameEngine mEngine;
        struct Transient {
            FormattedText renderer;
        }
        Transient mT;
        char[] mMarkupText;
        BoxProperties mBorder;
        Color mFontColor;
    }

    //if non-null, this is visible only if true is returned
    bool delegate(TeamMember t) visibility;

    this(GameEngine a_engine) {
        mEngine = a_engine;
        //init to what we had in the GUI in r865
        mBorder.border = Color(0.7);
        mBorder.back = Color(0);
        mBorder.cornerRadius = 3;
        mFontColor = Color(0.9);
    }
    this(ReflectCtor c) {
        c.transient(this, &mT);
    }

    char[] markupText() {
        return mMarkupText;
    }
    void markupText(char[] txt) {
        if (mMarkupText == txt)
            return;
        mMarkupText = txt.dup; //copy for more safety
        update();
    }

    Color color() {
        return mFontColor;
    }
    void color(Color c) {
        if (c == mFontColor)
            return;
    }

    //do:
    //  markupText = format(fmt, ...);
    //the good thing about this method is, that it doesn't allocate memory if
    //  the text doesn't change => you can call this method every frame, even
    //  if nothing changes, without trashing memory
    void setFormatted(char[] fmt, ...) {
        char[80] buffer = void;
        //(markupText setter compares and then copies anyway)
        markupText = formatfx_s(buffer, fmt, _arguments, _argptr);
    }

    //--- non-determinstic functions following here

    private void update() {
        if (!mT.renderer) {
            mT.renderer = new FormattedText();
            mT.renderer.font = gFramework.fontManager.loadFont("wormfont");
        }
        mT.renderer.setBorder(mBorder);
        mT.renderer.setMarkup(mMarkupText);
        FontProperties p = mT.renderer.font.properties;
        auto p2 = p;
        p2.fore = mFontColor;
        if (p2 != p) {
            mT.renderer.font = gFramework.fontManager.create(p2);
        }
    }

    FormattedText renderer() {
        if (!mT.renderer) {
            update();
            assert(!!mT.renderer);
        }
        return mT.renderer;
    }

    void draw(Canvas c, Vector2i pos) {
        if (visible())
            renderer.draw(c, pos);
    }

    Vector2i size() {
        return renderer.textSize();
    }

    bool visible() {
        if (!visibility)
            return true;
        auto getcontrolled = mEngine.callbacks.getControlledTeamMember;
        if (!getcontrolled)
            return true;
        return visibility(getcontrolled());
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

    MDelegate!() nukeSplatEffect;

    //looks like I'm turning this into a dumping ground for other stuff

    //for transient effects
    ParticleWorld particleEngine;
    Scene scene;

    //needed for rendering team specific stuff (crate spies)
    TeamMember delegate() getControlledTeamMember;

    //used for interpolated/extrapolated drawing (see GameShell.frame())
    //NOTE: changes in arbitrary way on replays (restoring snapshots)
    TimeSourcePublic interpolateTime;
}

