module game.game;
import levelgen.level;
import game.scene;
import game.gobject;
import game.physic;
import game.glevel;
import game.worm;
import game.water;
import game.sky;
import utils.mylist;
import utils.time;
import utils.log;
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

    Vector2i tmp;
    EventSink events;

    Worm lastworm;

    package List!(GameObject) mObjects;

    private const cSpaceBelowLevel = 80;
    private const cSpaceAboveOpenLevel = 1000;
    private const cOpenLevelWidthMultiplier = 3;

    private ConstantForce mGravForce;
    private WindyForce mWindForce;

    this(Scene gamescene, Level level) {
        assert(gamescene !is null);
        assert(level !is null);
        scene = gamescene;
        this.level = level;

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
        mWindForce.accel = Vector2f(150, 0); //what unit is that???
        physicworld.add(mWindForce);

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        gameWater = new GameWater(this, "blue");
        gameSky = new GameSky(this);

        events = levelobject.getEventSink();
        events.onMouseMove = &onMouseMove;
        events.onKeyDown = &onKeyDown;
        events.onKeyUp = &onKeyUp;
    }

    public float windSpeed() {
        return mWindForce.accel.x;
    }
    public void windSpeed(float speed) {
        mWindForce.accel.x = speed;
    }

    public float gravity() {
        return mGravForce.accel.y;
    }

    bool onMouseMove(EventSink sender, MouseInfo info) {
        tmp = info.pos;
        return true;
    }

    bool onKeyDown(EventSink sender, KeyInfo info) {
        if (info.code == Keycode.MOUSE_LEFT) {
            gamelevel.damage(sender.mousePos, 100);
        }
        if (lastworm) {
            if (info.code == Keycode.LEFT) {
                lastworm.physics.setWalking(Vector2f(-1, 0));
                registerLog("xxx")("walk left");
            } else if (info.code == Keycode.RIGHT) {
                lastworm.physics.setWalking(Vector2f(+1, 0));
                registerLog("xxx")("walk right");
            }
        }
        return true;
    }

    bool onKeyUp(EventSink sender, KeyInfo info) {
        if (info.code == Keycode.LEFT || info.code == Keycode.RIGHT) {
            lastworm.physics.setWalking(Vector2f(0));
        }
        return false;
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        physicworld.simulate(currentTime);
        //update game objects
        foreach (GameObject o; mObjects) {
            o.simulate(currentTime);
        }
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
        obj.setPos(tmp);
        lastworm = obj;
    }
}

class LevelObject : SceneObject {
    GameController game;
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
            auto angle = o.rotation;
            //auto angle = o.ground_angle;
            c.drawCircle(toVector2i(o.pos), cast(int)o.radius, Color(1,1,1));
            auto p = Vector2f.fromPolar(40, angle) + o.pos;
            c.drawCircle(toVector2i(p), 5, Color(1,1,0));
        }
        //more debug stuff...
        foreach (GameObject go; game.mObjects) {
            if (cast(Worm)go) {
                auto w = cast(Worm)go;
                auto p = Vector2f.fromPolar(40, w.angle) + w.physics.pos;
                c.drawCircle(toVector2i(p), 5, Color(1,0,1));
            }
        }
    }

    this(GameController game) {
        this.game = game;
        gamelevel = game.gamelevel;
    }
}
