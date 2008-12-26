module game.levelgen.landscape;

import framework.framework;
import framework.resset;
import game.animation;
import utils.configfile;
public import game.levelgen.renderer;

//LEvel ELement
//collection of flags
//all 0 currently means pixel is free
public enum Lexel : ubyte {
    Null = 0,
    SolidSoft = 1, // destroyable ground
    SolidHard = 2, // undestroyable ground

    INVALID = 255
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
        ResourceSet res = gFramework.resources.loadResSet(node);

        void load(char[] name, out Surface s, out Color c) {
            s = res.get!(Surface)(node[name ~ "_tex"], true);
            c.parse(node.getStringValue(name ~ "_color"));

            //throw new what
        }

        load("border", borderImage, borderColor);
        load("soil", backImage, backColor);
    }
}
