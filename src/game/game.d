module game.game;
import levelgen.level;
import game.animation;
import game.gobject;
import physics.world;
import game.glevel;
import game.sprite;
import game.water;
import game.sky;
//import game.scene;
import common.common;
import game.controller;
import game.weapon;
import game.gamepublic;
import utils.mylist;
import utils.time;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.perf;
import utils.random;
import framework.framework;
import framework.keysyms;
import framework.timesource;
import framework.resset;
import std.math;

import game.worm;
import game.crate;

interface ServerGraphic {
    //update position
    void setPos(Vector2i pos);
    void setVelocity(Vector2f v);

    //update params
    // p1 is mostly an angle (in degrees), and p2 is mostly unused
    // (actual meaning depends from animation)
    void setParams(int p1, int p2);

    //update animation
    // force = set new animation immediately, else wait until done
    void setNextAnimation(AnimationResource animation, bool force);

    //visibility of the animation
    void setVisible(bool v);

    //kill this graphic
    void remove();

    //if remove() was called
    bool isDead();

    long getUID();
}

package class ServerGraphicLocalImpl : ServerGraphic {
    private mixin ListNodeMixin node;

    long uid;

    //event to be generated, also store local data (currently)
    GraphicEvent event;
    bool nalive; //new value for alive
    bool didchange;

    bool mDead;
    bool alive; //graphic dead or alive remotely

    //return an event to generate the new state or null if nothing changed
    GraphicEvent* createEvent() {
        if (!didchange || (!alive && !nalive))
            return null;

        //don't send non-Adds if not alive
        if (!alive && (nalive == alive))
            return null;

        GraphicEvent* res = new GraphicEvent;
        *res = event;
        res.uid = uid;
        if (!nalive && alive) {
            res.type = GraphicEventType.Remove;
        } else if (nalive && !alive) {
            res.type = GraphicEventType.Add;
        } else {
            res.type = GraphicEventType.Change;
        }

        //reset state machine to capture changes
        didchange = false;
        alive = nalive;
        event.setevent.do_set_ani = false;

        return res;
    }

    //methods of that interface
    void setPos(Vector2i apos) {
        if (event.setevent.pos != apos) {
            event.setevent.pos = apos;
            didchange = true;
        }
    }

    void setVelocity(Vector2f v) {
        if (event.setevent.dir != v) {
            event.setevent.dir = v;
            didchange = true;
        }
    }

    void setParams(int ap1, int ap2) {
        AnimationParams np;
        np.p1 = ap1;
        np.p2 = ap2;
        if (event.setevent.params != np) {
            event.setevent.params = np;
            didchange = true;
        }
    }

    void setNextAnimation(AnimationResource animation, bool force) {
        event.setevent.do_set_ani = true;
        event.setevent.set_animation = animation;
        event.setevent.set_force = force;
        didchange = true;
    }

    void setVisible(bool v) {
        nalive = v;
        if (nalive != alive)
            didchange = true;
    }

    void remove() {
        if (alive) {
            nalive = false;
            didchange = true;
        }
        mDead = true; //for GameEngine
    }

    bool isDead() {
        return mDead;
    }

    long getUID() {
        return uid;
    }
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine : GameEnginePublic, GameEngineAdmin {
    private TimeSource mGameTime;

    protected PhysicWorld mPhysicWorld;
    private List!(GameObject) mObjects;
    public List!(ServerGraphicLocalImpl) mGraphics;
    private Level mLevel;
    private GameLevel mGamelevel;
    PlaneTrigger waterborder;
    PlaneTrigger deathzone;

    private GraphicEvent* mCurrentEvents;

    ResourceSet resources;

    GraphicEvent* currentEvents() {
        return mCurrentEvents;
    }

    void clearEvents() {
        mCurrentEvents = null;
    }

    Level level() {
        return mLevel;
    }

    GameLevel gamelevel() {
        return mGamelevel;
    }

    struct EventQueue {
        GraphicEvent* list;
        Time time;
    }
    EventQueue[] events;
    const lag = 0;//100; //ms
    const lagvar = 0; //100

    private Vector2i mWorldSize;

    private GameController mController;

    GameLogicPublic logic() {
        return mController;
    }

    //from GameEnginePublic
    void signalReadiness() {
        //client signaled readiness
        assert(false);
    }
    void setGameEngineCalback(GameEngineCallback gec) {
        //TODO!
        assert(false);
    }

    Vector2i worldSize() {
        return mWorldSize;
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

    package Log mLog;
    private PerfTimer mNetUpdateTime, mPhysicTime;

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

    //load all weapons from "weapons" subdir
    private void loadWeapons(char[] dir) {
        //load all .conf files found
        gFramework.fs.listdir(dir, "*.conf", false,
            (char[] path) {
                //a weapons file can contain resources, collision map
                //additions and a list of weapons
                auto wp_conf = gFramework.loadConfig(dir~"/"~path[0..$-5]);
                physicworld.loadCollisions(wp_conf.getSubNode("collisions"));
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
        char[] type = weapon.getStringValue("type", "notype");
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

    void windChangerUpdate(float val) {
        mWindForce.accel = Vector2f(val,0);
    }

    private void waterChangerUpdate(float val) {
        mCurrentWaterLevel = val;
        waterborder.plane.define(Vector2f(0, val), Vector2f(1, val));
    }

    this(GameConfig config, ResourceSet a_resources) {
        resources = a_resources;

        assert(config.level !is null);
        mLevel = config.level;

        mLog = registerLog("gameengine");
        mNetUpdateTime = globals.newTimer("game_netupdate");
        mPhysicTime = globals.newTimer("game_physic");

        mGameTime = new TimeSource();
        mGameTime.paused = true;

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());
        mGraphics = new typeof(mGraphics)(ServerGraphicLocalImpl.node
            .getListNodeOffset());
        mPhysicWorld = new PhysicWorld();

        Vector2i levelOffset;
        if (level.isCave) {
            mWorldSize = mLevel.size + Vector2i(0, cSpaceBelowLevel);
            levelOffset = Vector2i(0, 0);
        } else {
            mWorldSize = Vector2i(cOpenLevelWidthMultiplier*mLevel.size.x,
                mLevel.size.y+cSpaceBelowLevel+cSpaceAboveOpenLevel);
            levelOffset = Vector2i(cast(int)((cOpenLevelWidthMultiplier-1)/2.0f
                *mLevel.size.x), cSpaceAboveOpenLevel);
        }

        mGamelevel = new GameLevel(mLevel, levelOffset);

        //to enable level-bitmap collision
        physicworld.add(mGamelevel.physics);
        //various level borders
        waterborder = new PlaneTrigger();
        waterborder.onTrigger = &underWaterTrigger;
        physicworld.add(waterborder);

        deathzone = new PlaneTrigger();
        deathzone.onTrigger = &deathzoneTrigger;
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
        setWindSpeed(-150);   //what unit is that???

        //physics timed changer for water offset
        mWaterChanger = new PhysicTimedChangerFloat(mGamelevel.offset.y
            + mGamelevel.size.y - mGamelevel.waterLevelInit, &waterChangerUpdate);
        mWaterChanger.changePerSec = cWaterRaisingSpeed;
        physicworld.addBaseObject(mWaterChanger);

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        loadLevelStuff();

        //NOTE: GameController relies on many stuff at initialization
        //i.e. physics for worm placement
        mController = new GameController(this, config);
    }

    //actually start the game (called after resources were preloaded)
    void start() {
        mGameTime.paused = false;
    }

    TimeSource gameTime() {
        return mGameTime;
    }

    //return y coordinate of waterline
    int waterOffset() {
        return cast(int)mCurrentWaterLevel;
    }

    float earthQuakeStrength() {
        return mPhysicWorld.earthQuakeStrength();
    }

    //return skyline offset (used by airstrikes)
    float skyline() {
        return mGamelevel.offset.y;
    }

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        //load weapons
        loadWeapons("weapons");

        auto conf = gFramework.loadConfig("game");
        //load sprites
        foreach (char[] name, char[] value; conf.getSubNode("sprites")) {
            auto sprite = gFramework.loadConfig(value);
            loadSpriteClass(sprite);
        }

        mGravForce.accel = Vector2f(0, conf.getFloatValue("gravity",100));

        //hm!?!?
        physicworld.setCollideHandler("hit", &onPhysicHit);

        //this barfs up if setCollideHandler()s were missed
        physicworld.checkCollisionHandlers();
    }

    //called when a and b hit using the "hit" collision
    //i.e. the worm.conf contains this:
    //  collisions {
    //        worm {
    //            ground = "hit"
    //    }}
    //"hit" means onPhysicHit is called, with worm as "a" and ground as "b"
    //
    private void onPhysicHit(PhysicBase a, PhysicBase b) {
        //exactly as the old bahviour
        auto xa = cast(GObjectSprite)(a.backlink);
        if (xa) xa.doImpact(b);
        auto xb = cast(GObjectSprite)(b.backlink);
        if (xb) xb.doImpact(a);
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
        return mWindForce.accel.x;
    }
    public void setWindSpeed(float speed) {
        mWindChanger.target = speed;
    }

    public float gravity() {
        return mGravForce.accel.y;
    }

    void raiseWater(int by) {
        mWaterChanger.target = mCurrentWaterLevel - by;
    }

    //strength = force, degrade = multiplier applied all the time after a
    //  physics.cEarthQuakeDegradeInterval
    //this function never overwrites the settings, but adds both values to the
    //existing ones
    void addEarthQuake(float strength, float degrade) {
        physicworld.addBaseObject(new EarthQuakeDegrader(strength, degrade));
        mLog("created earth quake, strength=%s, degrade=%s", strength, degrade);
    }

    void ensureAdded(GameObject obj) {
        assert(obj.active);
        //in case of lazy removal
        //note that .contains is O(1)
        if (!mObjects.contains(obj))
            mObjects.insert_tail(obj);
    }

    long mUids;

    ServerGraphic createGraphic() {
        auto g = new ServerGraphicLocalImpl();
        g.uid = mUids;
        mUids++;
        mGraphics.insert_tail(g);
        return g;
    }

    PhysicWorld physicworld() {
        return mPhysicWorld;
    }

    protected void simulate() {
        mController.simulate();
    }

    Time blubber;
    int eventCount;

    void netupdate() {
        GraphicEvent* currentlist = null;
        GraphicEvent** lastptr = &currentlist;

        auto cur2 = mGraphics.head;
        while (cur2) {
            auto o = cur2;
            cur2 = mGraphics.next(cur2);

            GraphicEvent* curevent = o.createEvent();
            if (curevent) {
                //add to queue (as tail)
                *lastptr = curevent;
                lastptr = &curevent.next;
                curevent.next = null;
                eventCount++;
            }

            if (o.mDead)
                mGraphics.remove(o);
        }

        if ((mGameTime.current - blubber).secs >= 1) {
            //gDefaultLog("blubb: %s", eventCount);
            blubber = mGameTime.current;
            eventCount = 0;
        }

        EventQueue current;
        current.list = currentlist;
        current.time = mGameTime.current;
        events ~= current;

        mCurrentEvents = null;

        //take one element back from queue
        if (events[0].time + timeMsecs(lag+randRange(-25,25)) < mGameTime.current) {
            mCurrentEvents = events[0].list;
            events = events[1..$];
        }
    }

    Time lastnetupdate;

    void doFrame() {
        mGameTime.update();

        if (!mGameTime.paused) {
            simulate();
            mPhysicTime.start();
            mPhysicWorld.simulate(mGameTime.current);
            mPhysicTime.stop();
            //update game objects
            //NOTE: objects might be inserted/removed while iterating
            //      maybe one should implement a safe iterator...
            GameObject cur = mObjects.head;
            float deltat = mGameTime.difference.secsf;
            while (cur) {
                auto o = cur;
                cur = mObjects.next(cur);
                if (o.active) {
                    o.simulate(deltat);
                } else {
                    //remove (it's done lazily, and here it's actually removed)
                    mObjects.remove(o);
                }
            }

            //all 100ms update
            if (lastnetupdate + timeMsecs(lagvar) < mGameTime.current) {
                mNetUpdateTime.start();
                netupdate();
                lastnetupdate = mGameTime.current;
                mNetUpdateTime.stop();
            }
        }
    }

    //remove all objects etc. from the scene
    void kill() {
        //must iterate savely
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
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
        y_max = max(y_max, 1.0f*mGamelevel.offset.y);
        y_max = min(y_max, 1.0f*mGamelevel.offset.y + mGamelevel.size.y);
        for (;retrycount > 0; retrycount--) {
            drop.y = randRange(1.0f*mGamelevel.offset.y, y_max);
            drop.x = mGamelevel.offset.x + randRange(0, mGamelevel.size.x);
            if (placeObject(drop, y_max, dest, radius))
                return true;
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
        mGamelevel.damage(toVector2i(pos), cast(int)(expl.radius/2.0f));
        physicworld.add(expl);
        //some more chaos, if string enough
        //xxx needs moar tweaking
        //if (damage > 50)
        //    addEarthQuake(damage, 0.5);
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

    void collectCrate(CrateSprite crate, PhysicObject obj) {
        GameObject gobj = cast(GameObject)(obj.backlink);
        if (gobj) {
            mController.collectCrate(crate, gobj);
        } //if not then wtf!?
    }
}
