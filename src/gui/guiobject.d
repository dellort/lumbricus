module gui.guiobject;

import framework.framework;
import framework.event;
import gui.frame;
import gui.gui;
import game.game;
import game.scene;
import utils.configfile;
import utils.mylist;
import utils.time;
import utils.vector2;
import utils.rect2;
import utils.log;

//see GuiObject.getLayoutConstraints()
struct LayoutConstraints {
    Vector2i minSize = {0, 0};
}

//base class for gui stuff
//gui objects are simulated with absolute time, and can
//accept events by key bindings
//(to draw stuff, you can add your own SceneObject using addManagedSceneObject()
// it will be removed on kill() again, and also you should notice relayout())
class GuiObject {
    package bool mHasFocus; //accessed by GuiFrame
    package int mFocusAge; //accessed by GuiFrame
    package GuiFrame mParent;
    private {
        bool mOldFocus;
        SceneObject[] mManagedSceneObjects;
        //last known mousepos
        Vector2i mMousePos;
        //capture status; if true, mouse is grabbed inside this object
        //bool mMouseCaptured;
        //(optional) set of key bindings for the onKey*() handlers
        //if not set, bind parameter will be empty
        KeyBindings mBindings;

        Rect2i mBounds;
        int mZOrder = GUIZOrder.Gui;
    }

    GuiFrame parent() {
        return mParent;
    }
    void parent(GuiFrame set) {
        if (mParent is set)
            return;
        if (mParent !is null)
            remove();

        assert(mParent is null);
        assert(set !is null);
        mParent = set;
        set.doAdd(this);
        enforceSOStuff();
        stateChanged();
        needRelayout();
    }

    /+
    Resize procedure if screen resolution was changed:
    - GuiMain.size(newsize) is invoked
    - GuiMain.MainFrame.relayout()
    - GuiFrame.relayout() calls GuiLayouter.relayout()
    - GuiLayouter.relayout() possibly asks all managed children about size
      requests by calling getLayoutConstraints()
    - then it actually set the bounds by GuiObject.bounds(b), which in turn
      triggers the whole thing again, if that GuiObject was a GuiFrame or so
    +/

    final Rect2i bounds() {
        return mBounds;
    }

    final Vector2i size() {
        return bounds.size;
    }

    //get parameters how the object can be sized
    //default: minimum size to enclosing PositionedSceneObjects
    //you can override this and return anything
    void getLayoutConstraints(out LayoutConstraints lc) {
        lc.minSize = getSubBounds().size;
    }

    final void bounds(Rect2i b) {
        mBounds = b;
        relayout();
    }

    //called if the position or size changes
    void relayout() {
        //default implementation: do nothing (pretty bad, most time)
    }

    //called by a GuiObject itself when it updates bounds() or layout stuff
    //also i.e. called by the GuiLayouter if object is added to it
    void needRelayout() {
        //this seemed to be most simple *g*
        auto obj = this;
        while (obj.parent) {
            obj = obj.parent;
        }
        obj.relayout();
    }

    final void zorder(int set) {
        if (mZOrder != set) {
            mZOrder = set;
            //do random stuff, it's stupid anyway
            enforceSOStuff();
            stateChanged();
        }
    }

    final int zorder() {
        return mZOrder;
    }

    //check if the mouse "hits" this gui object
    //by default just look if it's inside the bounding rect
    //but for the sake of overengineering, anything is possible
    bool testMouse(Vector2i pos) {
        return bounds.isInside(pos);
    }

    //return the rectangle enclosing all scene objects
    Rect2i getSubBounds() {
        auto r = Rect2i.Empty();
        foreach (so; mManagedSceneObjects) {
            auto sop = cast(SceneObjectPositioned)so;
            if (sop) {
                r.extend(sop.pos);
                r.extend(sop.pos + sop.size);
            }
        }
        return r;
    }

    final void addManagedSceneObject(SceneObject so) {
        mManagedSceneObjects ~= so;
        enforceSOStuff(so);
    }

    //for the state of a SceneObject to certain invariant conditions
    //currently: mercilessly force managed scene objects to our scene, hehe
    private void enforceSOStuff(SceneObject so) {
        so.scene = mParent ? mParent.scene : null;
        so.zorder = mZOrder;
        so.active = true; //activeness isn't stored, argh
    }
    private void enforceSOStuff() {
        foreach (so; mManagedSceneObjects) {
            enforceSOStuff(so);
        }
    }

    void remove() {
        if (mParent) {
            mParent.removeSubobject(this);
            //will call this again, with mParent==null *g*
        } else {
            enforceSOStuff();
            stateChanged();
        }
    }

    //called if one of the following things changed:
    //  - focusness
    //  - global focusness (if parent focuses change)
    //  - mouse capture (not here yet)
    //  - alive state (added to a parent, killed)
    //also accessed by GuiFrame -> package
    /+package+/ void stateChanged() {
        if (mParent) {
            //recheck focus
            mHasFocus = (mParent.localFocus is this) && mParent.focused;
        } else {
            mHasFocus = isTopLevel;
        }

        if (mOldFocus != focused()) {
            mOldFocus = mHasFocus;
            onFocusChange();
        }
    }

