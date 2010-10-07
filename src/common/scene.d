module common.scene;

import framework.drawing;
import framework.surface;
import gui.renderbox;
import gui.rendertext;
import utils.list2;
import utils.vector2;
import utils.rect2;
import utils.misc;

import arr = tango.core.Array;

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
            if (mActiveObjects.ptr == static_storage.ptr) {
                //temporary fix for Tango issue #1987
                mActiveObjects = mActiveObjects.dup;
            }
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
    /// if zorder is passed, set the zorder (-1 is a special marker value to
    /// indicate that the function was called with one parameter)
    void add(SceneObject obj, int zorder = -1) {
        if (zorder != -1)
            obj.zorder = zorder;
        if (obj.mParent is this)
            return;
        argcheck(!obj.mParent, "already inserted in another Scene?");
        int z = obj.zorder();
        extend_zorder(z);
        assert(!mActiveObjects[z].contains(obj));
        mActiveObjects[z].add(obj);
        obj.mParent = this;
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
    Vector2i pos;
}

class SceneObjectRect : SceneObject {
    Rect2i rc;
}

//this crap is for Lua; you don't want to redraw every frame using Lua code, so
//  here's some scene graph based stuff that basically wraps common drawing
//  commands for Lua

//add new stuff as needed

//commands like blend or clip can be done as subclasses of Scene (influencing
//  only sub scene objects, then restoring the Canvas state)

class SceneDrawRect : SceneObjectRect {
    Color color = Color(0);
    bool fill = false;
    int width = 1; //width for unfilled rect
    int stipple = 0; //length of stipple

    override void draw(Canvas c) {
        if (fill) {
            c.drawFilledRect(rc, color);
        } else if (stipple > 0) {
            c.drawStippledRect(rc, color, stipple);
        } else {
            c.drawRect(rc, color, width);
        }
    }
}

class SceneDrawCircle : SceneObjectCentered {
    int radius;
    Color color = Color(0);
    bool fill;

    override void draw(Canvas c) {
        if (fill) {
            c.drawFilledCircle(pos, radius, color);
        } else {
            c.drawCircle(pos, radius, color);
        }
    }
}

class SceneDrawLine : SceneObject {
    Vector2i p1, p2;
    Color color;
    int width = 1;

    override void draw(Canvas c) {
        c.drawLine(p1, p2, color, width);
    }
}

class SceneDrawSprite : SceneObjectCentered {
    SubSurface source;
    BitmapEffect effect;

    override void draw(Canvas c) {
        c.drawSprite(source, pos, &effect);
    }
}

class SceneDrawText : SceneObjectCentered {
    FormattedText text;

    this() {
        text = new FormattedText();
    }

    override void draw(Canvas c) {
        //not really centered; the user can do that; hopefully this small
        //  violation of SceneObjectCentered assumptions doesn't really matter
        text.draw(c, pos);
    }
}

class SceneDrawBox : SceneObjectRect {
    BoxProperties box;

    override void draw(Canvas c) {
        drawBox(c, rc, box);
    }
}
