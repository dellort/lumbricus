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
    FrontWater,  //water before the level
    FrontWaterWaves1,
    FrontWaterWaves2,
    FrontWaterWaves3,
}

struct GameConfig {
    Level level;
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameController {
    Level level;
    LevelObject levelobject;
    GameLevel gamelevel;
    Scene scene;
    PhysicWorld physicworld;
    Time currentTime;
    GameWater gameWater;
    GameSky gameSky;

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

    //managment of sprite classes, for findGOSpriteClass()
    private GOSpriteClass[char[]] mSpriteClasses;

    Vector2i tmp;
    EventSink events;

    Worm lastworm;

    package List!(GameObject) mObjects;

    private const cSpaceBelowLevel = 80;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private ConstantForce mGravForce;
    private WindyForce mWindForce;
    private float mWindTarget;
    private const cWindChange = 80.0f;

    private Time mLastTime;

    this(Scene gamescene, GameConfig config) {
        assert(gamescene !is null);
        assert(config.level !is null);
        scene = gamescene;
        this.level = config.level;

        mLog = registerLog("gamecontroller");

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
        gamescene.thesize = worldSize;

        physicworld = new PhysicWorld();

        //to enable level-bitmap collision
        physicworld.add(gamelevel.physics);
        //various level borders; for now, simply box it
        //water border
        physicworld.add(new PlaneGeometry(toVector2f(levelOffset+worldSize),
            toVector2f(levelOffset+worldSize) + Vector2f(1,0)));

        mGravForce = new ConstantForce();
        mGravForce.accel = Vector2f(0, 100); //what unit is that???
        physicworld.add(mGravForce);

        mWindForce = new WindyForce();
        physicworld.add(mWindForce);
        mWindTarget = -150;   //what unit is that???

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        gameWater = new GameWater(this, "blue");
        gameSky = new GameSky(this);

        events = levelobject.getEventSink();
        events.onMouseMove = &onMouseMove;
        events.onKeyDown = &onKeyDown;
        events.onKeyUp = &onKeyUp;

        loadLevelStuff();
    }

    //one time initialization, where levle objects etc. should be loaded (?)
    private void loadLevelStuff() {
        auto conf = globals.loadConfig("game");
        //load sprites
        foreach (char[] name, char[] value; conf.getSubNode("sprites")) {
            auto n = new GOSpriteClass(this, globals.loadConfig(value));
            mSpriteClasses[name] = n;
        }
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

    bool onMouseMove(EventSink sender, MouseInfo info) {
        tmp = info.pos;
        return true;
    }

    //key state for LEFT/RIGHT and UP/DOWN
    Vector2f dirKeyState = {0, 0};

    void handleDirKey(Keycode c, bool up) {
        float v = up ? 0 : 1;
        switch (c) {
            case Keycode.LEFT:
                dirKeyState.x = -v;
                break;
            case Keycode.RIGHT:
                dirKeyState.x = +v;
                break;
            case Keycode.UP:
                dirKeyState.y = -v;
                break;
            case Keycode.DOWN:
                dirKeyState.y = +v;
                break;
            default:
                return;
        }

        //control the worm (better only on state change)
        lastworm.move(dirKeyState);
    }

    bool onKeyDown(EventSink sender, KeyInfo info) {
        if (info.code == Keycode.MOUSE_LEFT) {
            gamelevel.damage(sender.mousePos, 100);
        }
        if (lastworm) {
            handleDirKey(info.code, false);
            if (info.code == Keycode.RETURN) {
                lastworm.jump();
            } else if (info.code == Keycode.J) {
                //jetpack
                lastworm.activateJetpack(!lastworm.jetpackActivated);
            } else if (info.code == Keycode.W) {
                lastworm.drawWeapon(!lastworm.weaponDrawn);
            } else if (info.code == Keycode.SPACE) {
                lastworm.fireWeapon();
            }
        }
        return true;
    }

    bool onKeyUp(EventSink sender, KeyInfo info) {
        if (lastworm) {
            handleDirKey(info.code, true);
        }
        return false;
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        float deltaT = (currentTime - mLastTime).msecs/1000.0f;
        if (abs(mWindTarget - mWindForce.accel.x) > 0.5f) {
            mWindForce.accel.x += copysign(cWindChange*deltaT,mWindTarget - mWindForce.accel.x);
        }
        physicworld.simulate(currentTime);
        //update game objects
        foreach (GameObject o; mObjects) {
            o.simulate(deltaT);
        }
        mLastTime = currentTime;
    }

    //remove all objects etc. from the scene
    void kill() {
        levelobject.active = false;
        foreach (GameObject o; mObjects) {
            o.kill();
        }
    }

    //stupid debugging code
    void spawnWorm() {
        auto obj = new Worm(this);
        obj.setPos(toVector2f(tmp));
        lastworm = obj;
    }

    //try to place an object into the landscape
    //essentially finds the first collision under "drop" and checks the normal
    //success only when only the LevelGeometry object is hit
    //  drop = any startpoint
    //  dest = where it is dropped (will have same x value)
    //returns if dest contains a useful value
    bool placeObject(inout Vector2i drop, out Vector2i dest, int radius) {
        assert(false);
    }

    //places an object at a random (x,y)-position, where y <= y_max
    //use y_max to prevent placement under the water, or to start dopping from
    //the sky (instead of anywhere)
    //  retrycount = times it tries again until it gives up
    bool placeObject(int y_max, int retrycount, out Vector2i drop,
        out Vector2i dest, int radius)
    {
        //clip y_max to level borders
        y_max = max(y_max, gamelevel.offset.y);
        y_max = min(y_max, gamelevel.offset.y + cast(int)gamelevel.height);
        for (;retrycount > 0; retrycount--) {
            drop.x = randRange(gamelevel.offset.y, y_max);
            drop.y = randRange(gamelevel.offset.x, gamelevel.offset.x
                + cast(int)gamelevel.width);
            if (placeObject(drop, dest, radius))
                return true;
        }
        return false;
    }

    //load animations as requested in "item"
    //currently, item shall be a ConfigValue which contains the configfile name
    //note that this name shouldn't contains a ".conf", argh.
    void loadAnimations(ConfigItem item) {
        if (!item)
            return;

        auto v = cast(ConfigValue)item;
        assert(v !is null);
        char[] file = v.value;
        if (file in mLoadedAnimationConfigFiles)
            return;

        mLoadedAnimationConfigFiles[file] = true;
        auto cfg = globals.loadConfig(file);
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

    GOSpriteClass findGOSpriteClass(char[] name) {
        GOSpriteClass* gosc = name in mSpriteClasses;
        if (gosc)
            return *gosc;

        //not found? xxx better error handling (as usual...)
        throw new Exception("sprite class " ~ name ~ " not found");
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
    GameController game;
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

    this(GameController game) {
        this.game = game;
        gamelevel = game.gamelevel;
    }
}
