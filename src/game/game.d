module game.game;
import levelgen.level;
import game.scene;
import game.gobject;
import game.physic;
import game.glevel;
import utils.mylist;
import utils.time;
import utils.log;
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
    GameLevel gamelevel;
    Scene scene;
    PhysicWorld physicworld;
    Time currentTime;

    Vector2i tmp;

    package List!(GameObject) mObjects;

    this(Scene gamescene, Level level) {
        assert(gamescene !is null);
        assert(level !is null);
        scene = gamescene;
        this.level = level;
        levelobject = new LevelObject(this);
        levelobject.setScene(scene, GameZOrder.Level);

        gamelevel = new GameLevel(level, Vector2i(0, 0));

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
        Vector2i n = game.gamelevel.normalAt(game.tmp, 10);
        Vector2f nf = toVector2f(n).normal*100;

        c.drawLine(game.tmp, game.tmp +toVector2i(nf), Color(1,0,0));
    }

    this(GameController game) {
        this.game = game;
        level = game.level;
    }
}
