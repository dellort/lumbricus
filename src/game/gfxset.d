module game.gfxset;

import common.animation;
import framework.config;
import framework.framework;
import framework.font;
import game.particles : ParticleType;
public import game.teamtheme;
import gui.rendertext;
import gui.renderbox;
import common.resset;
import common.resources : gResources, ResourceFile;
//import common.macroconfig;
import utils.color;
import utils.configfile;
import utils.misc;
import utils.time;

import str = utils.string;

import physics.collisionmap;
import physics.world;
import game.core;
import game.events;
import game.sequence;
import game.setup;


//references all graphic/sound (no sounds yet) resources etc.
//after r866: extended to carry sprites & sequences
//xxx doesn't seem to have much valur anymore... this used to hold all
//  resources that are loaded before the GameEngine is created, but now the
//  GameEngine is created before loading resources
//- right now, still handles some annoying loading code
class GfxSet {
    private {
        //bits from GameConfig; during loading
        ConfigNode[] mSequenceConfig;

        CollisionMap mCollisionMap;

        bool mFinished;
    }

    //xxx only needed by sky.d
    ConfigNode config;

    ResourceSet resources;
    Events events;

    //upper half of the GameEngine
    GameCore core;

    //needed during loading
    //- first, all resources are collected here
    //- then, they're loaded bit by bit (loading screen)
    //- finally, the loaded resources are added to the ResourceSet object above
    //all files must be added before mResPreloader is created in gameshell.d
    ResourceFile[] load_resources;

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

    private void loadExplosions() {
        expl.load(config.getSubNode("explosions"), resources);
    }

    private void loadParticles() {
        auto conf = loadConfig("particles");
        foreach (ConfigNode node; conf.getSubNode("particles")) {
            ParticleType p = new ParticleType();
            p.read(resources, node);
            resources.addResource(p, node.name);
        }
    }

    //the constructor does allmost all the work, but you have to call
    //finishLoading() too; in between, you can preload the resources
    this(GameCore a_core, GameConfig cfg)
    {
        core = a_core;

        resources = core.resources;
        events = core.events;

        ConfigNode gfx = cfg.gfx;

        char[] gfxconf = gfx.getStringValue("config", "wwp.conf");
        char[] watername = gfx.getStringValue("waterset", "blue");

        //resources = new ResourceSet();

        config = gResources.loadConfigForRes(gfxconf);
        auto resfile = addGfxSet(config);

        //resfile.fixPath for making the water dir relative to the other
        //  resources
        auto waterpath = resfile.fixPath(config.getStringValue("water_path"));
        auto waterfile = gResources.loadConfigForRes(waterpath ~ "/" ~
            watername ~ "/water.conf");
        load_resources ~= gResources.loadResources(waterfile);

        waterColor = waterfile.getValue("color", waterColor);

        //xxx if you want, add code to load crosshair here
        //...

        //xxx this file is loaded at two places (gravity in game engine)
        auto gameConf = loadConfig("game.conf", true);

        mCollisionMap = core.physicWorld.collide;
        addCollideConf(gameConf.getSubNode("collisions"));
    }

    //this also means that a bogus/changed resource file could cause scripting
    //  type errors, when it receives the wrong object type; maybe add some way
    //  to enforce a specific type?
    Object scriptGetRes(char[] name, bool canfail = false) {
        return resources.get!(Object)(name, canfail);
    }

    //just for scripting
    static FormattedText textCreate() {
        return WormLabels.textCreate();
    }

    ResourceFile addGfxSet(ConfigNode conf) {
        //resources
        auto file = gResources.loadResources(conf);
        load_resources ~= file;
        //sequences
        addSequenceNode(conf.getSubNode("sequences"));
        return file;
    }

    //Params: n = the "sequences" node, containing loaders
    void addSequenceNode(ConfigNode n) {
        //process_macros(n);
        mSequenceConfig ~= n;
    }

    //call after resources have been preloaded
    void finishLoading() {
        assert(!mFinished);
        assert(load_resources == null, "resources were added after preloading"
            " started => not good, they'll be missing");

        loadParticles();
        //loaded after all this because Sequences depend from Animations etc.
        loadSequences();

        //commented when weapons and sprite classes got managed as resources
        //--resources.seal(); //disallow addition of more resources

        loadTeamThemes();
        loadExplosions();

        mFinished = true;
    }

    //only for GameEngine
    CollisionMap collision_map() {
        mCollisionMap.seal();
        return mCollisionMap;
    }

    void addCollideConf(ConfigNode node) {
        if (node)
            mCollisionMap.loadCollisions(node);
    }

    //--- sprite & weapon stuff (static data)

    private void loadSequences() {
        //load sequences
        foreach (ConfigNode node; mSequenceConfig) {
            foreach (ConfigNode sub; node) {
                auto t = new SequenceType(core, sub);
                resources.addResource(t, t.name);
            }
        }
    }

    //add to resource list
    //this is typically used for weapons and spriteclasses, which are added
    //  after resource loading
    //the name must not be used yet
    void registerResource(char[] name, Object obj) {
        resources.addResource(obj, name);
    }

    //find all resources of a specific type
    //e.g. findResources!(WeaponClass)() => array of all possible weapons
    T[] findResources(T)() {
        return resources.findAll!(T)();
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
    ParticleType[4] shockwave1, shockwave2, comicText, smoke;
    ParticleType spark, sound;
    //tresholds to choose animations matching size
    int[] sizeTreshold = [25, 100, 150, 200];

    void load(ConfigNode conf, ResourceSet res) {
        ParticleType getp(char[] name) {
            Animation ani = res.get!(Animation)(name);
            auto p = new ParticleType;
            p.animation ~= ani;
            return p;
        }

        char[][] sw1 = conf.getValue!(char[][])("shockwave1");
        foreach (int i, resid; sw1) {
            shockwave1[i] = getp(resid);
        }

        char[][] sw2 = conf.getValue!(char[][])("shockwave2");
        foreach (int i, resid; sw2) {
            shockwave2[i] = getp(resid);
        }

        char[][] txt = conf.getValue!(char[][])("comictext");
        foreach (int i, resid; txt) {
            comicText[i] = getp(resid);
        }

        char[][] smo = conf.getValue!(char[][])("smoke");
        foreach (int i, resid; smo) {
            smoke[i] = getp(resid);
            smoke[i].gravity.min = -50f;
            smoke[i].gravity.max = -200f;
            smoke[i].bubble_x = 0.7f;
            smoke[i].bubble_x_h = 100f;
            smoke[i].wind_influence.min = 0.7f;
            smoke[i].wind_influence.max = 1.0f;
        }

        spark = res.get!(ParticleType)("p_spark");
        sound = res.get!(ParticleType)("p_explosion_sound");

        int[] st = conf.getValue("sizetreshold",sizeTreshold);
        if (st.length >= 4)
            sizeTreshold = st;
    }
}
