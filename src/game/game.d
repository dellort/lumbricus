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
    FrontLowerWater,  //water before the level
    Objects,
    Names, //controller.d/WormNameDrawer
    FrontUpperWater,
    FrontWaterWaves1,
    FrontWaterWaves2,
    FrontWaterWaves3,
}

struct GameConfig {
    Level level;
    ConfigNode teams;
    ConfigNode weapons;
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine : GameObjectHandler {
    Level level;
    LevelObject levelobject;
    GameLevel gamelevel;
    Scene scene;
    PhysicWorld physicworld;
    PlaneTrigger waterborder;
    PlaneTrigger deathzone;
    Time lastTime;
    Time currentTime;

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

    private const cSpaceBelowLevel = 150;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private ConstantForce mGravForce;
    private WindyForce mWindForce;
    private PhysicTimedChangerFloat mWindChanger;
    private const cWindChange = 80.0f;

    //for raising waterline
    private PhysicTimedChangerFloat mWaterChanger;
    private const cWaterRaisingSpeed = 50.0f; //pixels per second
    //current water level, now in absolute scene coordinates, no more dupes
    private float mCurrentWaterLevel;


    //managment of sprite classes, for findSpriteClass()
    private GOSpriteClass[char[]] mSpriteClasses;

    //same for weapons (also such a two-stage factory, which creastes Shooters)
    private WeaponClass[char[]] mWeaponClasses;

    void activate(GameObject obj) {
        mObjects.insert_tail(obj);
    }

    void deactivate(GameObject obj) {
        mObjects.remove(obj);
    }

    //factory for GOSpriteClasses
    //the constructor of GOSpriteClasses will call:
    //  engine.registerSpriteClass(registerName, this);
    GOSpriteClass instantiateSpriteClass(char[] name, char[] registerName) {
        return gSpriteClassFactory.instantiate(name, this, this, registerName);
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
        //xxx error handling
        //hope you never need to debug this code!
        WeaponClass c = gWeaponClassFactory.instantiate(type, this, this, weapon);
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
        throw new Exception("weapon class " ~ name ~ " not found");
    }

    void windChangerUpdate(float val) {
        mWindForce.accel = Vector2f(val,0);
    }

    private void waterChangerUpdate(float val) {
        mCurrentWaterLevel = val;
        waterborder.plane.define(Vector2f(0, val), Vector2f(1, val));
    }

    this(GameConfig config) {
        assert(config.level !is null);
        this.level = config.level;

        mLog = registerLog("gameengine");

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

        //prepare the scene
        scene = new Scene();
        scene.size = worldSize;

        gamelevel = new GameLevel(level, levelOffset);

        levelobject = new LevelObject(this);
        levelobject.setScene(scene, GameZOrder.Level);

        physicworld = new PhysicWorld();

        //to enable level-bitmap collision
        physicworld.add(gamelevel.physics);
        //various level borders
        waterborder = new PlaneTrigger();
        waterborder.id = "waterplane";
        physicworld.add(waterborder);

        deathzone = new PlaneTrigger();
        deathzone.id = "deathzone";
        //xxx: at least as high as highest object in the game
        //     else objects will disappear too early
        auto death_y = worldSize.y + 30;
        deathzone.plane.define(Vector2f(0, death_y), Vector2f(1, death_y));
        physicworld.add(deathzone);

        mGravForce = new ConstantForce();
        physicworld.add(mGravForce);

        mWindForce = new WindyForce();
        mWindChanger = new PhysicTimedChangerFloat(0, &windChangerUpdate);
        mWindChanger.changePerSec = cWindChange;
        physicworld.add(mWindForce);
        physicworld.addBaseObject(mWindChanger);
        //xxx make this configurable or initialize randomly
        windSpeed = -150;   //what unit is that???

        //physics timed changer for water offset
        mWaterChanger = new PhysicTimedChangerFloat(gamelevel.offset.y
            + gamelevel.height - gamelevel.waterLevelInit, &waterChangerUpdate);
        mWaterChanger.changePerSec = cWaterRaisingSpeed;
        physicworld.addBaseObject(mWaterChanger);

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        loadLevelStuff();

        //NOTE: GameController relies on many stuff at initialization
        //i.e. physics for worm placement
        controller = new GameController(this, config);
    }

    //return y coordinate of waterline
    int waterOffset() {
        return cast(int)mCurrentWaterLevel;
    }

    //return skyline offset (used by airstrikes)
    float skyline() {
        return gamelevel.offset.y;
    }

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        globals.resources.loadAnimations(globals.loadConfig("stdanims"));

        //load weapons
        auto weapons = globals.loadConfig("weapons");
        globals.resources.loadAnimations(weapons.find("require_animations"));
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

        mGravForce.accel = Vector2f(0, conf.getFloatValue("gravity",100));

        //load all animations
        //xxx this would load all those worms animations, think of something
        //globals.resources.preloadAll();
    }

    public float windSpeed() {
        return mWindForce.accel.x;
    }
    public void windSpeed(float speed) {
        mWindChanger.target = speed;
    }

    public float gravity() {
        return mGravForce.accel.y;
    }

    void raiseWater(int by) {
        mWaterChanger.target = mCurrentWaterLevel - by;
    }

    private void simulate(float deltaT) {
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
        //must iterate savely
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
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
        auto expl = new ExplosiveForce();
        expl.damage = damage;
        expl.pos = pos;
        gamelevel.damage(toVector2i(pos), cast(int)(expl.radius/2.0f));
        physicworld.add(expl);
    }
}

class LevelObject : SceneObject {
    GameEngine game;
    GameLevel gamelevel;
    Texture levelTexture;

    void draw(Canvas c) {
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
