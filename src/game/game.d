module game.game;
import game.levelgen.level;
import game.animation;
import game.gobject;
import physics.world;
import game.gfxset;
import game.glevel;
import game.sprite;
import game.water;
import game.sky;
//import game.scene;
import common.common;
import game.controller;
import game.weapon.weapon;
import game.gamepublic;
import game.sequence;
import utils.list2;
import utils.time;
import utils.log;
import utils.configfile;
import utils.math;
import utils.misc;
import utils.perf;
import utils.random;
import utils.reflection;
import framework.framework;
import framework.keysyms;
import framework.timesource;
import framework.resset;
import std.math;

import game.levelgen.renderer;// : LandscapeBitmap;

import game.worm;
import game.crate;

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine : GameEnginePublic, GameEngineAdmin {
    private TimeSource mGameTime;

    protected PhysicWorld mPhysicWorld;
    private List2!(GameObject) mObjects;
    private Level mLevel;
    GameLandscape[] gameLandscapes;
    PhysicZonePlane waterborder;
    PhysicZonePlane deathzone;

    GfxSet gfx;

    GameEngineGraphics graphics;

    Random rnd;

    Level level() {
        return mLevel;
    }

    GameLandscape[] getGameLandscapes() {
        return gameLandscapes;
    }

    private Vector2i mWorldSize;

    private GameController mController;

    //Part of interface GameEnginePublic
    GameLogicPublic logic() {
        return mController;
    }

    //Direct server-side access to controller
    //NOT part of GameEnginePublic
    GameController controller() {
        return mController;
    }

    Vector2i worldSize() {
        return mWorldSize;
    }
    Vector2i worldCenter() {
        return mLevel.worldCenter;
    }

    GameEngineAdmin requestAdmin() {
        return this;
    }

    bool paused() {
        return mGameTime.paused;
    }
    void setPaused(bool p) {
        mGameTime.paused = p;
    }

    float slowDown() {
        return mGameTime.slowDown;
    }
    void setSlowDown(float s) {
        mGameTime.slowDown = s;
    }

    public Log mLog;
    //private PerfTimer mPhysicTime;

    private const cSpaceBelowLevel = 150;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private WindyForce mWindForce;
    private PhysicTimedChangerFloat mWindChanger;
    private const cWindChange = 80.0f;

    //for raising waterline
    private PhysicTimedChangerFloat mWaterChanger;
    private const cWaterRaisingSpeed = 50.0f; //pixels per second
    //current water level, now in absolute scene coordinates, no more dupes
    private float mCurrentWaterLevel;

    //generates earthquakes
    private EarthQuakeForce mEarthQuakeForce;


    //managment of sprite classes, for findSpriteClass()
    private GOSpriteClass[char[]] mSpriteClasses;

    //same for weapons (also such a two-stage factory, which creastes Shooters)
    private WeaponClass[char[]] mWeaponClasses;

    SequenceStateList sequenceStates;

    this (ReflectCtor c) {
        auto t = c.types();
        t.registerClass!(typeof(mObjects));
        t.registerMethod(this, &deathzoneTrigger, "deathzoneTrigger");
        t.registerMethod(this, &underWaterTrigger, "underWaterTrigger");
        t.registerMethod(this, &windChangerUpdate, "windChangerUpdate");
        t.registerMethod(this, &waterChangerUpdate, "waterChangerUpdate");
        t.registerMethod(this, &onPhysicHit, "onPhysicHit");
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
        throw new Exception("sprite class " ~ name ~ " not found");
    }

    GObjectSprite createSprite(char[] name) {
        return findSpriteClass(name).createSprite();
    }

    Shooter createShooter(char[] weapon_name, GObjectSprite owner) {
        return findWeaponClass(weapon_name).createShooter(owner);
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
        auto set_conf = gFramework.loadConfig(dir~"/set");
        auto coll_conf = gFramework.loadConfig(dir ~ "/"
            ~ set_conf.getStringValue("collisions","collisions.conf"),true,true);
        if (coll_conf)
            physicworld.collide.loadCollisions(coll_conf.getSubNode("collisions"));
        //load all .conf files found
        char[] weaponsdir = dir ~ "/weapons";
        gFramework.fs.listdir(weaponsdir, "*.conf", false,
            (char[] path) {
                //a weapons file can contain resources, collision map
                //additions and a list of weapons
                auto wp_conf = gFramework.loadConfig(weaponsdir ~ "/"
                    ~ path[0..$-5]);
                physicworld.collide.loadCollisions(wp_conf.getSubNode("collisions"));
                auto list = wp_conf.getSubNode("weapons");
                foreach (ConfigNode item; list) {
                    loadWeaponClass(item);
                }
                return true;
            }
        );
    }

    //a weapon subnode of weapons.conf
    void loadWeaponClass(ConfigNode weapon) {
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
        throw new Exception("weapon class " ~ name ~ " not found");
    }

    WeaponClass[] weaponList() {
        return mWeaponClasses.values;
    }

    void windChangerUpdate(float val) {
        mWindForce.windSpeed = Vector2f(val,0);
    }

    private void waterChangerUpdate(float val) {
        mCurrentWaterLevel = val;
        waterborder.plane.define(Vector2f(0, val), Vector2f(1, val));
    }

    this(GameConfig config, GfxSet a_gfx) {
        rnd = new Random();
        //xxx
        rnd.seed(1);
        gfx = a_gfx;

        assert(config.level !is null);
        mLevel = config.level;

        mLog = registerLog("gameengine");
        //mPhysicTime = globals.newTimer("game_physic");

        mGameTime = new TimeSource();
        mGameTime.paused = true;

        graphics = new GameEngineGraphics(mGameTime);

        mObjects = new List2!(GameObject)();
        mPhysicWorld = new PhysicWorld(rnd);

        mWorldSize = mLevel.worldSize;

        foreach (o; level.objects) {
            if (auto ls = cast(LevelLandscape)o) {
                //xxx landscapes should keep track of themselves
                gameLandscapes ~= new GameLandscape(this, ls);
            }
        }

        //various level borders
        waterborder = new PhysicZonePlane();
        auto wb = new ZoneTrigger(waterborder);
        wb.onTrigger = &underWaterTrigger;
        wb.collision = physicworld.collide.findCollisionID("water");
        physicworld.add(wb);
        //Stokes's drag force
        physicworld.add(new ForceZone(new StokesDragFixed(5.0f), waterborder));
        //xxx additional object-attribute controlled Stokes's drag
        physicworld.add(new StokesDragObject());
        //Earthquake generator
        mEarthQuakeForce = new EarthQuakeForce();
        physicworld.add(mEarthQuakeForce);

        deathzone = new PhysicZonePlane();
        auto dz = new ZoneTrigger(deathzone);
        dz.collision = physicworld.collide.collideAlways();
        dz.onTrigger = &deathzoneTrigger;
        dz.inverse = true;
        //the trigger is inverse, and triggers only when the physic object is
        //completely in the deathzone, but graphics are often larger :(
        auto death_y = worldSize.y + 20;
        //because trigger is inverse, the plane must be defined inverted too
        deathzone.plane.define(Vector2f(1, death_y), Vector2f(0, death_y));
        physicworld.add(dz);

        mWindForce = new WindyForce();
        mWindChanger = new PhysicTimedChangerFloat(0, &windChangerUpdate);
        mWindChanger.changePerSec = cWindChange;
        physicworld.add(new ForceZone(mWindForce, waterborder, true));
        physicworld.add(mWindChanger);
        //xxx make this configurable or initialize randomly
        setWindSpeed(-150);   //what unit is that???

        //physics timed changer for water offset
        mWaterChanger = new PhysicTimedChangerFloat(mLevel.waterBottomY,
            &waterChangerUpdate);
        mWaterChanger.changePerSec = cWaterRaisingSpeed;
        physicworld.add(mWaterChanger);

        sequenceStates = new SequenceStateList();

        //load sequences
        foreach (ConfigNode node; gfx.sequenceConfig) {
            loadSequences(this, node);
        }

        //load weapons
        foreach (char[] ws; config.weaponsets) {
            loadWeapons("weapons/"~ws);
        }

        loadLevelStuff();

        //NOTE: GameController relies on many stuff at initialization
        //i.e. physics for worm placement
        mController = new GameController(this, config);
    }

    //landscape bitmaps need special handling in many cases
    //xxx: need somehow to be identified
    LandscapeBitmap[] landscapeBitmaps() {
        LandscapeBitmap[] res;
        foreach (x; gameLandscapes) {
            res ~= x.landscape_bitmap();
        }
        return res;
    }

    //actually start the game (called after resources were preloaded)
    void start() {
        mGameTime.paused = false;
    }

    GameEngineGraphics getGraphics() {
        return graphics;
    }

    TimeSource gameTime() {
        return mGameTime;
    }

    //return y coordinate of waterline
    int waterOffset() {
        return cast(int)mCurrentWaterLevel;
    }

    float earthQuakeStrength() {
        return mEarthQuakeForce.earthQuakeStrength();
    }

    //return skyline offset (used by airstrikes)
    float skyline() {
        return level.airstrikeY;
    }

    bool allowAirstrikes() {
        return level.airstrikeAllow;
    }

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        auto conf = gFramework.loadConfig("game");
        //load sprites
        foreach (char[] name, char[] value; conf.getSubNode("sprites")) {
            auto sprite = gFramework.loadConfig(value);
            loadSpriteClass(sprite);
        }

        mPhysicWorld.gravity = Vector2f(0, conf.getFloatValue("gravity",100));

        //hm!?!?
        mPhysicWorld.collide.setCollideHandler(&onPhysicHit);

        //error when a reference to a collision type is missing
        mPhysicWorld.collide.checkCollisionHandlers();
    }

    //called when a and b touch in physics
    private void onPhysicHit(ref Contact c) {
        if (c.source == ContactSource.generator)
            return;
        //exactly as the old behaviour
        auto xa = cast(GObjectSprite)(c.obj[0].backlink);
        if (xa) xa.doImpact(c.obj[1], c.normal);
        if (c.obj[1]) {
            auto xb = cast(GObjectSprite)(c.obj[1].backlink);
            if (xb) xb.doImpact(c.obj[0], -c.normal);
        }
    }

    private void underWaterTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(GObjectSprite)(other.backlink);
        if (x) x.isUnderWater();
    }

    private void deathzoneTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(GObjectSprite)(other.backlink);
        if (x) x.exterminate();
    }

    public float windSpeed() {
        return mWindForce.windSpeed.x;
    }
    public void setWindSpeed(float speed) {
        mWindChanger.target = speed;
    }

    public float gravity() {
        return mPhysicWorld.gravity.y;
    }

    void raiseWater(int by) {
        //argh why is mCurrentWaterLevel a float??
        int t = cast(int)mCurrentWaterLevel - by;
        t = max(t, mLevel.waterTopY); //don't grow beyond limit?
        mWaterChanger.target = t;
    }

    EarthQuakeForce earthQuakeForce() {
        return mEarthQuakeForce;
    }

    //strength = force, degrade = multiplier applied all the time after a
    //  physics.cEarthQuakeDegradeInterval
    //this function never overwrites the settings, but adds both values to the
    //existing ones
    void addEarthQuake(float strength, float degrade) {
        physicworld.add(new EarthQuakeDegrader(strength, degrade,
            mEarthQuakeForce));
        mLog("created earth quake, strength=%s, degrade=%s", strength, degrade);
    }

    void ensureAdded(GameObject obj) {
        assert(obj.active);
        //in case of lazy removal
        //note that .contains is O(1) if used with .node
        if (!mObjects.contains(obj.node))
            obj.node = mObjects.add(obj);
    }

    PhysicWorld physicworld() {
        return mPhysicWorld;
    }

    protected void simulate() {
        mController.simulate();
    }

    void doFrame() {
        mGameTime.update();

        if (!mGameTime.paused) {
            //mPhysicTime.start();
            mPhysicWorld.simulate(mGameTime.current);
            //mPhysicTime.stop();
            simulate();
            //update game objects
            //NOTE: objects might be inserted/removed while iterating
            //      List.opApply can deal with that
            float deltat = mGameTime.difference.secsf;
            foreach (GameObject o; mObjects) {
                if (o.active) {
                    o.simulate(deltat);
                } else {
                    //remove (it's done lazily, and here it's actually removed)
                    mObjects.remove(o.node);
                }
            }
        }
    }

    //remove all objects etc. from the scene
    void kill() {
        //must iterate savely
        foreach (GameObject o; mObjects) {
            o.kill();
        }
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
        GeomContact contact;   //data not needed
        while (!physicworld.collideGeometry(drop, radius, contact)) {
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
        //xxx this should probably cooperate with the physics, which has methods
        //  for this anyway (remember the ray weapons)
        //  this means you'd enumerate static level objects, check if it's
        //  suitable for worms, select a random position, and then cast a ray to
        //  downwards find a position where a worm/mine can stand
        //but for now, I'm too lazy, so here is some ugly hack, have fun
        foreach (gl; gameLandscapes) {
            //clip y_max to level borders
            y_max = max(y_max, 1.0f*gl.offset.y);
            y_max = min(y_max, 1.0f*gl.offset.y + gl.size.y);
            for (;retrycount > 0; retrycount--) {
                drop.y = rnd.nextRange(1.0f*gl.offset.y, y_max);
                drop.x = gl.offset.x + rnd.nextRange(0, gl.size.x);
                if (placeObject(drop, y_max, dest, radius))
                    return true;
            }
        }
        return false;
    }

    //hack
    //sry!
    private void onDamage(Object cause, Object victim, float damage) {
        auto a = cast(GameObject)cause;
        auto b = cast(GameObject)victim;
        if (!a || !b) {
            mLog("WARNING: unknown damage: %s %s %s", cause, victim, damage);
        } else {
            mController.reportViolence(a, b, damage);
        }
    }

    void explosionAt(Vector2f pos, float damage, GameObject cause) {
        auto expl = new ExplosiveForce();
        expl.damage = damage;
        expl.pos = pos;
        expl.onReportApply = &onDamage;
        expl.cause = cause;
        damageLandscape(toVector2i(pos), cast(int)(expl.radius/2.0f));
        physicworld.add(expl);
        graphics.createExplosionGfx(toVector2i(pos), cast(int)expl.radius);
        //some more chaos, if strong enough
        //xxx needs moar tweaking
        //if (damage > 50)
        //    addEarthQuake(damage, 0.5);
    }

    //destroy a circular area of the damageable landscape
    void damageLandscape(Vector2i pos, int radius) {
        foreach (ls; gameLandscapes) {
            ls.damage(pos, radius);
        }
    }

    //insert bitmap into the landscape
    //(bitmap is a Resource for the network mode, if we'll ever have one)
    void insertIntoLandscape(Vector2i pos, Resource!(Surface) bitmap) {
        Rect2i[] covered;
        foreach (ls; gameLandscapes) {
            covered ~= Rect2i.Span(ls.offset(), ls.size());
        }
        //this is if the objects is inserted so that the landscape doesn't cover
        //it fully - possibly create new landscapes to overcome this yay
        Rect2i[] uncovered
            = Rect2i.Span(pos, bitmap.get.size).substractRects(covered);
        foreach (rc; uncovered) {
            assert(rc.size().x > 0 && rc.size().y > 0);
            gameLandscapes ~= new GameLandscape(this, rc);
        }
        //really insert
        foreach (ls; gameLandscapes) {
            ls.insert(pos, bitmap);
        }
    }

    //determine round-active objects
    //just another loop over all GameObjects :(
    bool checkForActivity() {
        bool quake = earthQuakeStrength() > 0;
        if (quake)
            return true;
        foreach (GameObject o; mObjects) {
            if (o.activity)
                return true;
        }
        return false;
    }

    void activityDebug(bool all = false) {
        mLog("-- Active game objects:");
        int i;
        foreach (GameObject o; mObjects) {
            char[] sa = "Dormant ";
            if (o.activity) {
                sa = "Active ";
                i++;
            } else {
                if (!all) continue;
            }
            if (cast(GObjectSprite)o) {
                mLog("%s%s at %s in state %s", sa, o.toString(),
                    (cast(GObjectSprite)o).physics.pos,
                    (cast(GObjectSprite)o).currentState.name);
            } else {
                mLog("%s%s", sa, o.toString());
            }
        }
        mLog("-- %s objects reporting activity",i);
    }
}
