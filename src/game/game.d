module game.game;
import game.effects;
import game.levelgen.level;
import game.levelgen.landscape;
import physics.world;
import game.gfxset;
import game.glevel;
import game.sprite;
import common.animation;
import common.common;
import common.scene;
import game.core;
import game.lua.base;
import game.weapon.weapon;
import game.events;
import game.sequence;
import game.setup;
import game.temp;
import game.particles;
import gui.rendertext; //oops, the core shouldn't really depend from the GUI
import net.marshal : Hasher;
import utils.list2;
import utils.time;
import utils.log;
import utils.configfile;
import utils.math;
import utils.misc;
import utils.perf;
import utils.random;
import framework.framework;
import utils.timesource;
import framework.commandline;
import common.resset;

import tango.math.Math;
import tango.util.Convert : to;

import game.levelgen.renderer;// : LandscapeBitmap;

//legacy crap (makes engine available as GameEngine, instead of GameCore)
abstract class GameObject2 : GameObject {
    this(GameCore aengine, char[] event_target_type) {
        assert(aengine !is null);
        super(aengine, event_target_type);
    }

    //reintroduce GameObject.engine()
    final GameEngine engine() {
        return GameEngine.fromCore(super.engine);
    }
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameEngine : GameCore {
    //xxx how to remove this:
    //  1. for explosions, this should somehow be handled by the physics,
    //     because the physic might have some sort of spatial tree making
    //     position => GameLandscape lookup faster; the rest would somehow be
    //     handled in applyExplosion, like all normal physic objects
    //  2. object placing can somehow be handled differently; it is seldomly
    //     needed and can be moved into some dark corner of the game
    GameLandscape[] gameLandscapes;

    const cDamageToImpulse = 140.0f;
    const cDamageToRadius = 2.0f;

    //dependency hack
    void delegate(Sprite s) onOffworld;

    private {
        static LogStruct!("game.game") log;

        PhysicZonePlane mWaterBorder;
        WaterSurfaceGeometry mWaterBouncer;

        //only for explosions; lazily initialized
        GfxSet mGfx;

        ConfigNode mGameConf;

        WindyForce mWindForce;
        PhysicTimedChangerFloat mWindChanger;

        //for raising waterline
        PhysicTimedChangerFloat mWaterChanger;
        //current water level, now in absolute scene coordinates, no more dupes
        float mCurrentWaterLevel;

        //generates earthquakes
        EarthQuakeForce mEarthquakeForceVis, mEarthquakeForceDmg;

        Sprite[] mPlaceQueue;

        const cWindChange = 80.0f;
        const cMaxWind = 150f;

        const cWaterRaisingSpeed = 50.0f; //pixels per second

        //minimum distance between placed objects
        const cPlaceMinDistance = 50.0f;
        //position increment for deterministic placement
        const cPlaceIncDistance = 55.0f;
        //distance when creating a platform in empty space
        const cPlacePlatformDistance = 90.0f;
    }

    class DrawParticles : SceneObject {
        override void draw(Canvas canvas) {
            //update state
            //engine.windSpeed is -1..1, don't ask me why
            particleWorld.windSpeed = windSpeed()*150f;
            particleWorld.waterLine = waterOffset();
            //simulate & draw
            particleWorld.draw(canvas);
        }
    }

    //config- and gametype-independant initialization
    //(stuff that every possible game always needs)
    this(GameConfig a_config, TimeSourcePublic a_gameTime,
        TimeSourcePublic a_interpolateTime)
    {
        super(a_config, a_gameTime, a_interpolateTime);

        scripting.addSingleton(this);


        mGameConf = loadConfig("game");

        physicWorld.gravity = Vector2f(0, mGameConf.getFloatValue("gravity",
            100));
        //hm!?!?
        physicWorld.onCollide = &onPhysicHit;

        SceneObject particles = new DrawParticles();
        particles.zorder = GameZOrder.Particles;
        scene.add(particles);

        //scripting initialization
        //code loaded here can be considered "internal" and should explode
        //  on errors
        scripting.onError = &scriptingObjError;

        events.setScripting(scripting);

        foreach (char[] name, char[] value; mGameConf.getSubNode("scripts")) {
            loadScript(value);
        }
    }

    //wrapper for the cast to make it easier to search for all occurrences where
    //  going from GameCore -> GameEngine was needed
    static GameEngine fromCore(GameCore core) {
        return castStrict!(GameEngine)(core);
    }

    void initGame() {
        auto config = gameConfig;

        //game initialization must be deterministic; so unless GameConfig
        //contains a good pre-generated seed, use a fixed seed (see above)
        if (config.randomSeed.length > 0) {
            rnd.seed(to!(uint)(config.randomSeed));
        }

        persistentState = config.gamestate.copy();

        assert(config.level !is null);
        assert(level is config.level);

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
        wb.collision = physicWorld.collide.findCollisionID("water");
        physicWorld.add(wb);
        mWaterBouncer = new WaterSurfaceGeometry();
        physicWorld.add(mWaterBouncer);
        //Stokes's drag force
        physicWorld.add(new ForceZone(new StokesDragFixed(5.0f), mWaterBorder));
        //xxx additional object-attribute controlled Stokes's drag
        physicWorld.add(new StokesDragObject());
        //Earthquake generator
        mEarthquakeForceVis = new EarthQuakeForce(false);
        mEarthquakeForceDmg = new EarthQuakeForce(true);
        physicWorld.add(mEarthquakeForceVis);
        physicWorld.add(mEarthquakeForceDmg);

        auto deathrc = toRect2f(level.worldBounds());
        auto sz = deathrc.size;
        //make rect much bigger in all three directions except downwards, so
        //  that the deathzone normally is not noticed (e.g. objects still can
        //  fly a long time, even if outside of the screen/level)
        deathrc.p1.x -= sz.x;
        deathrc.p2.x += sz.x;
        deathrc.p1.y -= sz.y;
        //downwards, objects should die immediately ("sea bottom")
        //the trigger is inverse, and triggers only when the physic object is
        //completely in the deathzone, but graphics are often larger :(
        deathrc.p2.y += 20;
        auto dz = new ZoneTrigger(new PhysicZoneRect(deathrc));
        dz.collision = physicWorld.collide.findCollisionID("always");
        dz.onTrigger = &deathzoneTrigger;
        dz.inverse = true;
        physicWorld.add(dz);

        //create trigger to check for objects leaving the playable area
        //xxx this can go into the controller; it is only needed to take control
        //  of worms that leave the level
        auto worldZone = new PhysicZoneXRange(0, level.worldSize.x);
        //only if completely outside (= touching the game area inverted)
        worldZone.whenTouched = true;
        auto offwTrigger = new ZoneTrigger(worldZone);
        offwTrigger.collision = physicWorld.collide.findCollisionID("always");
        offwTrigger.inverse = true;  //trigger when outside the world area
        offwTrigger.onTrigger = &offworldTrigger;
        physicWorld.add(offwTrigger);

        mWindForce = new WindyForce();
        mWindChanger = new PhysicTimedChangerFloat(0, &windChangerUpdate);
        mWindChanger.changePerSec = cWindChange;
        physicWorld.add(new ForceZone(mWindForce, mWaterBorder, true));
        physicWorld.add(mWindChanger);
        randomizeWind();

        //physics timed changer for water offset
        mWaterChanger = new PhysicTimedChangerFloat(level.waterBottomY,
            &waterChangerUpdate);
        mWaterChanger.changePerSec = cWaterRaisingSpeed;
        physicWorld.add(mWaterChanger);

        //initialize loaded plugins
        OnGameInit.raise(events);
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

    private void windChangerUpdate(float val) {
        mWindForce.windSpeed = Vector2f(val,0);
    }

    private void waterChangerUpdate(float val) {
        mCurrentWaterLevel = val;
        mWaterBorder.plane.define(Vector2f(0, val), Vector2f(1, val));
        //why -5? a) it looks better, b) objects won't drown accidentally
        mWaterBouncer.updatePos(val - 5);
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
        auto x = cast(Sprite)(other.backlink);
        if (x) x.setIsUnderWater();
    }

    private void deathzoneTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(Sprite)(other.backlink);
        if (x) x.exterminate();
    }

    private void offworldTrigger(PhysicTrigger sender, PhysicObject other) {
        auto x = cast(Sprite)(other.backlink);
        if (x && onOffworld) {
            onOffworld(x);
        }
    }

    //wind speeds are in [-1.0, 1.0]
    void setWindSpeed(float speed) {
        mWindChanger.target = clampRangeC(speed, -1.0f, 1.0f)*cMaxWind;
    }
    void randomizeWind() {
        mWindChanger.target = cMaxWind*rnd.nextDouble3();
    }

    void raiseWater(int by) {
        //argh why is mCurrentWaterLevel a float??
        int t = cast(int)mCurrentWaterLevel - by;
        t = max(t, level.waterTopY); //don't grow beyond limit?
        mWaterChanger.target = t;
    }

    //strength = force, duration = absolute time,
    //  degrade = true for exponential degrade
    //this function never overwrites the settings, but adds both values to the
    //existing ones
    void addEarthQuake(float strength, Time duration, bool degrade = true,
        bool bounceObjects = false)
    {
        auto ef = mEarthquakeForceVis;
        if (bounceObjects)
            ef = mEarthquakeForceDmg;
        physicWorld.add(new EarthQuakeDegrader(strength, duration, degrade,
            ef));
        log("created earth quake, strength={}, duration={}, degrade={}",
            strength, duration, degrade);
    }

    Rect2f placementArea() {
        //xxx: there's also mLevel.landBounds, which does almost the same
        //  correct way of doing this would be to include all objects on that
        //  worms can stand/sit
        //this code also seems to assume that the landscape is in the middle,
        //  which is ok most time
        auto mid = toVector2f(level.worldSize)/2;
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

        Rect2f area = Rect2f(0, 0, level.worldSize.x, y_max);
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
        foreach (GameObject o; mAllObjects) {
            auto s = cast(Sprite)o;
            if (s && s.visible) {
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

        Contact contact;
        //check if origin point is inside geometry
        if (physicWorld.collideGeometry(drop, radius, contact))
            return false;
        //cast a ray downwards from drop
        if (!physicWorld.thickRay(drop, Vector2f(0, 1), area.p2.y - drop.y,
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
            //fucking code duplication
            foreach (GameObject o; mAllObjects) {
                auto s = cast(Sprite)o;
                if (s && s.visible) {
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
                    error("couldn't place '{}'!", sprite);
                    //xxx
                    npos = toVector2f(level.worldSize)/2;
                }
            }
            log("placed '{}' at {}", sprite.type.name, npos);
            sprite.activate(npos);
        }
        mPlaceQueue = null;
    }

    //non-deterministic
    private void showExplosion(Vector2f at, int radius) {
        if (!mGfx)
            mGfx = singleton!(GfxSet)();
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
            particleWorld.emitParticle(at, Vector2f(0), t);
        }

        if (s >= 0) {
            //shockwave
            emit(mGfx.expl.shockwave1[s]);
            emit(mGfx.expl.shockwave2[s]);
            //flaming sparks
            //in WWP, those use a random animation speed
            for (int i = 0; i < rngShared.nextRange(2, 3); i++) {
                particleWorld.emitParticle(at, Vector2f(0, -1)
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
                particleWorld.emitParticle(at + Vector2f(0, -1)
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

    private void applyExplosion(PhysicObject o, Vector2f pos, float damage,
        Object cause = null)
    {
        const cDistDelta = 0.01f;

        assert(damage != 0f && !ieee.isNaN(damage));

        float radius = damage * cDamageToRadius;
        float impulse = damage * cDamageToImpulse;
        Vector2f v = (pos-o.pos);
        float dist = v.length;
        if (dist > cDistDelta) {
            float r = max(radius-dist, 0f)/radius;
            if (r < float.epsilon)
                return;
            o.applyDamage(r*damage, DamageCause.explosion, cause);
            o.addImpulse(-v.normal()*impulse*r*o.posp.explosionInfluence);
        } else {
            //unglue objects at center of explosion
            o.doUnglue();
        }
    }

    override void explosionAt(Vector2f pos, float damage, GameObject cause,
        bool effect = true, bool damage_landscape = true,
        bool delegate(PhysicObject) selective = null)
    {
        if (damage < float.epsilon)
            return;
        //apply double damage; this is probably close to what d0c thinks what
        //  the "right thing" is: only weapons fired by a worm who has collected
        //  a double damage crate cause double damage
        //in my opinion, a global double damage flag would be enough...
        if (auto actor = actorFromGameObject(cause)) {
            damage *= actor.damage_multiplier;
        }
        //radius of explosion influence
        float radius = cDamageToRadius * damage;
        //radius of landscape damage and effect
        auto iradius = cast(int)((radius+0.5f)/2.0f);
        if (damage_landscape)
            damageLandscape(toVector2i(pos), iradius, cause);
        physicWorld.objectsAt(pos, radius, (PhysicObject o) {
            if (selective && !selective(o)) {
                return true;
            }
            applyExplosion(o, pos, damage);
            return true;
        });
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
        //count was used for statistics
    }

    //insert bitmap into the landscape
    void insertIntoLandscape(Vector2i pos, Surface bitmap, Lexel bits) {
        argcheck(bitmap);
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
    override bool checkForActivity() {
        bool quake = earthQuakeStrength() > 0;
        if (quake)
            return true;
        if (!mWaterChanger.done)
            return true;
        return super.checkForActivity();
    }

    //count sprites with passed spriteclass name currently in the game
    int countSprites(char[] name) {
        auto sc = resources.get!(SpriteClass)(name, true);
        if (!sc)
            return 0;
        int ret = 0;
        foreach (GameObject o; mAllObjects) {
            auto s = cast(Sprite)o;
            if (s && s.visible) {
                if (s.type == sc)
                    ret++;
            }
        }
        return ret;
    }
}
