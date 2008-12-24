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
        alias List2!(SceneObject) SList;
        int max_zorder;
        SList[] mActiveObjects;
        SList[10] static_storage;
    }

    this() {
    }

    private void extend_zorder(int z) {
        assert (z >= 0);
        if (z < max_zorder)
            return;
        max_zorder = z;
        if (max_zorder < static_storage.length) {
            //sorry I suffer from a sickness called "performance paranoia"
            //this forces me to do microoptimizations whenever I see them, even
            //if they do nothing and the real performance killers sit elsewhere
            //if you know a cure, please send me an email
            //NOTE: old array data must not be lost
            mActiveObjects = static_storage[0..max_zorder+1];
        } else {
            mActiveObjects.length = max_zorder + 1;
        }
        foreach (ref cur; mActiveObjects) {
            if (!cur)
                cur = new SList();
        }
    }

    /// Add an object to the scene.
    /// It will have the highest z-order accross all other objects in the scene,
    /// and the z-orders within the already contained objects isn't changed.
    /// xxx currently only supports one container-scene per SceneObject, maybe
    /// I want to change that??? (and: how then? maybe need to allocate listnodes)
    void add(SceneObject obj) {
        assert(!obj.mParent, "already inserted in another Scene?");
        int z = obj.zorder();
        extend_zorder(z);
        assert(!mActiveObjects[z].contains(obj.node));
        obj.node = mActiveObjects[z].add(obj);
        obj.mParent = this;
    }

    /// Add with zorder; the other add() doesn't change the zorder
    void add(SceneObject obj, int zorder) {
        obj.zorder = zorder;
        add(obj);
    }

    /// Remove an object from the scene.
    /// The z-orders of the other objects remain untouched.
    void remove(SceneObject obj) {
        int z = obj.zorder();
        assert(z >= 0 && z < mActiveObjects.length);
        assert(mActiveObjects[z].contains(obj.node));
        assert(obj.mParent is this);
        mActiveObjects[z].remove(obj.node);
        obj.mParent = null;
    }

    /// Remove all sub objects
    void clear() {
        foreach (x; mActiveObjects) {
            foreach (y; x) {
                x.remove(y.node);
            }
        }
    }

    //NOTE: translates graphic coords
    override void draw(Canvas canvas) {
        canvas.pushState();
        canvas.translate(pos);

        for (int z = 0; z < mActiveObjects.length; z++) {
            //NOTE: some objects remove themselves with removeThis() when draw()
            //      is called
            foreach (obj; mActiveObjects[z]) {
                if (obj.active) {
                    obj.draw(canvas);
                }
            }
        }

        canvas.popState();
    }

    //returns nothing useful
    //probably can never be useful; sometimes I even reassign the SceneObject
    //position in draw()
    override Rect2i bounds() {
        return Rect2i.Empty();
    }
}

class SceneObject {
    private ListNode node;
    private Scene mParent;
    private ushort mZorder;
    bool active = true; //if draw should be called

    //returns non-null only, if it has been added to a Scene
    final Scene parent() {
        return mParent;
    }

    void removeThis() {
        if (mParent)
            mParent.remove(this);
    }

    final int zorder() {
        return mZorder;
    }
    //set the zorder... must be a low >=0 value (Scene uses arrays for zorder)
    final void zorder(int z) {
        assert (z >= 0 && z <= ushort.max);
        if (z == mZorder)
            return;
        Scene p = mParent;
        if (p) p.remove(this);
        mZorder = z;
        if (p) p.add(this);
    }

    //render callback; coordinates relative to containing SceneObject
    void draw(Canvas canvas) {
    }
}

class SceneObjectCentered : SceneObject {
    protected Vector2i mPos = {0, 0};

    final Vector2i pos() {
        return mPos;
    }
    final void pos(Vector2i p) {
        mPos = p;
    }

    //return bounds, independent from position (centered around (0,0))
    abstract Rect2i bounds();
}
