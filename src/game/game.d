module game.game;
import levelgen.level;
import game.animation;
import game.scene;
import game.gobject;
import game.physic;
import game.glevel;
import game.sprite;
import game.worm;
import game.water;
import game.sky;
import game.common;
import game.controller;
import game.weapon;
import projectile = game.projectile;
import special_weapon = game.special_weapon;
import utils.mylist;
import utils.time;
import utils.log;
import utils.configfile;
import utils.misc;
import framework.framework;
import framework.keysyms;
import std.math;

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
    BackLayer,
    BackWater,
    BackWaterWaves1,   //water behind the level
    BackWaterWaves2,
    Level,
    Objects,
    Names, //controller.d/WormNameDrawer
    FrontWater,  //water before the level
    FrontWaterWaves1,
    FrontWaterWaves2,
    FrontWaterWaves3,
}

struct GameConfig {
    Level level;
    ConfigNode teams;
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine {
    Level level;
    LevelObject levelobject;
    GameLevel gamelevel;
    Scene scene;
    PhysicWorld physicworld;
    PlaneGeometry waterborder;
    Time lastTime;
    Time currentTime;
    GameWater gameWater;
    GameSky gameSky;

    GameController controller;

    package Log mLog;

    //for simplicity of managment, store all animations globally
    //note that they are also referenced from i.e. spite.d/StaticStateInfo
    //access using loadAnimations() and findAnimation()
    private Animation[char[]] mAllLoadedAnimations;
    private ConfigNode mAllAnimations;
    //to prevent loading a configfile more than once
    //this is a hack!
    private bool[char[]] mLoadedAnimationConfigFiles;

    //collision handling stuff: map names to the registered IDs
    //used by loadCollisions() and findCollisionID()
    private CollisionType[char[]] mCollisionTypeNames;

    package List!(GameObject) mObjects;

    private const cSpaceBelowLevel = 80;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private ConstantForce mGravForce;
    private WindyForce mWindForce;
    private float mWindTarget;
    private const cWindChange = 80.0f;

    //for raising waterline
    private bool mRaiseWaterActive;
    private uint mDestWaterLevel;
    //GameLevel.waterLevel is uint, so we have a float version here...
    private float mCurrentLevel;

    private uint mDetailLevel;
    //not quite clean: Gui drawers can query this / detailLevel changes it
    bool enableSpiffyGui;

    //pixels per second
    private const cWaterRaisingSpeed = 50;

    //managment of sprite classes, for findSpriteClass()
    private GOSpriteClass[char[]] mSpriteClasses;
    //factory to instantiate sprite classes, this is a small wtf
    private Factory!(GOSpriteClass, GameEngine, char[]) mSpriteClassFactory;

    //same for weapons (also such a two-stage factory, which creastes Shooters)
    private WeaponClass[char[]] mWeaponClasses;
    private Factory!(WeaponClass, GameEngine, ConfigNode) mWeaponClassFactory;

    //factory for GOSpriteClasses
    //the constructor of GOSpriteClasses will call:
    //  engine.registerSpriteClass(registerName, this);
    GOSpriteClass instantiateSpriteClass(char[] name, char[] registerName) {
        return mSpriteClassFactory.instantiate(name, this, registerName);
    }

    //called by sprite.d/GOSpriteClass.this() only
    void registerSpriteClass(char[] name, GOSpriteClass sc) {
        if (findSpriteClass(name, true)) {
            assert(false);
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
        throw new Exception("sprite class " ~ name ~ " not found");
    }

    GObjectSprite createSprite(char[] name) {
        return findSpriteClass(name).createSprite();
    }

    Shooter createShooter(char[] weapon_name) {
        return findWeaponClass(weapon_name).createShooter();
    }

    //currently just worm.conf
    void loadSpriteClass(ConfigNode sprite) {
        char[] type = sprite.getStringValue("type", "notype");
        char[] name = sprite.getStringValue("name", "unnamed");
        auto res = instantiateSpriteClass(type, name);
        res.loadFromConfig(sprite);
    }

    //a weapon subnode of weapons.conf
    void loadWeaponClass(ConfigNode weapon) {
        char[] type = weapon.getStringValue("type", "notype");
        char[] name = weapon.getStringValue("name", "unnamed");
        //xxx error handling
        assert(findWeaponClass(name, true) is null);
        //hope you never need to debug this code!
        WeaponClass c = mWeaponClassFactory.instantiate(type, this, weapon);
        mWeaponClasses[name] = c;
    }

    //find a weapon class
    WeaponClass findWeaponClass(char[] name, bool canfail = false) {
        WeaponClass* w = name in mWeaponClasses;
        if (w)
            return *w;

        if (canfail)
            return null;

        //not found? xxx better error handling (as usual...)
        throw new Exception("weapon class " ~ name ~ " not found");
    }

    this(Scene gamescene, GameConfig config) {
        assert(gamescene !is null);
        assert(config.level !is null);
        scene = gamescene;
        this.level = config.level;

        mLog = registerLog("gameengine");

        mSpriteClassFactory = new typeof(mSpriteClassFactory);
        mSpriteClassFactory.register!(GOSpriteClass)("sprite_mc");
        mSpriteClassFactory.register!(WormSpriteClass)("worm_mc");
        mSpriteClassFactory.register!(projectile.ProjectileSpriteClass)("projectile_mc");

        mWeaponClassFactory = new typeof(mWeaponClassFactory);
        mWeaponClassFactory.register!(projectile.ProjectileWeapon)("projectile_mc");
        mWeaponClassFactory.register!(special_weapon.SpecialWeapon)("specialw_mc");

        mAllAnimations = new ConfigNode();

        Vector2i levelOffset, worldSize;
        if (level.isCave) {
            worldSize = Vector2i(level.width, level.height+cSpaceBelowLevel);
            levelOffset = Vector2i(0, 0);
        } else {
            worldSize = Vector2i(cOpenLevelWidthMultiplier*level.width,
                level.height+cSpaceBelowLevel+cSpaceAboveOpenLevel);
            levelOffset = Vector2i(cast(int)((cOpenLevelWidthMultiplier-1)/2.0f
                *level.width), cSpaceAboveOpenLevel);
        }

        gamelevel = new GameLevel(level, levelOffset);

        levelobject = new LevelObject(this);
        levelobject.setScene(scene, GameZOrder.Level);

        //prepare the scene
        gamescene.size = worldSize;

        physicworld = new PhysicWorld();

        //to enable level-bitmap collision
        physicworld.add(gamelevel.physics);
        //various level borders
        waterborder = new PlaneGeometry();
        physicworld.add(waterborder);

        mGravForce = new ConstantForce();
        mGravForce.accel = Vector2f(0, 100); //what unit is that???
        physicworld.add(mGravForce);

        mWindForce = new WindyForce();
        physicworld.add(mWindForce);
        mWindTarget = -150;   //what unit is that???

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        gameWater = new GameWater(this, "blue");
        gameSky = new GameSky(this);

        fixupWaterLevel();

        loadLevelStuff();

        detailLevel = 0;

        //NOTE: GameController relies on many stuff at initialization
        //i.e. physics for worm placement
        controller = new GameController(this, config);
    }

    //return y coordinate of waterline
    int waterOffset() {
        return gamelevel.offset.y + gamelevel.height-gamelevel.waterLevel;
    }

    private void fixupWaterLevel() {
        auto water_y = waterOffset;
        waterborder.define(Vector2f(0, water_y), Vector2f(1, water_y));
    }

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        loadAnimations(globals.loadConfig("stdanims"));

        //load weapons
        auto weapons = globals.loadConfig("weapons");
        loadAnimations(weapons.find("require_animations"));
        auto list = weapons.getSubNode("weapons");
        foreach (ConfigNode item; list) {
            loadWeaponClass(item);
        }

        auto conf = globals.loadConfig("game");
        //load sprites
        foreach (char[] name, char[] value; conf.getSubNode("sprites")) {
            auto sprite = globals.loadConfig(value);
            loadSpriteClass(sprite);
        }
    }

    public uint detailLevel() {
        return mDetailLevel;
    }
    //the higher the less detail (wtf), wraps around if set too high
    public void detailLevel(uint level) {
        level = level % 7;
        mDetailLevel = level;
        bool clouds = true, skyDebris = true, skyBackdrop = true, skyTex = true;
        bool water = true, gui = true;
        if (level >= 1) skyDebris = false;
        if (level >= 2) skyBackdrop = false;
        if (level >= 3) skyTex = false;
        if (level >= 4) clouds = false;
        if (level >= 5) water = false;
        if (level >= 6) gui = false;
        gameWater.simpleMode = !water;
        gameSky.enableClouds = clouds;
        gameSky.enableDebris = skyDebris;
        gameSky.enableSkyBackdrop = skyBackdrop;
        gameSky.enableSkyTex = skyTex;
        enableSpiffyGui = gui;
    }

    public float windSpeed() {
        return mWindForce.accel.x;
    }
    public void windSpeed(float speed) {
        mWindTarget = speed;
    }

    public float gravity() {
        return mGravForce.accel.y;
    }

    void raiseWater(int by) {
        if (!mRaiseWaterActive) {
            mRaiseWaterActive = true;
            mDestWaterLevel = gamelevel.waterLevel;
            mCurrentLevel = gamelevel.waterLevel;
        }
        mDestWaterLevel += by;
    }

    private void simulate(float deltaT) {
        //whatever this is?
        if (abs(mWindTarget - mWindForce.accel.x) > 0.5f) {
            mWindForce.accel.x += copysign(cWindChange*deltaT,mWindTarget - mWindForce.accel.x);
        }

        if (mRaiseWaterActive) {
            mCurrentLevel += deltaT * cWaterRaisingSpeed;
            uint current = cast(uint)mCurrentLevel;
            gamelevel.waterLevel = current;
            if (current >= mDestWaterLevel) {
                mRaiseWaterActive = false;
            }
        }

        //at least currently it's ok to update this each frame
        fixupWaterLevel();

        controller.simulate(deltaT);
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        float deltaT = (currentTime - lastTime).msecs/1000.0f;
        simulate(deltaT);
        physicworld.simulate(currentTime);
        //update game objects
        //NOTE: objects might be inserted/removed while iterating
        //      maybe one should implement a safe iterator...
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.simulate(deltaT);
        }
        lastTime = currentTime;
    }

