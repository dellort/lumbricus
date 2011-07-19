module game.gfxset;

import common.animation;
import common.resources;
import framework.config;
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

import physics.all;
import game.core;
import game.events;
import game.sequence;
import game.setup;

struct LoadedWater {
    Color color;
    ResourceFile res;
}
alias LoadedWater delegate(ConfigNode) WaterLoadDg;
WaterLoadDg[string] gWaterLoadHack;

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
    TeamTheme[string] teamThemes;

    Color waterColor;

    //what the crosshair looks like
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
        auto conf = loadConfig("particles.conf");
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
        core.addSingleton(this);

        resources = core.resources;
        events = core.events;

        ConfigNode gfx = cfg.gfx;

        enum string cPreferredGraphics = "wwp.conf";
        enum string cFailsafeGraphics = "freegraphics.conf";

        ResourceFile resfile;

        string gfxconf = gfx.getStringValue("config", cPreferredGraphics);
        try {
            config = gResources.loadConfigForRes(gfxconf);
            resfile = addGfxSet(config);
        } catch (CustomException e) {
            //if that failed, try to load the free graphics set, which should be
            //  always available (only if that isn't already being loaded)
            //(xxx: the intention is to switch to the failsafe graphics if the
            //  requested ones don't exist; not to deal with buggy graphic sets,
            //  but right now we can't just test for the existence of a file to
            //  check the actual presence of a graphic set => we are more error
            //  tolerant than what we want and what is good, blergh)
            if (gfxconf == cFailsafeGraphics)
                throw e;
            core.log.error("Loading graphicsset in '%s' failed (%s), trying to"
                " load %s instead.", gfxconf, e, cFailsafeGraphics);
            gfxconf = cFailsafeGraphics;
            config = gResources.loadConfigForRes(gfxconf);
            resfile = addGfxSet(config);
        }

        //optional, water loader may override this
        waterColor = config.getValue!(Color)("watercolor", Color.Black);

        auto waterloader = config["waterloader"];
        if (waterloader != "") {
            auto pload = waterloader in gWaterLoadHack;
            if (!pload)
                throwError("water loader not found: %s", waterloader);
            auto res = (*pload)(gfx.getSubNode("waterset"));
            load_resources ~= res.res;
            waterColor = res.color;
        }

        //xxx if you want, add code to load crosshair here
        //...

        //xxx this file is loaded at two places (gravity in game engine)
        auto gameConf = loadConfig("game.conf");

        mCollisionMap = core.physicWorld.collide;
        addCollideConf(gameConf.getSubNode("collisions"));
    }

    Resources.Preloader createPreloader() {
        ResourceFile[] list = load_resources;
        load_resources = null;
        return gResources.createPreloader(list);
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
        ParticleType getp(string name) {
            Animation ani = res.get!(Animation)(name);
            auto p = new ParticleType;
            p.animation ~= ani;
            return p;
        }

        string[] sw1 = conf.getValue!(string[])("shockwave1");
        foreach (int i, resid; sw1) {
            shockwave1[i] = getp(resid);
        }

        string[] sw2 = conf.getValue!(string[])("shockwave2");
        foreach (int i, resid; sw2) {
            shockwave2[i] = getp(resid);
        }

        string[] txt = conf.getValue!(string[])("comictext");
        foreach (int i, resid; txt) {
            comicText[i] = getp(resid);
        }

        string[] smo = conf.getValue!(string[])("smoke");
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
