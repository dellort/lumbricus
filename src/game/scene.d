module game.scene;
import framework.framework;
import utils.mylist;
import framework.font;

//a scene contains all graphics drawn onto the screen
//each graphic is represented by a SceneObject
class Scene {
    alias List!(SceneObject) SOList;
    private SOList mActiveObjects;
    Vector2i thesize;

    //zorder values from 0 to cMaxZorder, last inclusive
    //NOTE: zorder allocation is in common.d
    //zorder 0 isn't drawn at all
    public final const cMaxZOrder = 15;

    private SOList[cMaxZOrder] mActiveObjectsZOrdered;

    this() {
        mActiveObjects = new SOList(SceneObject.allobjects.getListNodeOffset());
        foreach (inout list; mActiveObjectsZOrdered) {
            list = new SOList(SceneObject.zorderlist.getListNodeOffset());
        }
    }
}

//over engineered for sure!
/// Provide a graphical windowed view into a (client-) scene.
/// Various transformations can be applied on the client view (currently only
/// translation, with OpenGL maybe also scaling and rotation)
class SceneView : SceneObjectPositioned {
    private Scene mClientScene;
    private Vector2i mClientoffset;
    private Vector2i mSceneSize;

    this(Scene clientscene) {
        assert(clientscene !is null);
        mClientScene = clientscene;
        mClientoffset = Vector2i(0, 0);
        mSceneSize = mClientScene.thesize;
    }

    void draw(Canvas canvas) {
        if (mSceneSize != mClientScene.thesize) {
            //scene size has changed
            clipOffset(mClientoffset);
            mSceneSize = mClientScene.thesize;
        }
        canvas.pushState();
        canvas.setWindow(pos, pos+thesize);
        canvas.translate(-clientoffset);

        foreach (list; mClientScene.mActiveObjectsZOrdered[1..$]) {
            foreach (obj; list) {
                obj.draw(canvas);
            }
        }

        canvas.popState();
    }

    Vector2i clientoffset() {
        return mClientoffset;
    }
    void clientoffset(Vector2i newOffs) {
        mClientoffset = newOffs;
        clipOffset(mClientoffset);
    }

    public void clipOffset(inout Vector2i offs) {
        if (thesize.x < mClientScene.thesize.x) {
            //view window is smaller than scene (x-dir)
            //-> don't allow black borders
            if (offs.x > 0)
                offs.x = 0;
            if (offs.x + mClientScene.thesize.x < thesize.x)
                offs.x = thesize.x - mClientScene.thesize.x;
        } else {
            //view is larger than scene -> black borders, but don't allow
            //parts of the scene to go out of view
            if (offs.x < 0)
                offs.x = 0;
            if (offs.x + mClientScene.thesize.x > thesize.x)
                offs.x = thesize.x - mClientScene.thesize.x;
        }

        //same for y
        if (thesize.y < mClientScene.thesize.y) {
            if (offs.y > 0)
                offs.y = 0;
            if (offs.y + mClientScene.thesize.y < thesize.y)
                offs.y = thesize.y - mClientScene.thesize.y;
        } else {
            if (offs.y < 0)
                offs.y = 0;
            if (offs.y + mClientScene.thesize.y > thesize.y)
                offs.y = thesize.y - mClientScene.thesize.y;
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
        mRootScene.thesize = size;
        mRootView = new SceneView(mRootScene);
        //NOTE: normally SceneViews are elements in a further Scene, but here
        //      Screen is the container of the SceneView mRootView
        //      damn overengineered madness!
        mRootView.pos = Vector2i(0, 0);
        mRootView.thesize = size;
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

    public Scene scene() {
        return mScene;
    }

    public void scene(Scene scene) {
        if (scene is mScene)
            return;

        //remove
        active = false;
        mScene = null;

        if (scene) {
            //add
            bool tmp = active;
            active = false;
            mScene = scene;
            active = tmp;
        }
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

    public bool active() {
        return mActive;
    }

    public void active(bool set) {
        if (set == mActive)
            return;

        if (!mScene) {
            mActive = false;
            return;
        }

        if (set) {
            mScene.mActiveObjectsZOrdered[mZOrder].insert_head(this);
            mScene.mActiveObjects.insert_head(this);
        } else {
            mScene.mActiveObjectsZOrdered[mZOrder].remove(this);
            mScene.mActiveObjects.remove(this);
        }

        mActive = set;
    }

    public void setScene(Scene s, int z) {
        scene = s;
        zorder = z;
        active = true;
    }

    abstract void draw(Canvas canvas);
}

class CallbackSceneObject : SceneObject {
    public void delegate(Canvas canvas) onDraw;

    void draw(Canvas canvas) {
        if (onDraw) onDraw(canvas);
    }
}

//with a rectangular bounding box??
class SceneObjectPositioned : SceneObject {
    Vector2i pos;
    Vector2i thesize;
}

class FontLabel : SceneObjectPositioned {
    char[] text;
    Font font;

    this(Font font) {
        this.font = font;
    }

    void draw(Canvas canvas) {
        font.drawText(canvas, pos, text);
    }
}
