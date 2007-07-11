module gui.widget;

import framework.framework;
import framework.event;
import gui.container;
import gui.gui;
import game.scene;
import utils.configfile;
import utils.mylist;
import utils.time;
import utils.vector2;
import utils.rect2;
import utils.log;

//debugging
//version = WidgetDebug;

enum LayoutingPhase {
    None,       //done
    Need,       //relayout requested (which must be honoured)
    NeedAlloc,  //like Need, but requested size is valid
    //Request,    //layoutSizeRequest() is being called on this (and children)
    Alloc       //layoutSizeAllocation() is being called
}

//base class for gui stuff
//Widgets are simulated with absolute time, and can
//accept events by key bindings
//(to draw stuff, you can add your own SceneObject using addManagedSceneObject()
// it will be removed on kill() again, and also you should notice relayout())
class Widget {
    private {
        Container mParent;
        Scene mScene;

        int mZOrder; //any value

        //used to prevent too much (infinite recursion?) or too less layouting
        LayoutingPhase mLayouting;

        //last known mousepos (client coords)
        Vector2i mMousePos;

        //capture status; if true, mouse is grabbed inside this object
        //bool mMouseCaptured;

        //if globally focused (for local focus: (this == parent.localFocused))
        bool mHasFocus;
        //used only to raise onFocusChange()
        bool mOldFocus;

        //(optional) set of key bindings for the onKey*() handlers
        //if not set, bind parameter will be empty
        KeyBindings mBindings;

        //size which the container allocated for this Widget, including the
        //container's coordinates
        Rect2i mContainedBounds;

        //last requested size (cached)
        Vector2i mLastRequestSize = {-1, -1};

        //this is added to the graphical position of the widget (Scene.rect)
        //it is intended to support animations (without messing up the layouting)
        Vector2i mAddToPos;
    }

    this() {
        mScene = new Scene();
        version (WidgetDebug)
            initDebug();
    }

    final Scene scene() {
        return mScene;
    }

    final Container parent() {
        return mParent;
    }

    final void parent(Container set) {
        if (mParent is set)
            return;

        if (mParent !is null)
            remove();
        if (set is null)
            return;

        assert(mParent is null);
        assert(set !is null);

        //calls this.internalDoAdd() in turn, after all work was done
        set.internalDoAdd(this);
    }

    final void remove() {
        if (mParent) {
            mParent.removeChild(this);
        }
    }

    package final void internalDoAdd(Container from) {
        assert(mParent is null);
        mParent = from;

        mParent.recheckChildFocus(this);
        needRelayout();
        stateChanged();
    }

    //called by Container only; it's there because argh
    package final void internalDoRemove(Container from) {
        assert(mParent is from);
        mParent = null;
        doRemove();
    }

    //deinitialize widget
    protected void doRemove() {
        stateChanged();
    }

    ///translate parent's coordinates (i.e. containedBounds()) to the Widget's
    ///coords (i.e. mousePos(), in case of containers: child object coordinates)
    final Vector2i coordsFromParent(Vector2i pos) {
        return pos - mContainedBounds.p1;
    }

    ///coordToParent(coordFromParent(p)) == p
    final Vector2i coordToParent(Vector2i pos) {
        return pos + mContainedBounds.p1;
    }

    final Rect2i containedBounds() {
        return mContainedBounds;
    }

    final Rect2i widgetBounds() {
        return Rect2i(Vector2i(0), size);
    }

    ///only for Containers which kick around their children in quite nasty ways
    ///i.e. scrolling containers
    final void adjustPosition(Vector2i pos) {
        auto s = mContainedBounds.size;
        mContainedBounds.p1 = pos;
        mContainedBounds.p2 = pos + s;
        //no notifications whatever necessary :)
        //only need to reposition the Scene
        internalUpdateRealRect();
    }

    ///the actual allocated size
    final Vector2i size() {
        return mContainedBounds.size;
    }

/+
    ///visible area due to Scene scrolling and parent clipping
    ///all in Widget coords
    final Rect2i visibleArea() {
        Rect2i rc;
        rc.p1 = ...
        return rc;
    }
+/

    /// Report wished size (or minimal size) to the parent container.
    Vector2i layoutSizeRequest() {
        //unmeaningful default value
        return Vector2i(100, 100);
    }

    //called from Container while layouting
    //(_only_ from Container, in the generic layouting code)
    package final Vector2i internalSizeRequest() {
        if (mLayouting == LayoutingPhase.Need) {
            mLastRequestSize = layoutSizeRequest();
            mLayouting = LayoutingPhase.NeedAlloc;
        } else {
            //hum, this function shouldn't be called if this fails!
            assert(mLayouting == LayoutingPhase.None
                || mLayouting == LayoutingPhase.NeedAlloc);
        }

        gDefaultLog("ask %s for size, return %s", this, mLastRequestSize);

        return mLastRequestSize;
    }

