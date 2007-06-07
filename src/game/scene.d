module game.scene;

import framework.framework;
import framework.font;
import utils.mylist;
import utils.time;
import utils.vector2;
import utils.rect2;

public import framework.keysyms;
public import framework.framework : KeyInfo, Canvas;

import game.common;

//a scene contains all graphics drawn onto the screen
//each graphic is represented by a SceneObject
class Scene {
    alias List!(SceneObject) SOList;
    private SOList mActiveObjects;
    //all objects that want to receive events
    private SceneObject[SceneObject] mEventReceiver;
    Vector2i size;

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

enum CameraStyle {
    Reset,  //disable camera
    Normal, //camera follows in a non-confusing way
    Center, //follows always centered, cf. super sheep
}

//over engineered for sure!
/// Provide a graphical windowed view into a (client-) scene.
/// Various transformations can be applied on the client view (currently only
/// translation, with OpenGL maybe also scaling and rotation)
class SceneView : SceneObjectPositioned {
    private Scene mClientScene;
    private Vector2i mClientoffset;
    private Vector2i mSceneSize;

    //scrolling stuff
    private long mTimeLast;
    private const float K_SCROLL = 0.01f;
    private Vector2f mScrollDest, mScrollOffset;
    private const cScrollStepMs = 10;
    private const cScrollIdleTimeMs = 2000;
    //"camera"
    private CameraStyle mCameraStyle;
    private SceneObjectPositioned mCameraFollowObject;
    private bool mCameraFollowLock;
    //last time the scene was scrolled by i.e. the mouse
    private long mLastUserScroll;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cCameraScrollBackTimeMs = 1000;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    private const cCameraBorder = 150;

    this() {
        //always create event handler
        getEventSink();
        mTimeLast = globals.framework.getCurrentTime().msecs;
    }

    void clientscene(Scene scene) {
        mClientScene = scene;
        mClientoffset = Vector2i(0, 0);
        mSceneSize = Vector2i(0, 0);
        if (scene) {
            mSceneSize = mClientScene.size;
        }
        scrollReset();
    }

    //--------------------------- Scrolling start -------------------------

    ///Stop all active scrolling and stay at the currently visible position
    public void scrollReset() {
        mScrollOffset = toVector2f(clientoffset);
        mScrollDest = mScrollOffset;
    }

    private void scrollUpdate(Time curTime) {
        long curTimeMs = curTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            clientoffset = toVector2i(mScrollOffset);
        } else {
            mTimeLast = timeCurrentTime().msecs;
        }

        //check for camera
        if (mCameraFollowObject && mCameraFollowObject.active &&
            (curTimeMs - mLastUserScroll > cScrollIdleTimeMs || mCameraFollowLock)) {
            auto pos = mCameraFollowObject.pos + mCameraFollowObject.size/2;
            pos = fromClientCoordsScroll(pos);
            switch (mCameraStyle) {
                case CameraStyle.Normal:
                    auto border = Vector2i(cCameraBorder);
                    Rect2i clip = Rect2i(border, size - border);
                    if (!clip.isInsideB(pos)) {
                        auto npos = clip.clip(pos);
                        scrollDoMove(pos-npos);
                    }
                    break;
                case CameraStyle.Center:
                    auto posCenter = size/2;
                    scrollDoMove(pos-posCenter);
                    break;
                case CameraStyle.Reset:
                    //nop
                    break;
            }
        }
    }

    ///call this when the user moves the mouse to scroll by delta
    ///idle time will be reset
    public void scrollMove(Vector2i delta) {
        mLastUserScroll = timeCurrentTime().msecs;
        scrollDoMove(delta);
    }

    ///internal method that will move the camera by delta without affecting
    ///idle time
    private void scrollDoMove(Vector2i delta) {
        mScrollDest = mScrollDest - toVector2f(delta);
        clipOffset(mScrollDest);
    }

    ///One-time center the camera on scenePos
    public void scrollCenterOn(Vector2i scenePos, bool instantly = false) {
        mScrollDest = -toVector2f(scenePos - size/2);
        clipOffset(mScrollDest);
        mTimeLast = timeCurrentTime().msecs;
        if (instantly) {
            mScrollOffset = mScrollDest;
            clientoffset = toVector2i(mScrollOffset);
        }
    }

    ///One-time center the camera on obj
    public void scrollCenterOn(SceneObjectPositioned obj,
        bool instantly = false)
    {
        scrollCenterOn(obj.pos, instantly);
    }