    //remove all objects etc. from the scene
    void kill() {
        levelobject.active = false;
        foreach (GameObject o; mObjects) {
            o.kill();
        }
        controller.kill();
    }

    //try to place an object into the landscape
    //essentially finds the first collision under "drop" and checks the normal
    //success only when only the LevelGeometry object is hit
    //  drop = any startpoint
    //  dest = where it is dropped (will have same x value as drop)
    //returns if dest contains a useful value
    bool placeObject(Vector2f drop, float y_max, out Vector2f dest,
        float radius)
    {
        Vector2f pos = drop;
        bool isfirst = true;
        while (!physicworld.collideGeometry(drop, radius)) {
            pos = drop;
            //hmpf!
            drop.y += 1;
            if (drop.y > y_max)
                return false;
            isfirst = false;
        }
        if (isfirst) //don't place inside landscape
            return false;
        //had a collision, check normal
        Vector2f normal = (drop-pos).normal;
        float dist = abs(angleDistance(normal.toAngle(), 90.0f/180*PI));
        //if (dist < 20.0f/180*PI) { always is true or so, for unkown reasons
        if (true) {
            dest = pos;
            return true;
        } else {
            return false;
        }
    }

    //places an object at a random (x,y)-position, where y <= y_max
    //use y_max to prevent placement under the water, or to start dopping from
    //the sky (instead of anywhere)
    //  retrycount = times it tries again until it gives up
    bool placeObject(float y_max, int retrycount, out Vector2f drop,
        out Vector2f dest, float radius)
    {
        //clip y_max to level borders
        y_max = max(y_max, 1.0f*gamelevel.offset.y);
        y_max = min(y_max, 1.0f*gamelevel.offset.y + gamelevel.height);
        for (;retrycount > 0; retrycount--) {
            drop.y = randRange(1.0f*gamelevel.offset.y, y_max);
            drop.x = gamelevel.offset.x + randRange(0u, gamelevel.width);
            if (placeObject(drop, y_max, dest, radius))
                return true;
        }
        return false;
    }

