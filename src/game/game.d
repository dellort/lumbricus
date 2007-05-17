module game.game;
import levelgen.level;
import game.scene;
import game.gobject;
import game.physic;
import game.glevel;
import game.water;
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

    Vector2i tmp;

    package List!(GameObject) mObjects;

    private const cSpaceBelowLevel = 80;
    private const cSpaceAboveOpenLevel = 1000;
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

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());

        mGameWater = new GameWater(this, "blue");
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
        Vector2i n = gamelevel.normalAt(game.tmp, 10);
        Vector2f nf = toVector2f(n).normal*100;

        c.drawLine(game.tmp, game.tmp +toVector2i(nf), Color(1,0,0));
    }

    this(GameController game) {
        this.game = game;
        gamelevel = game.gamelevel;
    }
}
