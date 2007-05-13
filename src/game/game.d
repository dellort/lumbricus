module game.game;
import level.level;
import game.scene;
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
    }

    //remove all objects etc. from the scene
    void kill() {
        levelobject.active = false;
    }
}

class LevelObject : SceneObject {
    GameController game;
    Level level;

    void draw(Canvas c) {
        c.draw(level.image, Vector2i(0, 0));
    }

    this(GameController game) {
        this.game = game;
        level = game.level;
    }
}
