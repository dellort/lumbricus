module common.scene;

import framework.framework;
import utils.list2;
import utils.vector2;
import utils.rect2;
import utils.misc;

import arr = tango.core.Array;

public import framework.framework : Canvas;

private alias ObjectList!(SceneObject, "node") SList;

///a scene contains all graphics drawn onto the screen.
///each graphic is represented by a SceneObject
///all SceneObjects are relative to clientOffset within the Scene's rect
///clientOffset can be used to implement scrolling etc.
class Scene : SceneObjectCentered {
    private {
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
        if (obj.mParent is this)
            return;
        assert(!obj.mParent, "already inserted in another Scene?");
        int z = obj.zorder();
        extend_zorder(z);
        assert(!mActiveObjects[z].contains(obj));
        mActiveObjects[z].add(obj);
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
        if (!obj.mParent)
            return;
        int z = obj.zorder();
        assert(z >= 0 && z < mActiveObjects.length);
        assert(mActiveObjects[z].contains(obj));
        assert(obj.mParent is this);
        mActiveObjects[z].remove(obj);
        obj.mParent = null;
    }

    /// Remove all sub objects
    void clear() {
        foreach (x; mActiveObjects) {
            foreach (y; x) {
                x.remove(y);
            }
        }
    }

    //NOTE: translates graphic coords
    override void draw(Canvas canvas) {
        for (int z = 0; z < mActiveObjects.length; z++) {
            draw_z(canvas, z);
        }
    }

    int zmin() {
        return 0;
    }
    int zmax() {
        return mActiveObjects.length; //huh off by one, but nobody cares
    }

    //only draw objects with z order z
    void draw_z(Canvas canvas, int z) {
        if (z < 0 || z >= mActiveObjects.length)
            return;

        SList objs = mActiveObjects[z];

        if (objs.empty())
            return;

        canvas.pushState();
        canvas.translate(pos);

        //NOTE: some objects remove themselves with removeThis() when draw()
        //      is called
        foreach (obj; objs) {
            if (obj.active) {
                obj.draw(canvas);
            }
        }

        canvas.popState();
    }
}

///you can add multiple sub-scenes, and the zorder of all objects in those sub-
///scenes will be as if they were added into a single scene
///NOTE: within the same zorder, the objects of the first scene still have a
///      lower zorder than objects from the last added scene
//xxx: the subscenes don't have this object as parent (but null or arbitrary)
//     also, uses a different interface than Scene (but that's naturally)
//     still better than the hack before
//also NOTE: special considerations for serialization: SceneZMix is used to
//  merge graphics that must be serialized and that can't be serialized; so you
//  should be sure that the serialized sub scenes don't contain references to
//  the not serialized ones (like in SceneObject.node)
//  (yes that's my dumb idea; try to sue me)
class SceneZMix {
    private {
        Scene[] mSubScenes;
    }

    Vector2i pos;

    this() {
    }

    void add(Scene obj) {
        mSubScenes ~= obj;
    }

    void remove(Scene obj) {
        //(remove doesn't actually remove anything, it does something... else)
        auto nlen = arr.remove(mSubScenes, obj);
        mSubScenes = mSubScenes[0..nlen];
    }

    void clear() {
        while (mSubScenes.length > 1) {
            remove(mSubScenes[$-1]);
        }
    }

    void draw(Canvas canvas) {
        canvas.pushState();
        canvas.translate(pos);

        int zmin = int.max;
        int zmax = int.min;

        foreach (s; mSubScenes) {
            zmin = min(zmin, s.zmin);
            zmax = max(zmax, s.zmax);
        }

        for (int z = zmin; z <= zmax; z++) {
            foreach (s; mSubScenes)
                s.draw_z(canvas, z);
        }

        canvas.popState();
    }
}

class SceneObject {
    public SList.Node node;
    private Scene mParent;
    private ushort mZorder;
    bool active = true; //if draw should be called

    this() {
    }

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
    Vector2i pos = {0, 0};

    this() {
    }
}
