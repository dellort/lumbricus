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

//when drawing a SceneObjectPositioned, clip the canvas to its bound
//useful to see if size field is correct, but not an intended functionality
//(because it's slow)
//version = ClipForDebugging;

//a scene contains all graphics drawn onto the screen
//each graphic is represented by a SceneObject
class Scene {
    alias List!(SceneObject) SOList;
    protected SOList mActiveObjects;
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

    //iterate over all objects in z-order (including z-order 0)
    int opApply(int delegate(inout SceneObject obj, inout int zorder) del) {
        foreach (int z, SOList list; mActiveObjectsZOrdered) {
            foreach (obj; list) {
                int res = del(obj, z);
                if (res)
                    return res;
            }
        }
        return 0;
    }
}

//virtual scene that merges two or more real (no recursion, sorry) scenes
//into one on-the-fly without any copying
class MetaScene : Scene {
    private Scene[] mSubScenes;

    this(Scene[] subScenes) {
        mSubScenes = subScenes;
        foreach (s; mSubScenes) {
            assert((cast(MetaScene)s) is null);
            size.x = max(size.x,s.size.x);
            size.y = max(size.y,s.size.y);
        }
    }

    //iterate over all objects in z-order (including z-order 0)
    int opApply(int delegate(inout SceneObject obj, inout int zorder) del) {
        for (int z = 0; z < cMaxZOrder; z++) {
            foreach (s; mSubScenes) {
                foreach (obj; s.mActiveObjectsZOrdered[z]) {
                    int res = del(obj, z);
                    if (res)
                        return res;
                }
            }
        }
        return 0;
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
    //"camera"
    private CameraStyle mCameraStyle;
    private SceneObjectPositioned mCameraFollowObject;
    private bool mCameraFollowLock;
    //last time the scene was scrolled by i.e. the mouse
    private long mLastUserScroll;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cScrollIdleTimeMs = 1000;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    private const cCameraBorder = 150;

    this() {
        //always create event handler
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

    void draw(Canvas canvas) {
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
        foreach (obj, z; mClientScene) {
            if (z>0) {
                version (ClipForDebugging) {
                    SceneObjectPositioned pobj = cast(SceneObjectPositioned)obj;
                    if (pobj) {
                        canvas.pushState();
                        canvas.clip(pobj.pos, pobj.pos + pobj.size);
                        obj.draw(canvas);
                        canvas.popState();
                    } else {
                        obj.draw(canvas);
                    }
                } else {
                    obj.draw(canvas);
                }
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

    //called after scene was set new, or zorder/activeness was changed
    //stupidly will be called 3 times on setScene()
    protected void onChangeScene() {
    }

    final public void scene(Scene scene) {
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

        onChangeScene();
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

        onChangeScene();
    }

    public bool active() {
        return mActive;
    }

    public void active(bool set) {
        if (set == mActive)
            return;

        if (!mScene) {
            mActive = false;
            onChangeScene();
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

        onChangeScene();
    }

    final public void setScene(Scene s, int z, bool aactive = true) {
        scene = s;
        zorder = z;
        active = aactive;
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
    Vector2i size;
}
