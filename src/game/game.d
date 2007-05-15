module game.game;
import level.level;
import game.scene;
import game.gobject;
import game.physic;
import utils.mylist;
import utils.time;
import framework.framework;

//maybe keep in sync with game.Scene.cMaxZOrder
enum GameZOrder {
    Invisible = 0,
    Background,
    Level,
    Objects,
}

//code to manage a game session (hm, whatever this means)
//reinstantiated on each "round"
class GameController {
    Level level;
    LevelObject levelobject;
    Scene scene;
    PhysicWorld physicworld;
    Time currentTime;

    package List!(GameObject) mObjects;

    this(Scene gamescene, Level level) {
        assert(gamescene !is null);
        assert(level !is null);
        scene = gamescene;
        this.level = level;
        levelobject = new LevelObject(this);
        levelobject.scene = scene;
        levelobject.zorder = GameZOrder.Level;
        levelobject.active = true;

        //prepare the scene
        gamescene.thesize = Vector2i(level.width, level.height);

        physicworld = new PhysicWorld();

        mObjects = new List!(GameObject)(GameObject.node.getListNodeOffset());
    }

    void doFrame(Time gametime) {
        currentTime = gametime;
        physicworld.simulate(currentTime);
    }

    //remove all objects etc. from the scene
    void kill() {
        levelobject.active = false;
    }
}

class LevelObject : SceneObject {
    GameController game;
    Level level;
    Texture levelTexture;

    void draw(Canvas c) {
        if (!levelTexture) {
            levelTexture = level.image.createTexture();
        }
        c.draw(levelTexture, Vector2i(0, 0));
    }

    this(GameController game) {
        this.game = game;
        level = game.level;
    }
}
