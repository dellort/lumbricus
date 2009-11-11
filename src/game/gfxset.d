module game.gfxset;

import common.animation;
import framework.framework;
import game.particles : ParticleType;
import common.config;
import common.resset;
import common.resources : gResources, ResourceFile;
//import common.macroconfig;
import utils.color;
import utils.configfile;
import utils.time;
import utils.serialize;

import physics.collisionmap;
import physics.world;
import game.sequence;
import game.gamepublic; //:GameConfig
import game.sprite;
import game.weapon.weapon;

class ClassNotRegisteredException : Exception {
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
        char[][] mWeaponSets;
        ConfigNode[] mSequenceConfig;
        ConfigNode[] mCollNodes;

        //managment of sprite classes, for findSpriteClass()
        GOSpriteClass[char[]] mSpriteClasses;

        //same for weapons (also such a two-stage factory, creates Shooters)
        WeaponClass[char[]] mWeaponClasses;

        Object[char[]] mActionClasses;

        CollisionMap mCollisionMap;

        bool mFinished;
    }

    char[] gfxId;
    //xxx only needed by sky.d
    ConfigNode config;

    //null until begin of finishLoading()
    ResourceSet resources;

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
        foreach (ConfigNode node; config.getSubNode("particles")) {
            ParticleType p = new ParticleType();
            p.read(resources, node);
            resources.addResource(p, node.name);
        }
    }

    //the constructor does allmost all the work, but you have to call
    //finishLoading() too; in between, you can preload the resources
    this(GameConfig cfg) {
        ConfigNode gfx = cfg.gfx;

        gfxId = gfx.getStringValue("config", "wwp");
        char[] watername = gfx.getStringValue("waterset", "blue");

        //resources = new ResourceSet();

        config = gResources.loadConfigForRes(gfxId ~ ".conf");
        addGfxSet(config);

        auto waterfile = gResources.loadConfigForRes("water/"
            ~ watername ~ "/water.conf");
        load_resources ~= gResources.loadResources(waterfile);

        waterColor = waterfile.getValue("color", waterColor);

        //xxx if you want, add code to load crosshair here
        //...

        mSprites = config.getSubNode("sprites");
        mWeaponSets = cfg.weaponsets;

        mCollisionMap = new CollisionMap();
    }

    void addGfxSet(ConfigNode conf) {
        //resources
        load_resources ~= gResources.loadResources(conf);
        //sequences
        addSequenceNode(conf.getSubNode("sequences"));
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
            if (auto ani = cast(Animation)e.get!(Object)()) {
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
            auto sprite = loadConfig(value);
            loadSpriteClass(sprite);
        }

        //load weapons
        foreach (char[] ws; mWeaponSets) {
            loadWeapons("weapons/"~ws);
        }
    }

    //factory for GOSpriteClasses
    //the constructor of GOSpriteClasses will call:
    //  engine.registerSpriteClass(registerName, this);
    GOSpriteClass instantiateSpriteClass(char[] name, char[] registerName) {
        return SpriteClassFactory.instantiate(name, this, registerName);
    }

    //called by sprite.d/GOSpriteClass.this() only
    void registerSpriteClass(char[] name, GOSpriteClass sc) {
        if (findSpriteClass(name, true)) {
            assert(false, "Sprite class "~name~" already registered");
        }
        mSpriteClasses[name] = sc;
    }

    //find a sprite class
    GOSpriteClass findSpriteClass(char[] name, bool canfail = false) {
        GOSpriteClass* gosc = name in mSpriteClasses;
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
        auto res = instantiateSpriteClass(type, name);
        res.loadFromConfig(sprite);
    }

    //load all weapons from one weapon set (directory containing set.conf)
    //loads only collisions and weapon behavior, no resources/sequences
    private void loadWeapons(char[] dir) {
        auto set_conf = loadConfig(dir~"/set");
        auto coll_conf = loadConfig(dir ~ "/"
            ~ set_conf.getStringValue("collisions","collisions.conf"),true,true);
        if (coll_conf)
            addCollideConf(coll_conf.getSubNode("collisions"));
        //load all .conf files found
        char[] weaponsdir = dir ~ "/weapons";
        gFS.listdir(weaponsdir, "*.conf", false,
            (char[] path) {
                //a weapons file can contain resources, collision map
                //additions and a list of weapons
                auto wp_conf = loadConfig(weaponsdir ~ "/"
                    ~ path[0..$-5]);
                addCollideConf(wp_conf.getSubNode("collisions"));
                auto list = wp_conf.getSubNode("weapons");
                foreach (ConfigNode item; list) {
                    loadWeaponClass(item);
                }
                return true;
            }
        );
    }

    //a weapon subnode of weapons.conf
    private void loadWeaponClass(ConfigNode weapon) {
        char[] type = weapon.getStringValue("type", "action");
        //xxx error handling
        //hope you never need to debug this code!
        WeaponClass c = WeaponClassFactory.instantiate(type, this, weapon);
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

    //--
    void registerActionClass(Object o, char[] name) {
        assert(!(name in mActionClasses), "double action name: "~name);
        mActionClasses[name] = o;
    }

    void initSerialization(SerializeContext ctx) {
        assert(mFinished, "must have called finishLoading()");

        ctx.addExternal(this, "gfx");

        foreach (char[] key, TeamTheme tt; teamThemes) {
            ctx.addExternal(tt, "gfx_theme::" ~ key);
        }

        foreach (ResourceSet.Entry res; resources.resourceList()) {
            Object o = res.get!(Object)();
            ctx.addExternal(o, "res::" ~ res.name());
            //xxx: maybe generalize using an interface or so?
            if (auto seq = cast(SequenceType)o) {
                seq.initSerialization(ctx);
            }
        }

        foreach (char[] key, GOSpriteClass s; mSpriteClasses) {
            assert(key == s.name);
            char[] name = "sprite::" ~ key;
            ctx.addExternal(s, name);
            //if it gets more complicated than this, add a
            //  GOSpriteClass.initSerialization() method
            foreach (char[] key2, StaticStateInfo state; s.states) {
                assert(key2 == state.name);
                ctx.addExternal(state, name ~ "::" ~ key2);
            }
        }

        foreach (char[] key, WeaponClass w; mWeaponClasses) {
            assert(key == w.name);
            ctx.addExternal(w, "weapon::" ~ w.name);
        }

        foreach (char[] key, Object o; mActionClasses) {
            ctx.addExternal(o, "action::" ~ key);
        }

        ctx.addExternal(collision_map, "collision_map");
        foreach (CollisionType t; collision_map.collisionTypes()) {
            ctx.addExternal(t, "collision_type::" ~ t.name);
        }
    }
}

//per-team themeing used by the game engine, by the GUI etc.
//all members are read only after initialization
class TeamTheme {
    Color color;
    int colorIndex; //index into cTeamColors

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
