module game.scene;
import framework.framework;
import utils.mylist;
import framework.font;

//a scene contains all graphics drawn onto the screen
//each graphic is represented by a SceneObject
class Scene {
    alias List!(SceneObject) SOList;
    private SOList mActiveObjects;
    //all objects that want to receive events
    private SceneObject[SceneObject] mEventReceiver;
    Vector2i thesize;

    //zorder values from 0 to cMaxZorder, last inclusive
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

class EventSink {
    bool delegate(EventSink sender, KeyInfo key) onKeyDown;
    bool delegate(EventSink sender, KeyInfo key) onKeyUp;
    bool delegate(EventSink sender, KeyInfo key) onKeyPress;
    bool delegate(EventSink sender, MouseInfo mouse) onMouseMove;

    private enum KeyEvent {
        Down,
        Up,
        Press
    }

    private Vector2i mMousePos;  //see mousePos()
    private SceneObject mObject; //(mObject.getEventSink() is this) == true

    //last known mouse position, that is inside this "window"
    Vector2i mousePos() {
        return mMousePos;
    }

    private bool callKeyHandler(KeyEvent type, KeyInfo info) {
        switch (type) {
            case KeyEvent.Down: return onKeyDown ? onKeyDown(this, info) : false;
            case KeyEvent.Up: return onKeyUp ? onKeyUp(this, info) : false;
            case KeyEvent.Press: return onKeyPress ? onKeyPress(this, info) : false;
            default: assert(false);
        }
    }

    private void callMouseHandler(MouseInfo info) {
        mMousePos = info.pos;
        if (onMouseMove)
            onMouseMove(this, info);
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

    this() {
        //always create event handler
        getEventSink();
    }

    void clientscene(Scene scene) {
        mClientScene = scene;
        mClientoffset = Vector2i(0, 0);
        mSceneSize = Vector2i(0, 0);
        if (scene) {
            mSceneSize = mClientScene.thesize;
        }
    }

    void draw(Canvas canvas) {
        if (!mClientScene)
            return;

        if (mSceneSize != mClientScene.thesize) {
            //scene size has changed
            clipOffset(mClientoffset);
            mSceneSize = mClientScene.thesize;
        }
        canvas.pushState();
        canvas.setWindow(pos, pos+thesize);
        canvas.translate(-clientoffset);

        //Hint: first element in zorder array is the list of invisible objects
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

    Scene clientscene() {
        return mClientScene;
    }

    //from the parent's coordinate system to the client's
    //(client = mClientScene)
    public Vector2i toClientCoords(Vector2i p) {
        return p - pos - clientoffset;
    }

    public void clipOffset(inout Vector2i offs) {
        if (!mClientScene) {
            offs = Vector2i(0, 0);
            return;
        }

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

    private static bool isInside(SceneObjectPositioned obj, Vector2i pos) {
        return pos.isInside(obj.pos, obj.thesize);
    }

    //event handling
    void doMouseMove(MouseInfo info) {
        info.pos = toClientCoords(info.pos);
        //xxx following line
        getEventSink().mMousePos = info.pos;

        if (!mClientScene)
            return;

        foreach (SceneObject so; mClientScene.mEventReceiver) {
            auto pso = cast(SceneObjectPositioned)so;
            if (!pso) {
                so.getEventSink().callMouseHandler(info);
            } else if (isInside(pso, info.pos)) {
                //deliver
                pso.getEventSink().callMouseHandler(info);
                auto sv = cast(SceneView)pso;
                if (sv) {
                    sv.doMouseMove(info);
                }
            }
        }
    }

    //duplicated from above
    void doMouseButtons(EventSink.KeyEvent ev, KeyInfo info) {
        if (!mClientScene)
            return;

        //last mouse position - should be valid (?)
        auto pos = getEventSink().mousePos;
        foreach (SceneObject so; mClientScene.mEventReceiver) {
            auto pso = cast(SceneObjectPositioned)so;
            if (!pso) {
                so.getEventSink().callKeyHandler(ev, info);
            } else if (isInside(pso, pos)) {
                pso.getEventSink().callKeyHandler(ev, info);
                auto sv = cast(SceneView)pso;
                if (sv) {
                    sv.doMouseButtons(ev, info);
                }
            }
        }
    }
}

//(should be a) singleton!
class Screen {
    private Scene mRootScene;
    private SceneView mRootView;
    private EventSink mFocus;

    Scene rootscene() {
        return mRootScene;
    }

    this(Vector2i size) {
        mRootScene = new Scene();
        mRootScene.thesize = size;
        mRootView = new SceneView();
        mRootView.clientscene = mRootScene;
        //NOTE: normally SceneViews are elements in a further Scene, but here
        //      Screen is the container of the SceneView mRootView
        //      damn overengineered madness!
        mRootView.pos = Vector2i(0, 0);
        mRootView.thesize = size;
    }

    void setSize(Vector2i s) {
        mRootScene.thesize = s;
        mRootView.thesize = s;
    }

    void draw(Canvas canvas) {
        mRootView.draw(canvas);
    }

    void setFocus(SceneObject so) {
        mFocus = so ? so.getEventSink() : null;
    }

    private bool doKeyEvent(EventSink.KeyEvent ev, KeyInfo info) {
        if (info.isMouseButton) {
            mRootView.doMouseButtons(ev, info);
        }
        if (mFocus) {
            return mFocus.callKeyHandler(ev, info);
        }
        return false;
    }
    //distribute events to these EventSink things
    bool putOnKeyDown(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Down, info);
    }
    bool putOnKeyPress(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Press, info);
    }
    bool putOnKeyUp(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Up, info);
    }
    void putOnMouseMove(MouseInfo info) {
        mRootView.doMouseMove(info);
    }
}

class SceneObject {
    mixin ListNodeMixin allobjects;
    mixin ListNodeMixin zorderlist;

    private Scene mScene;
    private int mZOrder;
    private bool mActive;

    private EventSink mEvents;

    //create on demand, since very view SceneObjects want events...
    public EventSink getEventSink() {
        if (!mEvents) {
            bool tmp = active;
            active = false;
            mEvents = new EventSink();
            mEvents.mObject = this;
            active = tmp;
        }
        return mEvents;
    }

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
            if (mEvents) {
                mScene.mEventReceiver[this] = this;
            }
        } else {
            mScene.mActiveObjectsZOrdered[mZOrder].remove(this);
            mScene.mActiveObjects.remove(this);
            if (mEvents) {
                mScene.mEventReceiver.remove(this);
            }
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
