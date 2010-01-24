module game.gfxset;

import common.animation;
import framework.config;
import framework.framework;
import framework.font;
import game.particles : ParticleType;
import gui.rendertext;
import gui.renderbox;
import common.resset;
import common.resources : gResources, ResourceFile;
//import common.macroconfig;
import utils.color;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.factory;

import str = utils.string;

import physics.collisionmap;
import physics.world;
import game.events;
import game.sequence;
import game.setup;
import game.sprite;
import game.weapon.weapon;
import game.plugins;
import game.controller_events;

class ClassNotRegisteredException : CustomException {
    this(char[] msg) {
        super(msg);
    }
}

//references all graphic/sound (no sounds yet) resources etc.
//after r866: extended to carry sprites & sequences
class GfxSet {
    private {
        //bits from GameConfig; during loading
        ConfigNode mSprites;
        ConfigNode[] mSequenceConfig;
        ConfigNode[] mCollNodes;

        //managment of sprite classes, for findSpriteClass()
        SpriteClass[char[]] mSpriteClasses;

        //same for weapons (also such a two-stage factory, creates Shooters)
        WeaponClass[char[]] mWeaponClasses;

        CollisionMap mCollisionMap;

        bool mFinished;
        Font mFlashFont;

        bool[char[]] mLoadedPlugins;
    }

    //xxx only needed by sky.d
    ConfigNode config;

    //null until begin of finishLoading()
    ResourceSet resources;

    //lol sorry
    Events events;

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
    //list of active plugins, in load order
    Plugin[] plugins;

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
    this(GameConfig cfg) {
        events = new Events();

        ConfigNode gfx = cfg.gfx;

        mFlashFont = gFontManager.loadFont("wormfont_flash");

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
        mSprites = gameConf.getSubNode("sprites");

        mCollisionMap = new CollisionMap();
        addCollideConf(gameConf.getSubNode("collisions"));

        foreach (ConfigNode sub; cfg.plugins) {
            //either an unnamed value, or a subnode with config items
            char[] pid = sub.value.length ? sub.value : sub.name;
            try {
                loadPlugin(pid, sub, cfg.plugins);
            } catch (PluginException e) {
                //xxx we need "something" to handle non-fatal errors
                Trace.formatln("Plugin '{}' failed to load: {}", pid, e.msg);
            }
        }
    }

    void loadPlugin(char[] pluginId, ConfigNode cfg, ConfigNode allPlugins) {
        assert(!!allPlugins);
        if (pluginId in mLoadedPlugins) {
            return;
        }

        ConfigNode conf;
        if (str.eatStart(pluginId, "ext:")) {
            char[] confFile = "plugins/" ~ pluginId ~ "/plugin.conf";
            //load plugin.conf as gfx set (resources and sequences)
            conf = gResources.loadConfigForRes(confFile);
        } else {
            //internal plugin with no confignode
            conf = new ConfigNode();
            conf["internal_plugin"] = pluginId;
        }

        //mixin dynamic configuration
        if (cfg) {
            conf.getSubNode("config").mixinNode(cfg, true);
        }

        Plugin newPlugin = new Plugin(pluginId, this, conf);

        //this will place dependencies in the plugins[] first, making them load
        //  before the current plugin
        foreach (dep; newPlugin.dependencies) {
            try {
                loadPlugin(dep, allPlugins.findNode(dep), allPlugins);
            } catch (PluginException e) {
                throw new PluginException("Dependency '" ~ dep
                    ~ "' failed to load: " ~ e.msg);
            }
        }

        plugins ~= newPlugin;
        mLoadedPlugins[pluginId] = true;
    }

