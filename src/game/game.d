module game.game;
import game.levelgen.level;
import game.levelgen.landscape;
import game.gobject;
import physics.world;
import game.gfxset;
import game.glevel;
import game.sprite;
import common.animation;
import common.common;
import common.scene;
import game.controller;
import game.controller_events;
import game.weapon.weapon;
import game.events;
import game.glue;
import game.sequence;
import game.setup;
import game.particles;
import game.lua;
import gui.rendertext; //oops, the core shouldn't really depend from the GUI
import net.marshal : Hasher;
import utils.list2;
import utils.time;
import utils.log;
import utils.configfile;
import utils.math;
import utils.md;
import utils.misc;
import utils.perf;
import utils.random;
import utils.reflection;
import framework.framework;
import utils.timesource;
import framework.commandline;
import framework.lua;
import common.resset;

import tango.math.Math;
import tango.util.Convert : to;
import tango.core.Traits : ParameterTupleOf;

import game.levelgen.renderer;// : LandscapeBitmap;

//dummy object *sigh*
class GlobalEvents : GameObject {
    this(GameEngine aengine) { super(aengine, "root"); }
    this (ReflectCtor c) { super(c); }
    override bool activity() { return false; }
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine {
    GameLandscape[] gameLandscapes;
    //the whole fucking world!
    Scene scene;

    Random rnd;

    GameConfig gameConfig;
    ConfigNode persistentState;
    Events events;
    GlobalEvents globalEvents;

    //idiotic hack for sprite.d
    //indexed by SpriteClass only for now
    Events[Object] perClassEvents;

    private {
        static LogStruct!("game.game") log;

        TimeSourcePublic mGameTime;
        GameEngineCallback mCallbacks;

        PhysicWorld mPhysicWorld;
        ObjectList!(GameObject, "node") mObjects;
        Level mLevel;

        PhysicZonePlane mWaterBorder;
        PhysicZonePlane mDeathZone;
        WaterSurfaceGeometry mWaterBouncer;

        GfxSet mGfx;

        GameController mController;

        WindyForce mWindForce;
        PhysicTimedChangerFloat mWindChanger;

        //for raising waterline
        PhysicTimedChangerFloat mWaterChanger;
        //current water level, now in absolute scene coordinates, no more dupes
        float mCurrentWaterLevel;

        //generates earthquakes
        EarthQuakeForce mEarthquakeForceVis, mEarthquakeForceDmg;

        Object[char[]] mHudRequests;

        Sprite[] mPlaceQueue;

        LuaState mScripting;

        //for neutral text, I use GameEngine as key (hacky but simple)
        FormattedText[Object] mTempTextThemed;

        AccessEntry[] mAccessMapping;
        struct AccessEntry {
            char[] tag;
            Team team;
        }

        const cWindChange = 80.0f;
        const cMaxWind = 150f;

        const cWaterRaisingSpeed = 50.0f; //pixels per second

        //minimum distance between placed objects
        const cPlaceMinDistance = 50.0f;
        //position increment for deterministic placement
        const cPlaceIncDistance = 55.0f;
        //distance when creating a platform in empty space
        const cPlacePlatformDistance = 90.0f;

        bool mSavegameHack;
    }

    mixin Methods!("deathzoneTrigger", "underWaterTrigger", "windChangerUpdate",
        "waterChangerUpdate", "onPhysicHit", "offworldTrigger",
        "onHudAdd");

    this(GameConfig config, GfxSet a_gfx, TimeSourcePublic a_gameTime) {
        mSavegameHack = true;

        rnd = new Random();
        //game initialization must be deterministic; so unless GameConfig
        //contains a good pre-generated seed, use a fixed seed
        if (config.randomSeed.length > 0) {
            rnd.seed(to!(uint)(config.randomSeed));
        } else {
            rnd.seed(1);
        }
        mGfx = a_gfx;
        gameConfig = config;
        mGameTime = a_gameTime;
        createCmd();
        mCallbacks = new GameEngineCallback();

        mScripting = createScriptingObj(this);

        mScripting.addSingleton(this);
        mScripting.addSingleton(gfx);
        mScripting.addSingleton(rnd);

        events = new Events();
        globalEvents = new GlobalEvents(this);
        events.setScripting(mScripting, "eventhandlers_global");
        loadScript("events.lua");

        loadScript("timer.lua");

        //for now, this is to init events+scripting...
        foreach (SpriteClass s; mGfx.allSpriteClasses()) {
            s.initPerEngine(this);
        }

        persistentState = config.gamestate.copy();

        assert(config.level !is null);
        mLevel = config.level;
        scripting.addSingleton(mLevel);

        scene = new Scene();

        mObjects = new typeof(mObjects)();

        OnHudAdd.handler(events, &onHudAdd);

        mPhysicWorld = new PhysicWorld(rnd);
        mPhysicWorld.collide = gfx.collision_map;
        scripting.addSingleton(mPhysicWorld);

        foreach (o; level.objects) {
            if (auto ls = cast(LevelLandscape)o) {
                //xxx landscapes should keep track of themselves
                gameLandscapes ~= new GameLandscape(this, ls);
            }
        }

        //various level borders
        mWaterBorder = new PhysicZonePlane();
        auto wb = new ZoneTrigger(mWaterBorder);
        wb.onTrigger = &underWaterTrigger;
        wb.collision = physicworld.collide.findCollisionID("water");
        physicworld.add(wb);
        mWaterBouncer = new WaterSurfaceGeometry();
        physicworld.add(mWaterBouncer);
        //Stokes's drag force
        physicworld.add(new ForceZone(new StokesDragFixed(5.0f), mWaterBorder));
        //xxx additional object-attribute controlled Stokes's drag
        physicworld.add(new StokesDragObject());
        //Earthquake generator
        mEarthquakeForceVis = new EarthQuakeForce(false);
        mEarthquakeForceDmg = new EarthQuakeForce(true);
        physicworld.add(mEarthquakeForceVis);
        physicworld.add(mEarthquakeForceDmg);

        mDeathZone = new PhysicZonePlane();
        auto dz = new ZoneTrigger(mDeathZone);
        dz.collision = physicworld.collide.collideAlways();
        dz.onTrigger = &deathzoneTrigger;
        dz.inverse = true;
        //the trigger is inverse, and triggers only when the physic object is
        //completely in the deathzone, but graphics are often larger :(
        auto death_y = mLevel.worldSize.y + 20;
        //because trigger is inverse, the plane must be defined inverted too
        mDeathZone.plane.define(Vector2f(1, death_y), Vector2f(0, death_y));
        physicworld.add(dz);

        //create trigger to check for objects leaving the playable area
        auto worldZone = new PhysicZoneXRange(0, mLevel.worldSize.x);
        //only if completely outside (= touching the game area inverted)
        worldZone.whenTouched = true;
        auto offwTrigger = new ZoneTrigger(worldZone);
        offwTrigger.collision = physicworld.collide.collideAlways();
        offwTrigger.inverse = true;  //trigger when outside the world area
        offwTrigger.onTrigger = &offworldTrigger;
        physicworld.add(offwTrigger);

        mWindForce = new WindyForce();
        mWindChanger = new PhysicTimedChangerFloat(0, &windChangerUpdate);
        mWindChanger.changePerSec = cWindChange;
        physicworld.add(new ForceZone(mWindForce, mWaterBorder, true));
        physicworld.add(mWindChanger);
        randomizeWind();

        //physics timed changer for water offset
        mWaterChanger = new PhysicTimedChangerFloat(mLevel.waterBottomY,
            &waterChangerUpdate);
        mWaterChanger.changePerSec = cWaterRaisingSpeed;
        physicworld.add(mWaterChanger);


        loadLevelStuff();

        //lol.
        loadScript("gameutils.lua");
        OnGameInit.raise(globalEvents);

        //NOTE: GameController relies on many stuff at initialization
        //i.e. physics for worm placement
        //and a complete weapon class list (when loading team weaponsets)
        new GameController(this, config);

        //read the shitty access map, need to have access to the controller
        auto map = config.managment.getSubNode("access_map");
        foreach (ConfigNode sub; map) {
            //sub is "tag_name { "teamid1" "teamid2" ... }"
            foreach (char[] key, char[] value; sub) {
                Team found;
                foreach (Team t; controller.teams) {
                    if (t.id() == value) {
                        found = t;
                        break;
                    }
                }
                //xxx error handling
                assert(!!found, "invalid team id: "~value);
                mAccessMapping ~= AccessEntry(sub.name, found);
            }
        }
    }

    this (ReflectCtor c) {
        c.transient(this, &mCallbacks);
        c.transient(this, &mCmd);
        c.transient(this, &mCmds);
        c.transient(this, &mTempTextThemed);
        c.transient(this, &mScripting); //for now
        c.transient(this, &mSavegameHack);
        auto t = c.types();
        t.registerClass!(typeof(mObjects));
        if (c.recreateTransient) {
            mCallbacks = new GameEngineCallback();
            createCmd();
        }
    }

    final LuaState scripting() {
        //assertion may happen on savegames (when I was writing this, I didn't
        //  care about savegames at all; they may be broken; enjoy.)
        assert (!!mScripting);
        return mScripting;
    }

    final void loadScript(char[] filename) {
        .loadScript(scripting(), filename);
    }

    Sprite createSprite(char[] name) {
        return gfx.findSpriteClass(name).createSprite(this);
    }

    package void setController(GameController ctl) {
        assert(!mController);
        mController = ctl;
    }

    //lol.
    GameController controller() {
        return mController;
    }
    alias controller logic;

    //--- start GameEnginePublic

    ///level being played, must not modify returned object
    final Level level() {
        return mLevel;
    }

    final GameEngineCallback callbacks() {
        return mCallbacks;
    }

    ///time of last frame that was simulated
    final TimeSourcePublic gameTime() {
        return mGameTime;
    }

    ///return y coordinate of waterline
    int waterOffset() {
        return cast(int)mCurrentWaterLevel;
    }

    ///wind speed ([-1, +1] I guess, see sky.d)
    float windSpeed() {
        return mWindForce.windSpeed.x/cMaxWind;
    }

    ///return how strong the earth quake is, 0 if no earth quake active
    float earthQuakeStrength() {
        return mEarthquakeForceVis.earthQuakeStrength()
            + mEarthquakeForceDmg.earthQuakeStrength();
    }

    ///game configuration, must not modify returned object
    GameConfig config() {
        return gameConfig;
    }

    ///game resources, must not modify returned object
    GfxSet gfx() {
        return mGfx;
    }

    //--- end GameEnginePublic

    private void windChangerUpdate(float val) {
        mWindForce.windSpeed = Vector2f(val,0);
    }

    private void waterChangerUpdate(float val) {
        mCurrentWaterLevel = val;
        mWaterBorder.plane.define(Vector2f(0, val), Vector2f(1, val));
        //why -5? a) it looks better, b) objects won't drown accidentally
        mWaterBouncer.updatePos(val - 5);
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

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        auto conf = loadConfig("game");

        mPhysicWorld.gravity = Vector2f(0, conf.getFloatValue("gravity",100));

        //hm!?!?
        mPhysicWorld.onCollide = &onPhysicHit;
    }

    //called when a and b touch in physics
    private void onPhysicHit(ref Contact c) {
        if (c.source == ContactSource.generator)
            return;
        //exactly as the old behaviour
        auto xa = cast(Sprite)(c.obj[0].backlink);
        if (xa) xa.doImpact(c.obj[1], c.normal);
        if (c.obj[1]) {
            auto xb = cast(Sprite)(c.obj[1].backlink);
            if (xb) xb.doImpact(c.obj[0], -c.normal);
        }
    }

    private void underWaterTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(StateSprite)(other.backlink);
        if (x) x.setIsUnderWater();
    }

