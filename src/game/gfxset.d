module game.gfxset;

import common.animation;
import framework.framework;
import framework.resset;
import framework.resources : ResourceObject, addToResourceSet;
import game.sequence; //only for loading grr
import utils.color;
import utils.configfile;

import path = std.path;

//references all graphic/sound (no sounds yet) resources etc.
class GfxSet {
    ConfigNode config;

    ResourceSet resources;

    //keyed by the theme name (TeamTheme.name)
    TeamTheme[char[]] teamThemes;

    Color waterColor;

    //how the target cross looks like
    TargetCrossSettings targetCross;

    private void loadTeamThemes() {
        for (int n = 0; n < TeamTheme.cTeamColors.length; n++) {
            auto tt = new TeamTheme(resources, n);
            teamThemes[tt.name()] = tt;
        }
    }

    //omg hack
    private static class SequenceWrapper : ResourceObject {
        Object obj;
        Object get() {
            return obj;
        }
        this(Object o) {
            obj = o;
        }
    }

    private void loadSequenceStuff() {
        auto conf = config.getSubNode("sequences");
        foreach (ConfigNode sub; conf) {
            auto pload = sub.name in AbstractSequence.loaders;
            if (!pload) {
                throw new Exception("sequence loader not found: "~sub.name);
            }
            foreach (ConfigItem subsub; sub) {
                SequenceObject seq = (*pload)(resources, subsub);
                resources.addResource(new SequenceWrapper(seq), seq.name);
            }
        }
    }

    //gfx = GameConfig.gfx
    //the constructor does allmost all the work, but you have to call
    //finishLoading() too; in between, you can preload the resources
    this(ConfigNode gfx) {
        char[] gfxname = gfx.getStringValue("config", "wwp");
        char[] watername = gfx.getStringValue("waterset", "blue");

        resources = new ResourceSet();

        config = gFramework.resources.loadConfigForRes(gfxname ~ ".conf");
        auto graphics = gFramework.resources.loadResources(config);
        addToResourceSet(resources, graphics.getAll());

        auto waterfile = gFramework.resources.loadConfigForRes("water"~path.sep
            ~watername~path.sep~"water.conf");
        auto watergfx = gFramework.resources.loadResources(waterfile);
        addToResourceSet(resources, watergfx.getAll());

        waterColor.parse(waterfile["color"]);

        //xxx if you want, add code to load targetCross here
    }

    //call after resources have been preloaded
    void finishLoading() {
        //loaded after all this because Sequences depend from Animations etc.
        loadSequenceStuff();
        resources.seal(); //disallow addition of more resources
        loadTeamThemes();
    }
}

//per-team themeing used by the game engine, by the GUI etc.
//all members are read only after initialization
class TeamTheme {
    Color color;
    int colorIndex; //index into cTeamColors

    //wwp hardcodes these colors (there are separate bitmaps for each)
    static const char[][] cTeamColors = [
        "red",
        "blue",
        "green",
        "yellow",
        "magenta",
        "cyan",
    ];

    Resource!(Animation) arrow;
    Resource!(Animation) pointed;
    Resource!(Animation) change;
    Resource!(Animation) cursor;
    Resource!(Animation) click;
    Resource!(Animation) aim;

    //the name used to identify the theme
    //does not anymore equal to color string, see colors.conf
    char[] name() {
        return cTeamColors[colorIndex];
    }

    this(ResourceSet resources, int index) {
        colorIndex = index;
        char[] colorname = cTeamColors[colorIndex];
        color.parse("team_" ~ colorname); //if it fails, it is messed up

        Resource!(Animation) loadanim(char[] node) {
            return resources.resource!(Animation)(node ~ "_" ~ name());
        }

        arrow = loadanim("darrow");
        pointed = loadanim("pointed");
        change = loadanim("change");
        cursor = loadanim("point");
        click = loadanim("click");
        aim = loadanim("aim");
    }
}

//I feel a little bit guilty to place this here, but who cares
struct TargetCrossSettings {
    int targetDist = 90; //distance target-cross-center to worm-center
    int targetStartDist = 10;   //initial distance (for animate-away)
    int loadStart = 8; //start of the load-thing
    int loadEnd = 100; //end of it
    Color colorStart = Color(0.8,0,0); //colors of the load-thing
    Color colorEnd = Color(1,1,0.3);
    int radStart = 3; //min/max radius for these circles
    int radEnd = 10;
    int add = 1; //distance of circle centers
    int stipple = 7; //change color after that number of circles (>0, in pixels)
    float targetDegrade = 0.98f; //animate-away speed, multiplicator per millisecond
}