    /// The parent container calls this if it relayouts its children.
    /// (ok, it's actually only called by this.internalSizeAllocation())
    protected void layoutSizeAllocation() {
        //override if you want
    }

    ///??
    protected void onRelayout() {
    }

    package final void internalLayoutAllocation(Rect2i rect) {
        bool need = (mLayouting == LayoutingPhase.Need)
            || (mLayouting == LayoutingPhase.NeedAlloc);

        assert(mLayouting == LayoutingPhase.None || need);

        Vector2i oldAllocation = mContainedBounds.size;

        mLayouting = LayoutingPhase.Alloc;

        mContainedBounds = rect;
        internalUpdateRealRect();

        gDefaultLog("reallocate %s %s", this, rect);

        //call user handler
        //but only if the size changed; else theoretically there would be no
        //change (but honour need-flag)
        if (need || rect.size != oldAllocation) {
            layoutSizeAllocation();

            onRelayout();
        }

        //the idea is: if someone requested layouting again, don't delete the flag
        //xxx rethink, this seems to be stupid and useless
        if (mLayouting == LayoutingPhase.Alloc)
            mLayouting = LayoutingPhase.None;
    }

    //argghrhrrdss
    //never calls any "notification" functions or so by design
    private void internalUpdateRealRect() {
        Rect2i rect = mContainedBounds;
        rect.p1 += mAddToPos;
        rect.p2 += mAddToPos;
        mScene.rect = rect;
    }

    ///called by a Widget itself when it wants to report a changed
    ///layoutSizeRequest(), or if any layouting parameter was changed
    /// immediate = if it should be relayouted on return of this function
    void needRelayout(bool immediate = false) {
        requestedRelayout();
    }

    //call to make the parent container to relayouted its children
    protected void requestedRelayout() {
        //propagate upwards
        mLayouting = LayoutingPhase.Need;
        if (mParent) {
            mParent.requestedRelayout();
        }
    }

    //check if the mouse "hits" this gui object
    //by default just look if it's inside the bounding rect
    //but for the sake of overengineering, anything is possible
    bool testMouse(Vector2i pos) {
        auto s = size;
        return (pos.x >= 0 && pos.y >= 0 && pos.x < s.x && pos.y < s.y);
    }

    //called if one of the following things changed:
    //  - focusness
    //  - global focusness (if parent focuses change)
    //  - mouse capture (not here yet)
    //  - alive state (added to a parent, killed)
    //also accessed by GuiFrame -> package
    void stateChanged() {
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

    ///return true is this is the root window
    bool isTopLevel() {
        return false;
    }

    //set global focus state
    final void focused(bool set) {
        //in some cases, this might even safe you from infinite loops
        if (set == focused)
            return;
        if (set) {
            //set focus: recursively claim focus on parents
            if (parent) {
                parent.localFocus = this; //local
                parent.focused = true;    //global (recurse upwards)
            }
        } else {
            //xxx disclaiming focus
            assert(false);
        }
    }

    final bool focused() {
        return mHasFocus;
    }

    //within the parent frame, set this object on the highest zorder
    final void toFront() {
        if (parent) {
            parent.childToTop(this);
        }
    }

    final int zorder() {
        return mZOrder;
    }
    final void zorder(int z) {
        mZOrder = z;
        if (mParent) {
            mParent.setChildZOrder(this, z);
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
    //return true only if you want block this event for children
    //no meaning for non-Container Widgets (?)
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

    void bindings(KeyBindings bind) {
        mBindings = bind;
    }
    KeyBindings bindings() {
        return mBindings;
    }

    ///last known mouse position, that is inside this "window"
    ///relative to (0,0) of the Widget
    final Vector2i mousePos() {
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
    //overridden by Container
    bool internalHandleMouseEvent(MouseInfo* mi, KeyInfo* ki) {
        //call user's event handler
        assert(!!mi != !!ki);
        if (mi) {
            //update mousepos too!
            mMousePos = mi.pos;
            return onMouseMove(*mi);
        } else {
            return callKeyHandler(*ki);
        }
    }

    //return true if event was handled
    //overridden by Container
    bool internalHandleKeyEvent(KeyInfo info) {
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
            mParent.recheckChildFocus(this);
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    //overridden by Container
    void internalSimulate(Time curTime, Time deltaT) {
        simulate(curTime, deltaT);
    }

    void simulate(Time curTime, Time deltaT) {
    }

    version (WidgetDebug) {
        class DebugDraw : SceneObject {
            override void draw(Canvas canvas) {
                canvas.drawRect(Vector2i(0), size - Vector2i(1,1), Color(1,0,0));
            }
        }

        void initDebug() {
            scene.add(new DebugDraw);
        }
    }
}

//evil, but the rest was better to integrate with this
class GuiObjectOwnerDrawn : Widget {
    class Drawer : SceneObject {
        override void draw(Canvas canvas) {
            this.outer.draw(canvas);
        }
    }

    this() {
        scene.add(new Drawer);
    }

    protected abstract void draw(Canvas canvas);
}
