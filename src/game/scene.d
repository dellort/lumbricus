module game.scene;
import framework.framework;
import utils.mylist;
import framework.font;

//a scene contains all graphics drawn onto the screen
//each graphic is represented by a SceneObject
class Scene {
    alias List!(SceneObject) SOList;
    private SOList mActiveObjects;

    //zorder values from 0 to cMaxZorder, last inclusive
    //NOTE: zorder allocation is in common.d
    //zorder 0 isn't drawn at all
    public final const cMaxZOrder = 10;

    private SOList[cMaxZOrder] mActiveObjectsZOrdered;

    this() {
        mActiveObjects = new SOList(SceneObject.allobjects.getListNodeOffset());
        foreach (inout list; mActiveObjectsZOrdered) {
            list = new SOList(SceneObject.zorderlist.getListNodeOffset());
        }
    }
}

//over engineered for sure!
class SceneView : SceneObjectPositioned {
    this(Scene scene) {
        super(scene);
    }

    void draw(Canvas canvas) {
        //xxx: translate and add clipping!!!!
        foreach (list; mScene.mActiveObjectsZOrdered[1..$]) {
            foreach (obj; list) {
                obj.draw(canvas);
            }
        }
    }
}

//(should be a) singleton!
class Screen {
    private Scene mRootScene;
    private SceneView mRootView;

    Scene rootscene() {
        return mRootScene;
    }

    this(Vector2i size) {
        mRootScene = new Scene();
        mRootView = new SceneView(mRootScene);
        mRootView.pos = Vector2i(0, 0);
        mRootView.size = size;
    }

    void draw(Canvas canvas) {
        mRootView.draw(canvas);
    }
}

class SceneObject {
    mixin ListNodeMixin allobjects;
    mixin ListNodeMixin zorderlist;

    private Scene mScene;
    private int mZOrder;
    private bool mActive;

    this(Scene owner) {
        mScene = owner;
    }

    public int zorder() {
        return mZOrder;
    }
    public void zorder(int z) {
        assert (z >= 0 && z <= Scene.cMaxZOrder);

        if (mActive) {
            mScene.mActiveObjectsZOrdered[mZOrder].remove(this);
            mScene.mActiveObjectsZOrdered[z].insert_head(this);
        }

        mZOrder = z;
    }

    public void active(bool set) {
        if (set == mActive)
            return;

        if (set) {
            mScene.mActiveObjectsZOrdered[mZOrder].insert_head(this);
            mScene.mActiveObjects.insert_head(this);
        } else {
            mScene.mActiveObjectsZOrdered[mZOrder].remove(this);
            mScene.mActiveObjects.remove(this);
        }

        mActive = set;
    }

    abstract void draw(Canvas canvas);
}

//with a rectangular bounding box??
class SceneObjectPositioned : SceneObject {
    Vector2i pos;
    Vector2i size;

    this(Scene s) {
        super(s);
    }
}

class FontLabel : SceneObjectPositioned {
    char[] text;
    Font font;

    this(Scene s, Font font) {
        super(s);
        this.font = font;
    }

    void draw(Canvas canvas) {
        font.drawText(canvas, pos, text);
    }
}