    bool isTopLevel() {
        return false;
    }

    //set global focus state
    final void focused(bool set) {
        //in some cases, this might even safe you from infinite loops
        if (set == focused)
            return;
        //xxx: disclaiming focus (set==false) is ignored (but who needs it?)
        if (set) {
            //set focus: recursively claim focus on parents
            if (parent) {
                parent.localFocus = this; //local
                parent.focused = true;    //global (recurse upwards)
            }
        }
    }

    final bool focused() {
        return mHasFocus;
    }

    //within the parent frame, set this object on the highest zorder
    //(this is window-like zorder; has not much to do with the Scene stuff)
    void toFront() {
        if (parent) {
            //SceneObjects
            foreach (so; mManagedSceneObjects) {
                so.toTop();
            }
            //the GUI object itself under the parent
            parent.subObjectToFront(this);
        }
    }

    //called when focused() changes
    void onFocusChange() {
        gDefaultLog("global focus change for %s: %s", this, mHasFocus);
        //also adjust zorder, else it looks strange
        toFront();
    }

    //event handlers which can be overridden by the user
    //these functions shall return true if the event was handled
    protected bool onKeyDown(char[] bind, KeyInfo key) {
        return false;
    }
    protected bool onKeyUp(char[] bind, KeyInfo key) {
        return false;
    }
    protected bool onKeyPress(char[] bind, KeyInfo key) {
        return false;
    }
    //hm, what does the return value mean??
    protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }

    //notification if this.testMouse() changed on a mouse move event
    //onMouseEnterLeave(true, _) is called before the first onMouseMove() is
    //delivered
    //mouseIsInside == testMouse(mousePos)
    //forCapture == whether capture is active
    //i.e. onMouseEnterLeave(false, true) == captured, but outside real region
    //xxx nothing calls this, not implemented yet
    protected void onMouseEnterLeave(bool mouseIsInside, bool forCapture) {
    }

    /+package+/ void bindings(KeyBindings bind) {
        mBindings = bind;
    }
    KeyBindings bindings() {
        return mBindings;
    }

    //last known mouse position, that is inside this "window"
    Vector2i mousePos() {
        return mMousePos;
    }

    private bool callKeyHandler(KeyInfo info) {
        char[] bind;
        if (mBindings) {
            bind = mBindings.findBinding(info);
        }
        switch (info.type) {
            case KeyEventType.Down: return onKeyDown(bind, info);
            case KeyEventType.Up: return onKeyUp(bind, info);
            case KeyEventType.Press: return onKeyPress(bind, info);
            default: assert(false);
        }
    }

    //sucky interface, one and only one param must be !null
    //reason: mouse buttons are dispatched exactly like mouse move events
    //NOTE: instead of returning a bool for whether the event was accepted or
    //      not, there's testMouse() which queries if a mouse event on that
    //      position will be accepted or not
    /+package+/ void internalHandleMouseEvent(MouseInfo* mi, KeyInfo* ki) {
        assert(!!mi != !!ki);
        if (mi) {
            internalUpdateMousePos(mi.pos);
            onMouseMove(*mi);
        } else {
            callKeyHandler(*ki);
        }
    }

    //used by GuiFrame only
    /+package+/ void internalUpdateMousePos(Vector2i pos) {
        mMousePos = pos;
    }

    //return true if event was handled
    /+package+/ bool internalHandleKeyEvent(KeyInfo info) {
        return callKeyHandler(info);
    }

    /// Return true if this can have a focus (used for treatment of <tab>).
    bool canHaveFocus() {
        return false;
    }

    /// Return true if focus should set to this element when it becomes active.
    /// Only used if canHaveFocus() is true.
    bool greedyFocus() {
        return false;
    }

    //call if canHaveFocus() could have changed, although object was not added
    //or removed to the scene *sigh*
    void recheckFocus() {
        if (mParent)
            mParent.recheckSubFocus(this);
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    /+package+/ void doSimulate(Time curTime, Time deltaT) {
        simulate(curTime, deltaT);
    }

    void simulate(Time curTime, Time deltaT) {
    }
}

//evil, but the rest was better to integrate with this
class GuiObjectOwnerDrawn : GuiObject {
    class Drawer : SceneObject {
        override void draw(Canvas canvas) {
            //more for debugging; should it be a feature?
            auto b = this.outer.bounds();
            canvas.pushState();
            canvas.clip(b.p1, b.p2);
            this.outer.draw(canvas);
            canvas.popState();
        }
    }

    this() {
        addManagedSceneObject(new Drawer);
    }

    abstract void draw(Canvas canvas);
}

/+
//behave like s specifically
class GuiObjectProxy : GuiObject {
}
+/