    //load animations as requested in "item"
    //currently, item shall be a ConfigValue which contains the configfile name
    //note that this name shouldn't contain a ".conf", argh.
    //also can be an animation configfile directly
    void loadAnimations(ConfigItem item) {
        if (!item)
            return;

        ConfigNode cfg;

        auto v = cast(ConfigValue)item;
        if (v) {
            char[] file = v.value;
            if (file in mLoadedAnimationConfigFiles)
                return;

            mLoadedAnimationConfigFiles[file] = true;
            cfg = globals.loadConfig(file);
        } else if (cast(ConfigNode)item) {
            cfg = cast(ConfigNode)item;
        } else {
            assert(false);
        }

        assert(cfg !is null);

        auto load_further = cfg.find("require_animations");
        if (load_further !is null) {
            //xxx: should try to prevent possible recursion
            loadAnimations(load_further);
        }

        //load new introduced animations (not really load them themselves...)
        mAllAnimations.mixinNode(cfg.getSubNode("animations"), false);

        //add aliases
        foreach (char[] name, char[] value;
            cfg.getSubNode("animation_aliases"))
        {
            ConfigNode aliased = mAllAnimations.findNode(value);
            if (!aliased) {
                mLog("WARNING: alias '%s' not found", value);
                continue;
            }
            if (mAllAnimations.findNode(name)) {
                mLog("WARNING: alias target '%s' already exists", name);
                continue;
            }
            //um, this sucks... but seems to work... strange world
            mAllAnimations.getSubNode(name).mixinNode(aliased);
            //possibly copy already loaded Animation
            Animation* ani = value in mAllLoadedAnimations;
            if (ani) {
                mAllLoadedAnimations[name] = *ani;
            }
        }
    }

