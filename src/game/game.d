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
import tango.math.Math;

import game.levelgen.renderer;// : LandscapeBitmap;

import game.worm;
import game.crate;

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine : GameEnginePublic {
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

    GameConfig gameConfig;

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

    private static LogStruct!("game.game") log;
    //private PerfTimer mPhysicTime;

    private const cSpaceBelowLevel = 150;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private WindyForce mWindForce;
    private PhysicTimedChangerFloat mWindChanger;
    private const cWindChange = 80.0f;
    private const cMaxWind = 150f;

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
        t.registerMethod(this, &onDamage, "onDamage");
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

    //sry
    WeaponHandle findWeaponHandle(char[] name) {
        auto wc = findWeaponClass(name, true);
        //logic error, don't call this function if the name doesn't exist
        assert (!!wc, "no weapon handle: "~name);
        assert (!!wc.handle);
        return wc.handle;
    }
    WeaponHandle wc2wh(WeaponClass c) {
        return c ? findWeaponHandle(c.name) : null;
    }
    WeaponClass wh2wc(WeaponHandle h) {
        return h ? findWeaponClass(h.name) : null;
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
        gameConfig = config;

        assert(config.level !is null);
        mLevel = config.level;

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
        randomizeWind();

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

    //wind speeds are in [-1.0, 1.0]
    public float windSpeed() {
        return mWindForce.windSpeed.x/cMaxWind;
    }
    public void setWindSpeed(float speed) {
        mWindChanger.target = clampRangeC(speed, -1.0f, 1.0f)*cMaxWind;
    }
    public void randomizeWind() {
        mWindChanger.target = cMaxWind*rnd.nextDouble3();
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
        log("created earth quake, strength={}, degrade={}", strength, degrade);
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
            graphics.current_frame++;
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

    Rect2f getLandscapeArea(bool forPlace = true) {
        Rect2f landArea = Rect2f(toVector2f(worldSize)/2,
            toVector2f(worldSize)/2);
        if (gameLandscapes.length > 0)
            landArea = Rect2f(toVector2f(gameLandscapes[0].offset),
                toVector2f(gameLandscapes[0].offset));
        foreach (gl; gameLandscapes) {
            landArea.extend(toVector2f(gl.offset));
            landArea.extend(toVector2f(gl.offset + gl.size));
        }
        if (forPlace)
            //add some space at the top for object placement
            landArea.p1.y = max(landArea.p1.y - 50f, 0);
        return landArea;
    }

    //minimum distance between placed objects
    private const cMinDistance = 50.0f;
    //position increment for deterministic placement
    private const cIncDistance = 55.0f;
    //distance when creating a platform in empty space
    private const cPlatformDistance = 90.0f;

    //try to place an object into the landscape
    //essentially finds the first collision under "drop", then checks the
    //normal and distance to other objects
    //success only when only the LevelGeometry object is hit
    //  drop = any startpoint
    //  dest = where it is dropped (will have same x value as drop)
    //  inAir = true to place exactly at drop and create a hole/platform
    //returns if dest contains a useful value
    bool placeObject(Vector2f drop, float y_max, float radius,
        out Vector2f dest, bool inAir = false)
    {
        Rect2f area = Rect2f(0, 0, worldSize.x, y_max);
        area.fitInside(getLandscapeArea());
        if (!area.isInside(drop))
            return false;

        Vector2f pos = drop;
        if (inAir) {
            int holeRadius = cast(int)cPlatformDistance/2;

            //don't place half the platform outside the level area
            area.extendBorder(Vector2f(-holeRadius, -holeRadius));
            if (!area.isInside(pos))
                return false;

            //check distance to other sprites
            foreach (GameObject o; mObjects) {
                auto s = cast(GObjectSprite)o;
                if (s) {
                    if ((s.physics.pos - pos).length < cPlatformDistance+10f)
                        return false;
                }
            }

            //checks ok, remove land and create platform
            damageLandscape(toVector2i(pos), holeRadius);
            //xxx: can't access level theme resources here
            auto res = gfx.resources.resource!(Surface)("place_platform");
            Surface bmp = res.get();
            insertIntoLandscape(Vector2i(cast(int)pos.x-bmp.size.x/2,
                cast(int)pos.y+bmp.size.y/2), res);
            dest = pos;
            return true;
        } else {
            GeomContact contact;
            //cast a ray downwards from drop
            if (!physicworld.thickRay(drop, Vector2f(0, 1), y_max - drop.y,
                radius, pos, contact))
            {
                return false;
            }
            if (contact.depth == float.infinity)
                //most likely, drop was inside the landscape
                return false;
            //had a collision, check normal
            if (contact.normal.y < 0
                && abs(contact.normal.x) < -contact.normal.y)
            {
                //check distance to other sprites
                foreach (GameObject o; mObjects) {
                    auto s = cast(GObjectSprite)o;
                    if (s) {
                        if ((s.physics.pos - pos).length < cMinDistance)
                            return false;
                    }
                }
                dest = pos;
                return true;
            } else {
                return false;
            }
        }
    }

    //place an object deterministically on the landscape
    //checks a position grid with shrinking cell size for a successful placement
    //returns the first free position found
    bool placeOnLandscapeDet(float y_max, float radius, out Vector2f drop,
        out Vector2f dest)
    {
        //get placement area (landscape area)
        Rect2f area = Rect2f(0, 0, worldSize.x, y_max);
        area.fitInside(getLandscapeArea());

        //multiplier (controls grid size)
        int multiplier = 16;

        while (multiplier > 0) {
            float xx = cIncDistance * multiplier;
            float x = area.p1.x + realmod(xx, area.size.x);
            float y = area.p1.y + max((multiplier-1)/4, 0)*cIncDistance;
            while (y < area.p2.y) {
                drop.x = x;
                drop.y = y;
                if (placeObject(drop, area.p2.y, radius, dest))
                    return true;
                x += cIncDistance * multiplier;
                if (x > area.p2.x) {
                    y += cIncDistance * max(multiplier/4, 1);
                    x = x - area.size.x;
                }
            }
            multiplier /= 2;
        }
        return false;
    }

    //places an object at a random (x,y)-position, where y <= y_max
    //use y_max to prevent placement under the water, or to start dopping from
    //the sky (instead of anywhere)
    //  retrycount = times it tries again until it gives up
    //  inAir = true to create a platform instead of searching for landscape
    bool placeObjectRandom(float y_max, float radius, int retrycount,
        out Vector2f drop, out Vector2f dest, bool inAir = false)
    {
        Rect2f area = Rect2f(0, 0, worldSize.x, y_max);
        area.fitInside(getLandscapeArea());
        for (;retrycount > 0; retrycount--) {
            drop.x = rnd.nextRange(area.p1.x, area.p2.x);
            drop.y = rnd.nextRange(area.p1.y, area.p2.y);
            if (placeObject(drop, area.p2.y, radius, dest, inAir))
                return true;
        }
        return false;
    }

    //Queued placing:
    //as placeObjectDet always returns the same positions for the same call
    //order, use queuePlaceOnLandscape() to add all sprites to the queue,
    //then call finishPlace() to randomize the queue and place them all
    GObjectSprite[] mPlaceQueue;

    void queuePlaceOnLandscape(GObjectSprite sprite) {
        mPlaceQueue ~= sprite;
    }
    void finishPlace() {
        //randomize place queue
        for (int i = 0; i < mPlaceQueue.length; i++) {
            GObjectSprite tmp;
            int idx = rnd.next(0, mPlaceQueue.length);
            tmp = mPlaceQueue[idx];
            mPlaceQueue[idx] = mPlaceQueue[i];
            mPlaceQueue[i] = tmp;
        }

        foreach (GObjectSprite sprite; mPlaceQueue) {
            Vector2f npos, tmp;
            //first 10: minimum distance from water
            //second 10: retry count
            if (!placeOnLandscapeDet(waterOffset-10, sprite.physics.posp.radius,
                tmp, npos))
            {
                //placement unsuccessful
                //create a platform at a random position
                if (placeObjectRandom(waterOffset-10,
                    sprite.physics.posp.radius, 50, tmp, npos, true))
                {
                    log("placing '{}' in air!", sprite);
                } else {
                    log("couldn't place '{}'!", sprite);
                    //xxx
                    npos = toVector2f(worldSize)/2;
                }
            }
            log("placed '{}' at {}", sprite, npos);
            sprite.setPos(npos);
            sprite.active = true;
        }
        mPlaceQueue = null;
    }


    //hack
    //sry!
    private void onDamage(Object cause, Object victim, float damage) {
        auto a = cast(GameObject)cause;
        auto b = cast(GameObject)victim;
        if (!a || !b) {
            log("WARNING: unknown damage: {} {} {}", cause, victim, damage);
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

    //count game objects of type T currently in the game
    int countObjects(T)() {
        int ret = 0;
        foreach (GameObject o; mObjects) {
            if (cast(T)o)
                ret++;
        }
        return ret;
    }

    //count sprites with passed spriteclass name currently in the game
    int countSprites(char[] name) {
        auto sc = findSpriteClass(name, true);
        if (!sc)
            return 0;
        int ret = 0;
        foreach (GameObject o; mObjects) {
            auto s = cast(GObjectSprite)o;
            if (s) {
                if (s.type == sc)
                    ret++;
            }
        }
        return ret;
    }

    void activityDebug(char[] mode = "") {
        bool all = (mode == "all");
        bool fix = (mode == "fix");
        log("-- Active game objects:");
        int i;
        foreach (GameObject o; mObjects) {
            char[] sa = "Dormant ";
            if (o.activity) {
                sa = "Active ";
                i++;
                if (fix) {
                    sa = "Killed active ";
                    auto s = cast(GObjectSprite)(o);
                    if (s)
                        s.exterminate();
                    o.kill();
                }
            } else {
                if (!all) continue;
            }
            if (cast(GObjectSprite)o) {
                log("{}{} at {} in state {}", sa, o.toString(),
                    (cast(GObjectSprite)o).physics.pos,
                    (cast(GObjectSprite)o).currentState.name);
            } else {
                log("{}{}", sa, o.toString());
            }
        }
        log("-- {} objects reporting activity",i);
    }
}