    private void deathzoneTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(Sprite)(other.backlink);
        if (x) x.exterminate();
    }

    private void offworldTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(Sprite)(other.backlink);
        auto member = mController.memberFromGameObject(x, false);
        if (!member)
            return; //I don't know, try firing lots of mine airstrikes
        //xxx team stuff should get out of here
        //  rather, somehow affect the object directly, and the team code has to
        //  react on it
        if (member.active)
            member.active(false);
    }

    //wind speeds are in [-1.0, 1.0]
    void setWindSpeed(float speed) {
        mWindChanger.target = clampRangeC(speed, -1.0f, 1.0f)*cMaxWind;
    }
    void randomizeWind() {
        mWindChanger.target = cMaxWind*rnd.nextDouble3();
    }

    float gravity() {
        return mPhysicWorld.gravity.y;
    }

    void raiseWater(int by) {
        //argh why is mCurrentWaterLevel a float??
        int t = cast(int)mCurrentWaterLevel - by;
        t = max(t, mLevel.waterTopY); //don't grow beyond limit?
        mWaterChanger.target = t;
    }

    //strength = force, duration = absolute time,
    //  degrade = true for exponential degrade
    //this function never overwrites the settings, but adds both values to the
    //existing ones
    void addEarthQuake(float strength, Time duration, bool degrade,
        bool bounceObjects = false)
    {
        auto ef = mEarthquakeForceVis;
        if (bounceObjects)
            ef = mEarthquakeForceDmg;
        physicworld.add(new EarthQuakeDegrader(strength, duration, degrade,
            ef));
        log("created earth quake, strength={}, duration={}, degrade={}",
            strength, duration, degrade);
    }

    void ensureAdded(GameObject obj) {
        assert(obj._is_active());
        //in case of lazy removal
        //note that .contains is O(1) if used with .node
        if (!mObjects.contains(obj))
            mObjects.add(obj);
    }

    PhysicWorld physicworld() {
        return mPhysicWorld;
    }

    void frame() {
        auto physicTime = globals.newTimer("game_physic");
        physicTime.start();
        mPhysicWorld.simulate(mGameTime.current);
        physicTime.stop();

        mController.simulate();

        //update game objects
        //NOTE: objects might be inserted/removed while iterating
        //      List.opApply can deal with that
        float deltat = mGameTime.difference.secsf;
        foreach (GameObject o; mObjects) {
            if (o._is_active()) {
                o.simulate(deltat);
            } else {
                //remove (it's done lazily, and here it's actually removed)
                mObjects.remove(o);
            }
        }

        //xxx not sure where script functions should be called
        //  this will handle all script timers and per-frame functions
        //null termination for efficient toStringz
        scripting().call("game_per_frame\0");

        debug {
            globals.setCounter("gameobjects", mObjects.count);
        }
    }

    //remove all objects etc. from the scene
    void kill() {
        //must iterate savely
        foreach (GameObject o; mObjects) {
            o.kill();
        }
    }

    Rect2f placementArea() {
        //xxx: there's also mLevel.landBounds, which does almost the same
        //  correct way of doing this would be to include all objects on that
        //  worms can stand/sit
        //this code also seems to assume that the landscape is in the middle,
        //  which is ok most time
        auto mid = toVector2f(mLevel.worldSize)/2;
        Rect2f landArea = Rect2f(mid, mid);
        if (gameLandscapes.length > 0)
            landArea = Rect2f(toVector2f(gameLandscapes[0].offset),
                toVector2f(gameLandscapes[0].offset));
        foreach (gl; gameLandscapes) {
            landArea.extend(toVector2f(gl.offset));
            landArea.extend(toVector2f(gl.offset + gl.size));
        }

        //add some space at the top for object placement
        landArea.p1.y = max(landArea.p1.y - 50f, 0);

        //don't place underwater
        float y_max = waterOffset - 10;

        Rect2f area = Rect2f(0, 0, mLevel.worldSize.x, y_max);
        area.fitInside(landArea);
        return area;
    }

    //try to place an object into the landscape
    //essentially finds the first collision under "drop", then checks the
    //normal and distance to other objects
    //success only when only the LevelGeometry object is hit
    //  drop = any startpoint
    //  dest = where it is dropped (will have same x value as drop)
    //  inAir = true to place exactly at drop and create a hole/platform
    //returns if dest contains a useful value
    private bool placeObject(Vector2f drop, Rect2f area, float radius,
        out Vector2f dest, bool inAir = false)
    {
        if (inAir) {
            return placeObject_air(drop, area, radius, dest);
        } else {
            return placeObject_landscape(drop, area, radius, dest);
        }
    }


    private bool placeObject_air(Vector2f drop, Rect2f area, float radius,
        out Vector2f dest)
    {
        int holeRadius = cast(int)cPlacePlatformDistance/2;

        //don't place half the platform outside the level area
        area.extendBorder(Vector2f(-holeRadius));
        if (!area.isInside(drop))
            return false;

        //check distance to other sprites
        foreach (GameObject o; mObjects) {
            auto s = cast(Sprite)o;
            if (s) {
                if ((s.physics.pos-drop).length < cPlacePlatformDistance+10f)
                    return false;
            }
        }

        //check if the hole would intersect with any indestructable landscape
        // (we couldn't blast a hole there; forcing the hole would work, but
        //  worms could get trapped then)
        foreach (ls; gameLandscapes) {
            if (ls.lexelTypeAt(toVector2i(drop), holeRadius, Lexel.SolidHard))
                return false;
        }

        //checks ok, remove land and create platform
        damageLandscape(toVector2i(drop), holeRadius);
        //same thing that is placed with the girder weapon
        Surface bmp = level.theme.girder;
        insertIntoLandscape(Vector2i(cast(int)drop.x-bmp.size.x/2,
            cast(int)drop.y+bmp.size.y/2), bmp, Lexel.SolidSoft);
        dest = drop;
        return true;
    }

    private bool placeObject_landscape(Vector2f drop, Rect2f area, float radius,
        out Vector2f dest)
    {
        if (!area.isInside(drop))
            return false;

        GeomContact contact;
        //check if origin point is inside geometry
        if (physicworld.collideGeometry(drop, radius, contact))
            return false;
        //cast a ray downwards from drop
        if (!physicworld.thickRay(drop, Vector2f(0, 1), area.p2.y - drop.y,
            radius, drop, contact))
        {
            return false;
        }
        if (contact.depth == float.infinity)
            //most likely, drop was inside the landscape
            return false;
        //had a collision, check normal
        if (contact.normal.y < 0
            && abs(contact.normal.x) < -contact.normal.y*1.19f)
        {
            //check distance to other sprites
            foreach (GameObject o; mObjects) {
                auto s = cast(Sprite)o;
                if (s) {
                    if ((s.physics.pos - drop).length < cPlaceMinDistance)
                        return false;
                }
            }
            dest = drop;
            return true;
        } else {
            return false;
        }
    }

    //place an object deterministically on the landscape
    //checks a position grid with shrinking cell size for a successful placement
    //returns the first free position found
    private bool placeOnLandscapeDet(float radius, out Vector2f drop,
        out Vector2f dest)
    {
        //multiplier (controls grid size)
        int multiplier = 16;

        Rect2f area = placementArea();

        while (multiplier > 0) {
            float xx = cPlaceIncDistance * multiplier;
            float x = area.p1.x + realmod(xx, area.size.x);
            float y = area.p1.y + max((multiplier-1)/4, 0)*cPlaceIncDistance;
            while (y < area.p2.y) {
                drop.x = x;
                drop.y = y;
                if (placeObject_landscape(drop, area, radius, dest))
                    return true;
                x += cPlaceIncDistance * multiplier;
                if (x > area.p2.x) {
                    y += cPlaceIncDistance * max(multiplier/4, 1);
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
    bool placeObjectRandom(float radius, int retrycount,
        out Vector2f drop, out Vector2f dest, bool inAir = false)
    {
        Rect2f area = placementArea();
        for (;retrycount > 0; retrycount--) {
            drop.x = rnd.nextRange(area.p1.x, area.p2.x);
            drop.y = rnd.nextRange(area.p1.y, area.p2.y);
            if (placeObject(drop, area, radius, dest, inAir))
                return true;
        }
        return false;
    }

    ///Queued placing:
    ///as placeObjectDet always returns the same positions for the same call
    ///order, use queuePlaceOnLandscape() to add all sprites to the queue,
    ///then call finishPlace() to randomize the queue and place them all
    //queue for placing anywhere on landscape
    //call engine.finishPlace() when done with all sprites
    void queuePlaceOnLandscape(Sprite sprite) {
        mPlaceQueue ~= sprite;
    }
    void finishPlace() {
        //randomize place queue
        rnd.randomizeArray(mPlaceQueue);

        foreach (Sprite sprite; mPlaceQueue) {
            Vector2f npos, tmp;
            if (!placeOnLandscapeDet(sprite.physics.posp.radius,
                tmp, npos))
            {
                //placement unsuccessful
                //create a platform at a random position
                if (placeObjectRandom(sprite.physics.posp.radius,
                    50, tmp, npos, true))
                {
                    log("placing '{}' in air!", sprite);
                } else {
                    log("couldn't place '{}'!", sprite);
                    //xxx
                    npos = toVector2f(mLevel.worldSize)/2;
                }
            }
            log("placed '{}' at {}", sprite, npos);
            sprite.activate(npos);
        }
        mPlaceQueue = null;
    }

    private void onHudAdd(GameObject sender, char[] id, Object obj) {
        assert(!(id in mHudRequests), "id must be unique?");
        mHudRequests[id] = obj;
    }

    //just needed for game loading (see gameframe.d)
    //(actually, this is needed even on normal game start)
    Object[char[]] allHudRequests() {
        return mHudRequests;
    }

    //draw some text with a border around it, in the usual worms label style
    //see getTempLabel()
    //the bad:
    //- slow, may trigger memory allocations (at the very least it will use
    //  slow array appends, even if no new memory is really allocated)
    //- does a lot more work than just draw text and a box
    //- slow because it formats text on each frame
    //- it sucks, maybe I'll replace it by something else
    //=> use FormattedText instead with GfxSet.textCreate()
    //the good:
    //- uses the same drawing code as other _game_ labels
    //- for very transient labels, this probably performs better than allocating
    //  a FormattedText and keeping it around
    //- no need to be deterministic
    void drawTextFmt(Canvas c, Vector2i pos, char[] fmt, ...) {
        auto txt = getTempLabel();
        txt.setTextFmt_fx(true, fmt, _arguments, _argptr);
        txt.draw(c, pos);
    }

    //return a temporary label in worms style
    //see drawTextFmt() for the why and when to use this
    //how to use:
    //- use txt.setTextFmt() to set the text on the returned object
    //- possibly call txt.textSize() to get the size including label border
    //- call txt.draw()
    //- never touch the object again, as it will be used by other code
    //- you better not change any obscure properties of the label (like font)
    //if theme is !is null, the label will be in the team's color
    FormattedText getTempLabel(TeamTheme theme = null) {
        //xxx: AA lookup could be avoided by using TeamTheme.colorIndex
        Object idx = theme ? theme : this;
        if (auto p = idx in mTempTextThemed)
            return *p;

        FormattedText res;
        if (theme) {
            res = theme.textCreate();
        } else {
            res = GfxSet.textCreate();
        }
        res.shrink = false;
        mTempTextThemed[idx] = res;
        return res;
    }


    //non-deterministic
    private void showExplosion(Vector2f at, int radius) {
        int d = radius*2;
        int r = 1, s = -1, t = -1;
        if (d < mGfx.expl.sizeTreshold[0]) {
            //only some smoke
        } else if (d < mGfx.expl.sizeTreshold[1]) {
            //tiny explosion without text
            s = 0;
            r = 2;
        } else if (d < mGfx.expl.sizeTreshold[2]) {
            //medium-sized, may have small text
            s = 1;
            t = rngShared.next(-1,3);
            r = 3;
        } else if (d < mGfx.expl.sizeTreshold[3]) {
            //big, always with text
            s = 2;
            r = 4;
            t = rngShared.next(0,4);
        } else {
            //huge, always text
            s = 3;
            r = 4;
            t = rngShared.next(0,4);
        }

        void emit(ParticleType t) {
            callbacks.particleEngine.emitParticle(at, Vector2f(0), t);
        }

        if (s >= 0) {
            //shockwave
            emit(mGfx.expl.shockwave1[s]);
            emit(mGfx.expl.shockwave2[s]);
            //flaming sparks
            //in WWP, those use a random animation speed
            for (int i = 0; i < rngShared.nextRange(2, 3); i++) {
                callbacks.particleEngine.emitParticle(at, Vector2f(0, -1)
                    .rotated(rngShared.nextRange(-PI/2, PI/2))
                    * rngShared.nextRange(0.5f, 1.0f) * radius * 7,
                    mGfx.expl.spark);
            }
        }
        if (t >= 0) {
            //centered text
            emit(mGfx.expl.comicText[t]);
        }
        if (r > 0) {
            //white smoke bubbles
            for (int i = 0; i < r*3; i++) {
                callbacks.particleEngine.emitParticle(at
                    + Vector2f(0, -1)
                    .rotated(rngShared.nextRange!(float)(0, PI*2)) * radius
                    * rngShared.nextRange(0.25f, 1.0f),
                    Vector2f(0, -1).rotated(rngShared.nextRange(-PI/2, PI/2)),
                    mGfx.expl.smoke[rngShared.next(0, r)]);
            }
        }

        //always sound; I don't know how the explosion sound samples relate to
        //  the explosion size, so the sound is picked randomly
        if (s >= 0) {
            emit(mGfx.expl.sound);
        }
    }

    void animationEffect(Animation ani, Vector2i at, AnimationParams p) {
        //if this function gets used a lot, maybe it would be worth it to fuse
        //  this with the particle engine (cf. showExplosion())
        Animator a = new Animator(callbacks.interpolateTime);
        a.auto_remove = true;
        a.setAnimation(ani);
        a.pos = at;
        a.params = p;
        a.zorder = GameZOrder.Effects;
        callbacks.scene.add(a);
    }

    void explosionAt(Vector2f pos, float damage, GameObject cause,
        bool effect = true, bool damage_landscape = true,
        bool delegate(ExplosiveForce,PhysicObject) selective = null)
    {
        if (damage < float.epsilon)
            return;
        auto expl = new ExplosiveForce();
        expl.damage = damage;
        expl.pos = pos;
        expl.onCheckApply = selective;
        expl.cause = cause;
        auto iradius = cast(int)((expl.radius+0.5f)/2.0f);
        if (damage_landscape)
            damageLandscape(toVector2i(pos), iradius, cause);
        physicworld.add(expl);
        if (effect)
            showExplosion(pos, iradius);
        //some more chaos, if strong enough
        //xxx needs moar tweaking
        if (damage > 90)
            addEarthQuake(damage*2.0f, timeSecs(1.5f), true);
    }

    //destroy a circular area of the damageable landscape
    void damageLandscape(Vector2i pos, int radius, GameObject cause = null) {
        int count;
        foreach (ls; gameLandscapes) {
            count += ls.damage(pos, radius);
        }
        if (cause && count > 0) {
            OnDemolish.raise(cause, count);
        }
    }

    //insert bitmap into the landscape
    //(bitmap is a Resource for the network mode, if we'll ever have one)
    void insertIntoLandscape(Vector2i pos, Surface bitmap, Lexel bits) {
        Rect2i newrc = Rect2i.Span(pos, bitmap.size);

        //this is if the objects is inserted so that the landscape doesn't
        //  cover it fully - possibly create new landscapes to overcome this
        //actually, you can remove all this code if it bothers you; it's not
        //  like being able to extend the level bitmap is a good feature

        //look if landscape really needs to be extended
        //(only catches common cases)
        bool need_extend;
        foreach (ls; gameLandscapes) {
            need_extend |= !ls.rect.contains(newrc);
        }

        Rect2i[] covered;
        if (need_extend) {
            foreach (ls; gameLandscapes) {
                covered ~= ls.rect;
            }
            //test again (catches cases where object crosses landscape borders)
            need_extend = newrc.substractRects(covered).length > 0;
        }

        if (need_extend) {
            //only add large, aligned tiles; this prevents degenerate cases when
            //  lots of small bitmaps are added (like snow)
            newrc.fitTileGrid(Vector2i(512, 512));
            Rect2i[] uncovered = newrc.substractRects(covered);
            foreach (rc; uncovered) {
                assert(rc.size().x > 0 && rc.size().y > 0);
                log("insert landscape: {}", rc);
                gameLandscapes ~= new GameLandscape(this, rc);
            }
        }

        //really insert (relies on clipping)
        foreach (ls; gameLandscapes) {
            ls.insert(pos, bitmap, bits);
        }
    }

    //determine round-active objects
    //just another loop over all GameObjects :(
    bool checkForActivity() {
        bool quake = earthQuakeStrength() > 0;
        if (quake)
            return true;
        if (!mWaterChanger.done)
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
        auto sc = gfx.findSpriteClass(name, true);
        if (!sc)
            return 0;
        int ret = 0;
        foreach (GameObject o; mObjects) {
            auto s = cast(Sprite)o;
            if (s) {
                if (s.type == sc)
                    ret++;
            }
        }
        return ret;
    }

    void crateTest() {
        mController.dropCrate(true);
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
                    auto s = cast(Sprite)(o);
                    if (s)
                        s.exterminate();
                    o.kill();
                }
            } else {
                if (!all) continue;
            }
            if (cast(Sprite)o) {
                log("{}{} at {}", sa, o.toString(),
                    (cast(Sprite)o).physics.pos);
            } else {
                log("{}{}", sa, o.toString());
            }
        }
        log("-- {} objects reporting activity",i);
    }

    void scriptExecute(MyBox[] args, Output write) {
        char[] cmd = args[0].unbox!(char[]);
        try {
            scripting.scriptExec(cmd);
            write.writefln("OK");
        } catch (ScriptingException e) {
            write.writefln(e.msg);
        } catch (ClassNotRegisteredException e) {
            write.writefln(e.msg);
        }
    }

    //calculate a hash value of the game engine state
    //this is a just quick & dirty test to detect diverging client simulation
    //it should always prefer speed over accuracy
    void hash(Hasher hasher) {
        hasher.hash(rnd.state());
        foreach (GameObject o; mObjects) {
            o.hash(hasher);
        }
    }

    void debug_draw(Canvas c) {
        foreach (GameObject o; mObjects) {
            o.debug_draw(c);
        }
    }

    GameObject debug_pickObject(Vector2i pos) {
        auto p = toVector2f(pos);
        Sprite best;
        foreach (GameObject o; mObjects) {
            if (auto sp = cast(Sprite)o) {
                //about the NaN thing, there are such objects *shrug*
                if (!sp.physics.pos.isNaN() && (!best ||
                    (p-sp.physics.pos).length < (p-best.physics.pos).length))
                {
                    best = sp;
                }
            }
        }
        return best;
    }

    //--------------- client commands
    //if this wasn't D, I'd put this into a separate source file
    //but this is D, and the only way to move it to a separate file would be
    //  either to create bloat by creating a new class, or doing "unclean"
    //  stuff by putting this into free functions (and what about the vars?)

    CommandBucket mCmds;
    CommandLine mCmd;
    //temporary during command execution (sorry)
    char[] mTmp_CurrentAccessTag;

    //execute a user command
    //because cmd comes straight from the network, there's an access_tag
    //  parameter, which kind of identifies the sender of the command. the
    //  access_tag corresponds to the key in mAccessMapping.
    //the tag "local" is specially interpreted, and means the command comes
    //  from a privileged source. this disables access control checking.
    //be warned: in network game, the engine is replicated, and all nodes
    //  think they are "local", so using this in network games might cause chaos
    //  and desynchronization... it's a hack for local games, anyway
    void executeCommand(char[] access_tag, char[] cmd) {
        //log("exec: '{}': '{}'", access_tag, cmd);
        assert(mTmp_CurrentAccessTag == "");
        mTmp_CurrentAccessTag = access_tag;
        scope(exit) mTmp_CurrentAccessTag = "";
        mCmd.execute(cmd);
    }

    //test if the given team can be accessed with the given access tag
    //right now used for ClientControl.getOwnedTeams()
    bool checkTeamAccess(char[] access_tag, Team t) {
        if (access_tag == "local")
            return true;
        foreach (ref entry; mAccessMapping) {
            if (entry.tag == access_tag && entry.team is t)
                return true;
        }
        return false;
    }

    //internal clusterfuck follows

    //automatically add an item to the command line parser
    //compile time magic is used to infer the parameters, and the delegate
    //is called when the command is invoked (maybe this is overcomplicated)
    private void addCmd(T)(char[] name, T del) {
        alias ParameterTupleOf!(T) Params;

        //proxify the function in a commandline call
        //the wrapper is just to get a delegate, that is valid even after this
        //function has returned
        //in D2.0, this Wrapper stuff will be unnecessary
        struct Wrapper {
            T callee;
            char[] name;
            void cmd(MyBox[] params, Output o) {
                Params p;
                //(yes, p[i] will have a different static type in each iteration)
                foreach (int i, x; Params) {
                    p[i] = params[i].unbox!(x)();
                }
                callee(p);
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.callee = del;
        pwrap.name = name;

        //build command line argument list according to delegate arguments
        char[][] cmdargs;
        foreach (int i, x; Params) {
            char[]* pt = typeid(x) in gCommandLineParserTypes;
            if (!pt) {
                assert(false, "no command line parser for " ~ x.stringof);
            }
            cmdargs ~= myformat("{}:param_{}", *pt, i);
        }

        mCmds.register(Command(name, &pwrap.cmd, "-", cmdargs));
    }

    //similar to addCmd()
    //expected is a delegate like void foo(TeamMember w, X); where
    //X can be further parameters (can be empty)
    private void addWormCmd(T)(char[] name, T del) {
        //remove first parameter, because that's the worm
        alias ParameterTupleOf!(T)[1..$] Params;

        struct Wrapper {
            GameEngine owner;
            T callee;
            void moo(Params p) {
                bool ok;
                owner.checkWormCommand(
                    (TeamMember w) {
                        ok = true;
                        //may error here, if del has a wrong type
                        callee(w, p);
                    }
                );
                if (!ok)
                    log("denied: {}", owner.mTmp_CurrentAccessTag);
            }
        }

        Wrapper* pwrap = new Wrapper;
        pwrap.owner = this;
        pwrap.callee = del;

        addCmd(name, &pwrap.moo);
    }

    private void createCmd() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();

        //usual server "admin" command
        //xxx: not access checked, although it could
        addCmd("raise_water", &raiseWater);
        addCmd("set_wind", &setWindSpeed);
        addCmd("crate_test", &crateTest);
        addCmd("shake_test", &addEarthQuake);
        addCmd("activity", &activityDebug);
        mCmds.registerCommand("exec", &scriptExecute, "execute script",
            ["text...:command"]);

        //worm control commands; work like above, but the worm-selection code
        //is factored out

        //remember that delegate literals must only access their params
        //if they access members of this class, runtime errors will result

        addWormCmd("next_member", (TeamMember w) {
            w.team.doChooseWorm();
        });
        addWormCmd("jump", (TeamMember w, bool alt) {
            w.control.jump(alt ? JumpMode.straightUp : JumpMode.normal);
        });
        addWormCmd("move", (TeamMember w, int x, int y) {
            w.control.doMove(Vector2i(x, y));
        });
        addWormCmd("weapon", (TeamMember w, char[] weapon) {
            WeaponClass wc;
            if (weapon != "-")
                wc = w.engine.gfx.findWeaponClass(weapon, true);
            w.control.selectWeapon(wc);
        });
        addWormCmd("set_timer", (TeamMember w, int ms) {
            w.control.doSetTimer(timeMsecs(ms));
        });
        addWormCmd("set_target", (TeamMember w, int x, int y) {
            w.control.doSetPoint(Vector2f(x, y));
        });
        addWormCmd("select_fire_refire", (TeamMember w, char[] m, bool down) {
            WeaponClass wc = w.engine.gfx.findWeaponClass(m);
            w.control.selectFireRefire(wc, down);
        });
        addWormCmd("selectandfire", (TeamMember w, char[] m, bool down) {
            if (down) {
                WeaponClass wc;
                if (m != "-")
                    wc = w.engine.gfx.findWeaponClass(m, true);
                w.control.selectWeapon(wc);
                //doFireDown will save the keypress and wait if not ready
                w.control.doFireDown(true);
            } else {
                //key was released (like fire behavior)
                w.control.doFireUp();
            }
        });

        //also a worm cmd, but specially handled
        addCmd("weapon_fire", &executeWeaponFire);
        addCmd("remove_control", &removeControl);

        mCmds.bind(mCmd);
    }

    //during command execution, returns the Team that sent the command
    //xxx mostly a hack for scriptExecute(), has no real other use
    Team ownedTeam() {
        //we must intersect both sets of team members (= worms):
        // set of active worms (by game controller) and set of worms owned by us
        //xxx: if several worms are active that belong to us, pick the first one
        foreach (Team t; controller.teams()) {
            if (t.active && checkTeamAccess(mTmp_CurrentAccessTag, t)) {
                return t;
            }
        }
        return null;
    }

    //if a worm control command is incoming (like move, shoot, etc.), two things
    //must be done here:
    //  1. find out which worm is controlled by GameControl
    //  2. check if the move is allowed
    private bool checkWormCommand(void delegate(TeamMember w) pass) {
        Team t = ownedTeam();
        if (t) {
            pass(t.current);
            return true;
        }
        return false;
    }

    //Special handling for fire command: while replaying, fire will skip the
    //replay (fast-forward to end)
    //xxx: used to cancel replay mode... can't do this anymore
    //  instead, it's hacked back into gameshell.d somewhere
    private void executeWeaponFire(bool is_down) {
        void fire(TeamMember w) {
            if (is_down) {
                w.control.doFireDown();
            } else {
                w.control.doFireUp();
            }
        }

        if (!checkWormCommand(&fire)) {
            //no worm active
            //spacebar for crate
            controller.instantDropCrate();
        }
    }

    //there's remove_control somewhere in cmdclient.d, and apparently this is
    //  called when a client disconnects; the teams owned by that client
    //  surrender
    private void removeControl() {
        //special handling because teams don't need to be active
        foreach (Team t; controller.teams()) {
            if (checkTeamAccess(mTmp_CurrentAccessTag, t)) {
                t.surrenderTeam();
            }
        }
    }
}
