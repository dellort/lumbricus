module game.scene;

import framework.framework;
import utils.mylist;
import utils.vector2;
import utils.rect2;

public import framework.framework : Canvas;

//when drawing a SceneObjectPositioned, clip the canvas to its bound
//useful to see if size field is correct, but not an intended functionality
//(because it's slow)
//xxx currently unfunctional, but who cares
//version = ClipForDebugging;

///a scene contains all graphics drawn onto the screen.
///each graphic is represented by a SceneObject
///all SceneObjects are relative to clientOffset within the Scene's rect
///clientOffset can be used to implement scrolling etc.
class Scene : SceneObjectRect {
    alias List!(SceneObject) SOList;

    private {
        SOList mActiveObjects;
    }

    this() {
        mActiveObjects = new SOList(SceneObject.allobjects.getListNodeOffset());
    }

    /// Add an object to the scene.
    /// It will have the highest z-order accross all other objects in the scene,
    /// and the z-orders within the already contained objects isn't changed.
    /// xxx currently only supports one container-scene per SceneObject, maybe
    /// I want to change that??? (and: how then? maybe need to allocate listnodes)
    void add(SceneObject obj) {
        assert(!mActiveObjects.contains(obj));
        mActiveObjects.insert_tail(obj);
    }

    /// Remove an object from the scene.
    /// The z-orders of the other objects remain untouched.
    void remove(SceneObject obj) {
        assert(mActiveObjects.contains(obj));
        mActiveObjects.remove(obj);
    }

    /// Remove all sub objects
    void clear() {
        mActiveObjects.clear();
    }

    //NOTE: clips and translates graphic coords
    //the convention is that invisible objects need to check theirselves if
    //they're outside the visible region
    //xxx: check if it's worth to check Scenes itself this way
    override void draw(Canvas canvas) {
        canvas.pushState();
        canvas.setWindow(mRect.p1, mRect.p2);

        foreach (obj; mActiveObjects) {
            version (ClipForDebugging) {
                canvas.pushState();

                SceneObjectPositioned pobj = cast(SceneObjectPositioned)obj;
                if (pobj) {
                    canvas.clip(pobj.pos, pobj.pos + pobj.size);
                    obj.draw(canvas);
                }
            }

            obj.draw(canvas);

            version (ClipForDebugging) {
                canvas.popState();
            }
        }

        canvas.popState();
    }
}

class SceneObject {
    private mixin ListNodeMixin allobjects;

    //render callback; coordinates relative to containing SceneObject
    void draw(Canvas canvas) {
    }
}

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
}

class SceneObjectCentered : SceneObject {
    protected Vector2i mPos;

    final Vector2i pos() {
        return mPos;
    }
    final void pos(Vector2i p) {
        mPos = p;
    }

    //return approximate radius (needed in special cases, i.e. labels for worms)
    abstract int getRadius();
}

//xxx kill this, replace by SceneObjectRect
class SceneObjectPositioned : SceneObject {
    Vector2i pos;
    Vector2i size;
}