    //this also means that a bogus/changed resource file could cause scripting
    //  type errors, when it receives the wrong object type; maybe add some way
    //  to enforce a specific type?
    Object scriptGetRes(char[] name) {
        return resources.get!(Object)(name);
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
    void finishLoading(ResourceSet loaded_resources) {
        assert(!mFinished);
        assert(load_resources == null, "resources were added after preloading"
            " started => not good, they'll be missing");
        assert(!resources, "what");
        resources = loaded_resources;

        reversedHack();
        loadParticles();
        loadSprites();
        //loaded after all this because Sequences depend from Animations etc.
        //loadSequenceStuff();

        resources.seal(); //disallow addition of more resources

        loadTeamThemes();
        loadExplosions();

        mFinished = true;
    }

    //sequence.d wants to reverse some animations, and calls Animation.reversed()
    //that means a new reference to a non-serializable object is created, but
    //the object isn't catched by the resource system
    void reversedHack() {
        foreach (e; resources.resourceList().dup) {
            if (e.isAlias())
                continue;
            if (auto ani = cast(Animation)e.resource()) {
                resources.addResource(ani.reversed(), "reversed_" ~ e.name());
            }
        }
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

    private void loadSprites() {
        //load sequences
        foreach (ConfigNode node; mSequenceConfig) {
            foreach (ConfigNode sub; node) {
                auto t = new SequenceType(this, sub);
                resources.addResource(t, t.name);
            }
        }

        //load sprites
        foreach (char[] name, char[] value; mSprites) {
            auto sprite = loadConfig(value, true);
            loadSpriteClass(sprite);
        }

        //load weapons
        foreach (plg; plugins) {
            plg.finishLoading();
        }
    }

    //factory for SpriteClasses
    //the constructor of SpriteClasses will call:
    //  engine.registerSpriteClass(registerName, this);
    SpriteClass instantiateSpriteClass(char[] name, char[] registerName) {
        return SpriteClassFactory.instantiate(name, this, registerName);
    }

    //called by sprite.d/SpriteClass.this() only
    void registerSpriteClass(SpriteClass sc) {
        if (findSpriteClass(sc.name, true)) {
            assert(false, "Sprite class "~sc.name~" already registered");
        }
        assert(!!sc);
        mSpriteClasses[sc.name] = sc;
    }

    //find a sprite class
    SpriteClass findSpriteClass(char[] name, bool canfail = false) {
        SpriteClass* gosc = name in mSpriteClasses;
        if (gosc)
            return *gosc;

        if (canfail)
            return null;

        //not found? xxx better error handling (as usual...)
        throw new ClassNotRegisteredException("sprite class " ~ name
            ~ " not found");
    }

    //currently just worm.conf
    void loadSpriteClass(ConfigNode sprite) {
        char[] type = sprite.getStringValue("type", "notype");
        char[] name = sprite.getStringValue("name", "unnamed");
        SpriteClass res = instantiateSpriteClass(type, name);
        res.loadFromConfig(sprite);
        registerSpriteClass(res);
    }

    //mainly for scripts
    void registerWeapon(WeaponClass c) {
        assert(findWeaponClass(c.name, true) is null);
        mWeaponClasses[c.name] = c;
    }

    //find a weapon class
    WeaponClass findWeaponClass(char[] name, bool canfail = false) {
        WeaponClass* w = name in mWeaponClasses;
        if (w)
            return *w;

        if (canfail)
            return null;

        //not found? xxx better error handling (as usual...)
        throw new ClassNotRegisteredException("weapon class "
            ~ name ~ " not found");
    }

    ///list of _all_ possible weapons, which are useable during the game
    ///Team.getWeapons() must never return a Weapon not covered by this list
    ///not deterministic (arbitrary order of weapons)
    WeaponClass[] weaponList() {
        return mWeaponClasses.values;
    }

    SpriteClass[] allSpriteClasses() {
        return mSpriteClasses.values;
    }

    static BoxProperties textWormBorderStyle() {
        //init to what we had in the GUI in r865
        BoxProperties border;
        border.border = Color(0.7);
        border.back = Color(0,0,0,0.7);
        border.borderWidth = 1;
        border.cornerRadius = 3;
        return border;
    }

    //and some more hacky hacks
    static void textApplyWormStyle(FormattedText txt) {
        txt.setBorder(textWormBorderStyle());
        txt.font = gFontManager.loadFont("wormfont");
    }

    static FormattedText textCreate() {
        auto txt = new FormattedText();
        textApplyWormStyle(txt);
        return txt;
    }

    Font textFlashFont() {
        return mFlashFont;
    }
}

//per-team themeing used by the game engine, by the GUI etc.
//all members are read only after initialization
class TeamTheme {
    Color color;
    int colorIndex; //index into cTeamColors
    Font font, font_flash;

    //wwp hardcodes these colors (there are separate bitmaps for each)
    //the indices are also hardcoded to wwp (0 must be red etc.)
    static const char[][] cTeamColors = [
        "red",
        "blue",
        "green",
        "yellow",
        "magenta",
        "cyan",
    ];

    Animation arrow, pointed, change, cursor, click, aim;

    //the name used to identify the theme
    //does not anymore equal to color string, see colors.conf
    char[] name() {
        return cTeamColors[colorIndex];
    }

    this(ResourceSet resources, int index) {
        colorIndex = index;
        char[] colorname = cTeamColors[colorIndex];
        color = Color.fromString("team_" ~ colorname); //if it fails, it is messed up

        Animation loadanim(char[] node) {
            Animation ani = resources.get!(Animation)(node ~ "_" ~ name(), true);
            if (!ani)
                ani = resources.get!(Animation)(node);
            return ani;
        }

        arrow = loadanim("darrow");
        pointed = loadanim("pointed");
        change = loadanim("change");
        cursor = loadanim("point");
        click = loadanim("click");
        aim = loadanim("aim");

        font = gFontManager.loadFont("wormfont");
        //set color; Font is immutable
        auto style = font.properties;
        style.fore = color;
        font = new Font(style);

        font_flash = gFontManager.loadFont("wormfont_flash");
    }

    FormattedText textCreate() {
        auto txt = new FormattedText();
        GfxSet.textApplyWormStyle(txt);
        txt.font = font;
        return txt;
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
