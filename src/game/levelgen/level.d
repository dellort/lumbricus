module game.levelgen.level;

import common.animation;
import framework.framework;
import common.resources;
import common.resset;
import game.levelgen.landscape;
import game.levelgen.renderer;
import utils.configfile;
import utils.color;
import utils.misc;
import utils.rect2;
import utils.vector2;

//contains graphics about the global level "environment", which is currently how
//the level background looks like
//xxx what about the water and the clouds?
class EnvironmentTheme {
    Color skyColor;

    //used to draw the background; both can be null
    Surface skyGradient; //if null, use the color fields below
    Surface skyBackdrop;

    //(I don't want a "generic" gradient description struct, because that would
    // go too far again, because I'd add gradient directions, color runs, etc.)
    Color skyGradientTop;
    Color skyGradientHalf;
    Color skyGradientBottom;

    //can be null
    Animation skyDebris;

    //corresponds to a level.conf "environment" node
    this(ConfigNode node) {
        ResourceSet res = gResources.loadResSet(node);

        skyGradient = res.get!(Surface)(node["gradient"], true);
        skyBackdrop = res.get!(Surface)(node["backdrop"], true);
        skyDebris = res.get!(Animation)(node["debris"], true);
        skyColor.parse(node.getStringValue("skycolor"));

        //(sky.d uses skyGradient if it exists anyway)
        if (auto sub = node.findNode("sky_gradient")) {
            skyGradientTop.parse(sub["top"]);
            skyGradientHalf.parse(sub["half"]);
            skyGradientBottom.parse(sub["bottom"]);
        }
    }
}

//stores the layout of the level (level [bitmap] itself, positions of statical
//objects, worms, etc.)
//also shall be used to cache positions of placed worms and mines
//not used in-game (the game only uses it to create the world, except for the
//above thing)
class Level {
    /+char[] name;
    char[] description;+/

    //if this is true, no aistrikes are possible and no clouds are shown
    //(apart from that there are no differences: usually, the level is simply
    // much smaller so that you only see the landscape => looks like a cave)
    //bool isCave;

    //defines the world size; the rectangular area of everything you can view
    Vector2i worldSize;
    //bounding box for the contained landscape(s), and possibly everything else
    Rect2i landBounds;

    //allow airstrikes?
    bool airstrikeAllow;

    //all y coordinates below are in world coordinates

    //water starts out at bottom and can grow until it reaches top
    int waterBottomY;
    int waterTopY;

    //y coordinates for the sky area; the sky will put clouds under sky_top_y,
    //draw sky debris between bottom and top, and draw some gradients in the
    //background of this area
    //int skyBottomY; sky bottom implicit by water
    int skyTopY;

    //if airstrike_allow is true, where airstrikes should be started
    int airstrikeY;

    //-1 .. +1
    //float initialWind;

    EnvironmentTheme theme;

    //various objects placed in the level
    //includes at least the level bitmap
    LevelItem[] objects;

    //saved version of this Level
    //normally is only returned by the level generator and doesn't get updated
    ConfigNode saved;

    //for the level generator; does a deep copy
    Level copy() {
        Level nlevel = new Level();
        foreach (int n, t; this.tupleof) {
            nlevel.tupleof[n] = t;
        }
        if (nlevel.saved) {
            nlevel.saved = nlevel.saved.copy();
        }
        nlevel.objects = objects.dup;
        foreach (ref o; nlevel.objects) {
            o = o.copy();
            o.owner = this;
        }
        return nlevel;
    }

    Vector2i worldCenter() {
        return landBounds.center();
    }
}

//used for the landscape and mines
class LevelItem {
    Level owner;
    char[] name;

    protected void copyFrom(LevelItem other) {
        name = other.name;
    }

    final LevelItem copy() {
        //dirty but simple
        auto res = castStrict!(LevelItem)(this.classinfo.create());
        res.copyFrom(this);
        return res;
    }
}

/*class LevelItemObject : LevelItem {
    Vector2i position;
    char[] type;
}*/

class LevelLandscape : LevelItem {
    Vector2i position, size;
    LandscapeTheme landscape_theme;
    //may be null, if the Level was render()ed with render_bitmaps=false
    LandscapeBitmap landscape;
    //for each landscape side if there should be an impenetrable wall
    //bool[4] impenetrable;

    protected override void copyFrom(LevelItem other) {
        super.copyFrom(other);
        auto o = castStrict!(LevelLandscape)(other);
        position = o.position;
        size = o.size;
        //if (o.landscape)
          //  landscape = o.landscape.copy();
        landscape = o.landscape;
        landscape_theme = o.landscape_theme;
    }
}


//helpers
//xxx these should be moved away, they really don't belong here
package:

import str = stdx.string;

private static char[][] marker_strings = ["FREE", "LAND", "SOLID_LAND"];

Lexel parseMarker(char[] value) {
    static Lexel[] marker_values = [Lexel.Null, Lexel.SolidSoft,
        Lexel.SolidHard];
    for (uint i = 0; i < marker_strings.length; i++) {
        if (str.icmp(value, marker_strings[i]) == 0) {
            return marker_values[i];
        }
    }
    //else explode
    throw new Exception("invalid marker value in configfile: " ~ value);
}

char[] writeMarker(Lexel v) {
    return marker_strings[v];
}
