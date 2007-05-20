module game.game;
import levelgen.level;
import game.scene;
import game.gobject;
import game.physic;
import game.glevel;
import game.water;
import game.sky;
import utils.mylist;
import utils.time;
import utils.log;
import framework.framework;

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
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
    GameWater mGameWater;
    GameSky mGameSky;

    Vector2i tmp;

    package List!(GameObject) mObjects;

    private const cSpaceBelowLevel = 80;
    private const cSpaceAboveOpenLevel = 10;//00;
    private const cOpenLevelWidthMultiplier = 3;

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

        auto grav = new ConstantForce();
        grav.force = Vector2f(0, 10); //what unit is that???
        physicworld.add(grav);

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        mGameWater = new GameWater(this, "blue");
        mGameSky = new GameSky(this);
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
}

class LevelObject : SceneObject {
    GameController game;
    GameLevel gamelevel;
    Texture levelTexture;

    void draw(Canvas c) {
        if (!levelTexture) {
            levelTexture = gamelevel.image.createTexture();
        }
        c.draw(levelTexture, gamelevel.offset);
        Vector2i dir; int pixelcount;
        auto pos = game.tmp;
        auto npos = toVector2f(pos);
        if (gamelevel.physics.collide(npos, 100)) {
            c.drawCircle(pos, 100, Color(0,1,0));
            c.drawCircle(toVector2i(npos), 100, Color(1,1,0));
        }
        //xxx draw debug stuff for physics!
        foreach (PhysicObject o; game.physicworld.mObjects) {
            c.drawCircle(toVector2i(o.pos), cast(int)o.radius, Color(1,1,1));
        }
    }

    this(GameController game) {
        this.game = game;
        gamelevel = game.gamelevel;
    }
}
