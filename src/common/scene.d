module common.scene;

import framework.framework;
import utils.list2;
import utils.vector2;
import utils.rect2;

public import framework.framework : Canvas;

///a scene contains all graphics drawn onto the screen.
///each graphic is represented by a SceneObject
///all SceneObjects are relative to clientOffset within the Scene's rect
///clientOffset can be used to implement scrolling etc.
class Scene : SceneObjectCentered {
    private {
        List2!(SceneObject) mActiveObjects;
    }

    this() {
        mActiveObjects = new List2!(SceneObject)();
    }

    /// Add an object to the scene.
    /// It will have the highest z-order accross all other objects in the scene,
    /// and the z-orders within the already contained objects isn't changed.
    /// xxx currently only supports one container-scene per SceneObject, maybe
    /// I want to change that??? (and: how then? maybe need to allocate listnodes)
    void add(SceneObject obj) {
        assert(!mActiveObjects.contains(obj.node));
        obj.node = mActiveObjects.add(obj);
    }

    /// Remove an object from the scene.
    /// The z-orders of the other objects remain untouched.
    void remove(SceneObject obj) {
        assert(mActiveObjects.contains(obj.node));
        mActiveObjects.remove(obj.node);
    }

    /// Remove all sub objects
    void clear() {
        mActiveObjects.clear();
    }

    //NOTE: translates graphic coords
    override void draw(Canvas canvas) {
        canvas.pushState();
        canvas.translate(pos);

        foreach (obj; mActiveObjects) {
            if (obj.active) {
                obj.draw(canvas);
            }
        }

        canvas.popState();
    }

    //returns nothing useful
    Rect2i bounds() {
        return Rect2i.Empty();
    }
}

class SceneObject {
    private ListNode node;
    bool active = true;

    //render callback; coordinates relative to containing SceneObject
    void draw(Canvas canvas) {
    }
}

/+
class SceneObjectRect : SceneObject {
    protected Rect2i mRect;

    //accessors what for? but dmd will inline them anyway.
    final Rect2i rect() {
        return mRect;
    }
    final void rect(Rect2i rc) {
        mRect = rc;
    }
    final Vector2i size() {
        return mRect.size;
    }
    final void size(Vector2i size) {
        mRect.p2 = mRect.p1 + size;
    }
}
+/

class SceneObjectCentered : SceneObject {
    protected Vector2i mPos;

    final Vector2i pos() {
        return mPos;
    }
    final void pos(Vector2i p) {
        mPos = p;
    }

    //return bounds, independent from position (centered around (0,0))
    abstract Rect2i bounds();
}