    ///Set the active object the camera should follow
    ///Params:
    ///  lock = set to true to prevent user scrolling
    ///  resetIdleTime = set to true to start the cam movement immediately
    ///                  without waiting for user idle
    public void setCameraFocus(SceneObjectPositioned obj, CameraStyle cs
         = CameraStyle.Normal, bool lock = false, bool resetIdleTime = false)
    {
        if (!obj)
            cs = CameraStyle.Reset;
        mCameraFollowObject = obj;
        mCameraStyle = cs;
        mCameraFollowLock = lock;
        if (resetIdleTime)
            mLastUserScroll = 0;
    }

    //--------------------------- Scrolling end ---------------------------

    void draw(Canvas canvas, SceneView parentView) {
        if (!mClientScene)
            return;

        if (mSceneSize != mClientScene.size) {
            //scene size has changed
            clipOffset(mClientoffset);
            mSceneSize = mClientScene.size;
        }

        scrollUpdate(globals.framework.getCurrentTime());

        canvas.pushState();
        canvas.setWindow(pos, pos+size);
        canvas.translate(-clientoffset);

        //Hint: first element in zorder array is the list of invisible objects
        foreach (list; mClientScene.mActiveObjectsZOrdered[1..$]) {
            foreach (obj; list) {
                obj.draw(canvas, this);
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
        return p - (pos + clientoffset);
    }
    //toClientCoords(fromClientCoords(x)) == x
    public Vector2i fromClientCoords(Vector2i p) {
        return p + (pos + clientoffset);
    }
    //same as fromClientCoords, but uses current scroll destination instead
    //of actual position
    public Vector2i fromClientCoordsScroll(Vector2i p) {
        return p + (pos + toVector2i(mScrollDest));
    }

    public void clipOffset(inout Vector2i offs) {
        Vector2f tmp = toVector2f(offs);
        clipOffset(tmp);
        offs = toVector2i(tmp);
    }

    public void clipOffset(inout Vector2f offs) {
        if (!mClientScene) {
            offs = Vector2f(0, 0);
            return;
        }

        if (size.x < mClientScene.size.x) {
            //view window is smaller than scene (x-dir)
            //-> don't allow black borders
            if (offs.x > 0)
                offs.x = 0;
            if (offs.x + mClientScene.size.x < size.x)
                offs.x = size.x - mClientScene.size.x;
        } else {
            //view is larger than scene -> black borders, but don't allow
            //parts of the scene to go out of view
            if (offs.x < 0)
                offs.x = 0;
            if (offs.x + mClientScene.size.x > size.x)
                offs.x = size.x - mClientScene.size.x;
        }

        //same for y
        if (size.y < mClientScene.size.y) {
            if (offs.y > 0)
                offs.y = 0;
            if (offs.y + mClientScene.size.y < size.y)
                offs.y = size.y - mClientScene.size.y;
        } else {
            if (offs.y < 0)
                offs.y = 0;
            if (offs.y + mClientScene.size.y > size.y)
                offs.y = size.y - mClientScene.size.y;
        }
    }

    private static bool isInside(SceneObjectPositioned obj, Vector2i pos) {
        return pos.isInside(obj.pos, obj.size);
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
        mRootScene.size = size;
        mRootView = new SceneView();
        mRootView.clientscene = mRootScene;
        //NOTE: normally SceneViews are elements in a further Scene, but here
        //      Screen is the container of the SceneView mRootView
        //      damn overengineered madness!
        mRootView.pos = Vector2i(0, 0);
        mRootView.size = size;
    }

    void size(Vector2i s) {
        mRootScene.size = s;
        mRootView.size = s;
    }
    Vector2i size() {
        return mRootView.size;
    }

    void draw(Canvas canvas) {
        mRootView.draw(canvas, null);
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

    abstract void draw(Canvas canvas, SceneView parentView);
}

class CallbackSceneObject : SceneObject {
    public void delegate(Canvas canvas, SceneView parentView) onDraw;

    void draw(Canvas canvas, SceneView parentView) {
        if (onDraw) onDraw(canvas, parentView);
    }
}

//with a rectangular bounding box??
class SceneObjectPositioned : SceneObject {
    Vector2i pos;
    Vector2i size;
}

class FontLabel : SceneObjectPositioned {
    private char[] mText;
    private Font mFont;

    this(Font font) {
        mFont = font;
        assert(font !is null);
    }

    void text(char[] txt) {
        mText = txt;
        //fit size to text
        size = mFont.textSize(mText);
    }
    char[] text() {
        return mText;
    }

    void draw(Canvas canvas, SceneView parentView) {
        mFont.drawText(canvas, pos, mText);
    }
}