    //get an animation or, if not loaded yet, actually load the animation
    Animation findAnimation(char[] name) {
        Animation* ani = name in mAllLoadedAnimations;
        if (ani)
            return *ani;
        //actually load
        ConfigNode n = mAllAnimations.findNode(name);
        if (!n) {
            mLog("WARNING: animation '%s' not found", name);
            return null;
        }
        auto nani = new Animation(n);
        mAllLoadedAnimations[name] = nani;
        return nani;
    }

    //find a collision ID by name
    //  doregister = if true, register on not-exist, else throw exception
    CollisionType findCollisionID(char[] name, bool doregister = false) {
        if (name in mCollisionTypeNames)
            return mCollisionTypeNames[name];

        if (!doregister) {
            mLog("WARNING: collision name '%s' not found", name);
            throw new Exception("mooh");
        }

        auto nt = physicworld.newCollisionType();
        mCollisionTypeNames[name] = nt;
        return nt;
    }

    //"collisions" node from i.e. worm.conf
    void loadCollisions(ConfigNode node) {
        //list of collision IDs, which map to...
        foreach (ConfigNode sub; node) {
            CollisionType obj_a = findCollisionID(sub.name, true);
            //... a list of "collision ID" -> "action" pairs
            foreach (char[] name, char[] value; sub) {
                //NOTE: action is currently unused
                //      should map to a cookie value, which is 1 for now
                CollisionType obj_b = findCollisionID(name, true);
                physicworld.setCollide(obj_a, obj_b, 1);
            }
        }
    }

    void explosionAt(Vector2f pos, float damage) {
        gamelevel.damage(toVector2i(pos), cast(int)damage);
        auto expl = new ExplosiveForce();
        expl.impulse = 40.0f*damage;
        expl.radius = 4.0f*damage;
        expl.pos = pos;
        physicworld.add(expl);
    }
}

class LevelObject : SceneObject {
    GameEngine game;
    GameLevel gamelevel;
    Texture levelTexture;

    void draw(Canvas c, SceneView parentView) {
        if (!levelTexture) {
            levelTexture = gamelevel.image.createTexture();
            levelTexture.setCaching(false);
        }
        c.draw(levelTexture, gamelevel.offset);
        /+
        //debug code to test collision detection
        Vector2i dir; int pixelcount;
        auto pos = game.tmp;
        auto npos = toVector2f(pos);
        auto testr = 10;
        if (gamelevel.physics.collide(npos, testr)) {
            c.drawCircle(pos, testr, Color(0,1,0));
            c.drawCircle(toVector2i(npos), testr, Color(1,1,0));
        }
        +/
        //xxx draw debug stuff for physics!
        foreach (PhysicObject o; game.physicworld.mObjects) {
            //auto angle = o.rotation;
            auto angle2 = o.ground_angle;
            auto angle = o.lookey;
            c.drawCircle(toVector2i(o.pos), cast(int)o.posp.radius, Color(1,1,1));
            auto p = Vector2f.fromPolar(40, angle) + o.pos;
            c.drawCircle(toVector2i(p), 5, Color(1,1,0));
            p = Vector2f.fromPolar(50, angle2) + o.pos;
            c.drawCircle(toVector2i(p), 5, Color(1,0,1));
        }
        //more debug stuff...
        foreach (GameObject go; game.mObjects) {
            /+if (cast(Worm)go) {
                auto w = cast(Worm)go;
                auto p = Vector2f.fromPolar(40, w.angle) + w.physics.pos;
                c.drawCircle(toVector2i(p), 5, Color(1,0,1));
            }+/
        }
    }

    this(GameEngine game) {
        this.game = game;
        gamelevel = game.gamelevel;
    }
}
