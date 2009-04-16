module game.gfxset;

import common.animation;
import framework.framework;
import common.resset;
import common.resources : gResources, ResourceObject, addToResourceSet;
//import game.sequence : loadSequences; //only for loading grr
import utils.color;
import utils.configfile;
import utils.time;


//references all graphic/sound (no sounds yet) resources etc.
class GfxSet {
    char[] gfxId;
    //xxx only needed by sky.d
    ConfigNode config;
    ConfigNode[] sequenceConfig;

    ResourceSet resources;

    //keyed by the theme name (TeamTheme.name)
    TeamTheme[char[]] teamThemes;

    Color waterColor;

    //how the target cross looks like
    CrosshairSettings crosshair;

    ExplosionSettings expl;

    private void loadTeamThemes() {
        for (int n = 0; n < TeamTheme.cTeamColors.length; n++) {
            auto tt = new TeamTheme(resources, n);
            teamThemes[tt.name()] = tt;
        }
    }

    /+private void loadSequenceStuff() {
        foreach (conf; sequenceConfig) {
            loadSequences(resources, conf);
        }
    }+/

    private void loadExplosions() {
        expl.load(config.getSubNode("explosions"), resources);
    }

    //gfx = GameConfig.gfx
    //the constructor does allmost all the work, but you have to call
    //finishLoading() too; in between, you can preload the resources
    this(ConfigNode gfx) {
        gfxId = gfx.getStringValue("config", "wwp");
        char[] watername = gfx.getStringValue("waterset", "blue");

        resources = new ResourceSet();

        config = gResources.loadConfigForRes(gfxId ~ ".conf");
        addGfxSet(config);

        auto waterfile = gResources.loadConfigForRes("water/"
            ~ watername ~ "/water.conf");
        auto watergfx = gResources.loadResources(waterfile);
        addToResourceSet(resources, watergfx.getAll());

        waterColor.parse(waterfile["color"]);

        //xxx if you want, add code to load crosshair here
    }

    void addGfxSet(ConfigNode conf) {
        //resources
        auto resfile = gResources.loadResources(conf);
        addToResourceSet(resources, resfile.getAll());
        //sequences
        addSequenceNode(conf.getSubNode("sequences"));
    }

    //Params: n = the "sequences" node, containing loaders
    void addSequenceNode(ConfigNode n) {
        sequenceConfig ~= n;
    }

    //call after resources have been preloaded
    void finishLoading() {
        reversedHack();
        //loaded after all this because Sequences depend from Animations etc.
        //loadSequenceStuff();
        resources.seal(); //disallow addition of more resources
        loadTeamThemes();
        loadExplosions();
    }

    //sequence.d wants to reverse some animations, and calls Animation.reversed()
    //that means a new reference to a non-serializable object is created, but
    //the object isn't catched by the resource system
    void reversedHack() {
        foreach (e; resources.resourceList().dup) {
            if (auto ani = cast(Animation)e.wrapper.get()) {
                auto rani = new ReverseAnimationResource();
                rani.ani = ani.reversed();
                resources.addResource(rani, "reversed_" ~ e.name());
            }
        }
    }
}

class ReverseAnimationResource : ResourceObject {
    Animation ani;
    override Object get() {
        return ani;
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
struct CrosshairSettings {
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
    Time animDur = timeMsecs(250); //animate-away duration
}

struct ExplosionSettings {
    //animations for different explosion sizes
    Resource!(Animation)[4] shockwave1, shockwave2, comicText;
    //tresholds to choose animations matching size
    int[] sizeTreshold = [25, 100, 150, 200];

    void load(ConfigNode conf, ResourceSet res) {
        char[][] sw1 = conf.getValueArray!(char[])("shockwave1");
        foreach (int i, resid; sw1) {
            shockwave1[i] = res.resource!(Animation)(resid);
        }

        char[][] sw2 = conf.getValueArray!(char[])("shockwave2");
        foreach (int i, resid; sw2) {
            shockwave2[i] = res.resource!(Animation)(resid);
        }

        char[][] txt = conf.getValueArray!(char[])("comictext");
        foreach (int i, resid; txt) {
            comicText[i] = res.resource!(Animation)(resid);
        }

        int[] st = conf.getValue("sizetreshold",sizeTreshold);
        if (st.length >= 4)
            sizeTreshold = st;
    }
}
