module game.game;
import levelgen.level;
import game.animation;
import game.gobject;
import game.physic;
import game.glevel;
import game.sprite;
import game.worm;
import game.water;
import game.sky;
import game.scene;
import game.common;
import game.controller;
import game.weapon;
import utils.mylist;
import utils.time;
import utils.log;
import utils.configfile;
import utils.misc;
import utils.random;
import framework.framework;
import framework.keysyms;
import std.math;

import clientengine = game.clientengine;

struct GameConfig {
    Level level;
    ConfigNode teams;
    ConfigNode weapons;
    ConfigNode gamemode;
}

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
}

enum GraphicEventType {
    None,
    Add,
    Change,
    Remove,
}

struct GraphicEvent {
    GraphicEvent* next; //ad-hoc linked list

    GraphicEventType type;
    long uid;
    GraphicSetEvent setevent;
}

struct GraphicSetEvent {
    Vector2i pos;
    Vector2f dir; //direction + velocity
    int p1, p2;
    bool do_set_ani;
    AnimationResource set_animation; //network had to transfer animation id
    bool set_force;
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
        if (event.setevent.p1 != ap1 || event.setevent.p2 != ap2) {
            event.setevent.p1 = ap1;
            event.setevent.p2 = ap2;
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
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine {
    protected Time lastTime;
    Time currentTime;
    protected PhysicWorld mPhysicWorld;
    private List!(GameObject) mObjects;
    public List!(ServerGraphicLocalImpl) mGraphics;
    Level level;
    GameLevel gamelevel;
    PlaneTrigger waterborder;
    PlaneTrigger deathzone;

    GraphicEvent* currentEvents;

    struct EventQueue {
        GraphicEvent* list;
        Time time;
    }
    EventQueue[] events;
    const lag = 100; //ms

    Vector2i levelOffset, worldSize;

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
        return gSpriteClassFactory.instantiate(name, this, registerName);
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
        WeaponClass c = gWeaponClassFactory.instantiate(type, this, weapon);
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

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());
        mGraphics = new typeof(mGraphics)(ServerGraphicLocalImpl.node
            .getListNodeOffset());
        mPhysicWorld = new PhysicWorld();

        if (level.isCave) {
            worldSize = level.size + Vector2i(0, cSpaceBelowLevel);
            levelOffset = Vector2i(0, 0);
        } else {
            worldSize = Vector2i(cOpenLevelWidthMultiplier*level.size.x,
                level.size.y+cSpaceBelowLevel+cSpaceAboveOpenLevel);
            levelOffset = Vector2i(cast(int)((cOpenLevelWidthMultiplier-1)/2.0f
                *level.size.x), cSpaceAboveOpenLevel);
        }

        gamelevel = new GameLevel(level, levelOffset);

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
            + gamelevel.size.y - gamelevel.waterLevelInit, &waterChangerUpdate);
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
        globals.resources.loadResources(globals.loadConfig("stdanims"));

        //load weapons
        auto weapons = globals.loadConfig("weapons");
        globals.resources.loadResources(weapons.find("require_resources"));
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

    void activate(GameObject obj) {
        mObjects.insert_tail(obj);
    }

    void deactivate(GameObject obj) {
        mObjects.remove(obj);
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

    protected void simulate(float deltaT) {
        controller.simulate(deltaT);
    }

    Time blubber;
    int eventCount;

    void netupdate() {
        currentTime = globals.gameTime;

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

        if ((lastTime - blubber).secs >= 1) {
            gDefaultLog("blubb: %s", eventCount);
            blubber = lastTime;
            eventCount = 0;
        }

        EventQueue current;
        current.list = currentlist;
        current.time = currentTime;
        events ~= current;

        currentEvents = null;

        //take one element back from queue
        if (events[0].time + timeMsecs(lag+randRange(-25,25)) < currentTime) {
            currentEvents = events[0].list;
            events = events[1..$];
        }
    }

    Time lastnetupdate;

    void doFrame() {
        currentTime = globals.gameTime;
        float deltaT = (currentTime - lastTime).msecs/1000.0f;
        simulate(deltaT);
        mPhysicWorld.simulate(currentTime);
        //update game objects
        //NOTE: objects might be inserted/removed while iterating
        //      maybe one should implement a safe iterator...
        GameObject cur = mObjects.head;
        while (cur) {
            auto o = cur;
            cur = mObjects.next(cur);
            o.simulate(deltaT);
        }

        //all 100ms update
        if (lastnetupdate + timeMsecs(100) < currentTime) {
            netupdate();
            lastnetupdate = currentTime;
        }

        lastTime = currentTime;
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
        y_max = max(y_max, 1.0f*gamelevel.offset.y);
        y_max = min(y_max, 1.0f*gamelevel.offset.y + gamelevel.size.y);
        for (;retrycount > 0; retrycount--) {
            drop.y = randRange(1.0f*gamelevel.offset.y, y_max);
            drop.x = gamelevel.offset.x + randRange(0, gamelevel.size.x);
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
