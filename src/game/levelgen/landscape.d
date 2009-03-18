module game.levelgen.landscape;

import framework.framework;
import common.resources;
import common.resset;
import utils.configfile;

//LEvel ELement
//collection of flags (yup, it's a bitfield now)
//all 0 means pixel is free
//!= 0 always means there's a collision
public enum Lexel : ubyte {
    Null = 0,
    SolidSoft = 1, // destroyable ground
    SolidHard = 2, // undestroyable ground

    //bits that are free for use - they can be used to associate additional
    //  "material" properties with a pixel, which are used in the physic code,
    //  when objects collide with the landscape (or whatever)
    //currently, the first (Type_Bit_Min) is used for snow
    Type_Bit_Min = 4,
    Type_Bit_Max = 128,

    INVALID = 255,
    Max = 2,       //marker for highest valid value
}

//the part of the themeing which is still needed for a fully rendered level
//this is a smaller part of the real LevelTheme
//in generator.d, there's another type LandscapeGenTheme which contains theme
//graphics needed for rendering a Landscape
class LandscapeTheme {
    //all members are read-only after initialization

    //for the following two things, the color is only used if the Surface is null

    //the landscape border where landscape was destroyed
    Color borderColor = {0.6,0.6,0};
    Surface borderImage;

    //background image for the level (visible when parts of level destroyed)
    Color backColor = {0,0,0,0};
    Surface backImage;

    //corresponds to "landscape" node in a level theme
    this(ConfigNode node) {
        ResourceSet res = gResources.loadResSet(node);

        void load(char[] name, out Surface s, out Color c) {
            s = res.get!(Surface)(node[name ~ "_tex"], true);
            c.parse(node.getStringValue(name ~ "_color"));

            //throw new what
        }

        load("border", borderImage, borderColor);
        load("soil", backImage, backColor);
    }
}
