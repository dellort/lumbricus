module gui.widget;

import framework.framework;
import framework.event;
import gui.container;
import gui.gui;
import utils.configfile;
import utils.mylist;
import utils.time;
import utils.vector2;
import utils.rect2;
import utils.log;

//debugging (draw a red frame for the widget's bounds)
//version = WidgetDebug;

//layout parameters for dealing with i.e. size overallocation
//you can define borders and what happens, if a widget gets more space than it
//wanted
struct WidgetLayout {
    //most parameters are for each coord-component; X==0, Y==1

    //how the Widget wants to size
    //maybe give extra space to this object (> requested)
    bool[2] expand = [true, true];
    //actually use the extra space from expand (for allocation), aka streching
    //the value selects between expanded and requested size (without borders)
    //(with (expand && (fill==0)), the extra space will be kept empty, and the
    // widget is set to its requested size, i.e. allocation == requested)
    float[2] fill = [1.0f, 1.0f];

    //alignment of the Widget if it was expanded but not filled
    float[2] alignment = [0.5f, 0.5f]; //range 0 .. 1.0f

    //padding (added to the Widget's size request)
    int pad;        //padding for all 4 borders
    Vector2i padA;  //additional left/top border padding
    Vector2i padB;  //additional right/bottom border padding

    //not expanded and aligned, with optional border
    //x: -1 = left, 0 = center, 1 = right
    //y: similar
    static WidgetLayout Aligned(int x, int y, Vector2i border = Vector2i()) {
        WidgetLayout lay;
        lay.expand[0] = lay.expand[1] = false;
        lay.alignment[0] = (x+1)/2.0f;
        lay.alignment[1] = (y+1)/2.0f;
        lay.padA = lay.padB = border;
        return lay;
    }

    //expand in one direction, align centered in the other
    static WidgetLayout Expand(bool horiz_dir, Vector2i border = Vector2i()) {
        int dir = horiz_dir ? 0 : 1;
        int inv = 1-dir;
        WidgetLayout lay;
        lay.expand[dir] = true;
        lay.expand[inv] = false;
        lay.padA = lay.padB = border;
        return lay;
    }

    //expand fully, but with a fixed border around the widget
    static WidgetLayout Border(Vector2i border) {
        WidgetLayout lay;
        lay.padA = lay.padB = border;
        return lay;
    }

    static WidgetLayout Noexpand() {
        return Aligned(0,0);
    }

    static WidgetLayout opCall() {
        WidgetLayout x;
        return x;
    }
}

//base class for gui stuff
//Widgets are simulated with absolute time, and can
//accept events by key bindings
class Widget {
    package {
        Container mParent;
        int mZOrder; //any value, higher means more on top
        int mZOrder2; //what was last clicked, argh
        int mFocusAge;
    }
    private {
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

        //size which the container allocated for this Widget
        Rect2i mContainerBounds;
        //size which the Widget accepted (due to WidgetLayout)
        Rect2i mContainedWidgetBounds;

        //last requested size (cached)
        Vector2i mCachedContainedRequestSize;
        bool mCachedContainedRequestSizeValid;

        //if false, only call reallocation if size changed
        bool mLayoutNeedReallocate = true;

        //placement of Widget within allocation from Container
        WidgetLayout mLayout;

        //this is added to the graphical position of the widget (onDraw)
        //it is intended to support animations (without messing up the layouting)
        Vector2i mAddToPos;
    }

    final Container parent() {
        return mParent;
    }

    /// remove this from its parent
    final void remove() {
        if (mParent) {
            mParent.doRemoveChild(this);
        }
    }

    ///return true is this is the root window
    bool isTopLevel() {
        return false;
    }

    ///within the parent frame, set this object on the highest zorder
    final void toFront() {
        if (parent) {
            parent.doSetChildToFront(this);
        }
    }

    final int zorder() {
        return mZOrder;
    }
    ///set the "strict" zorder, will also set the "soft" zorder to top
    final void zorder(int z) {
        mZOrder = z;
        if (mParent) {
            mParent.doSetChildToFront(this);
        }
    }

    ///translate parent's coordinates (i.e. containedBounds()) to the Widget's
    ///coords (i.e. mousePos(), in case of containers: child object coordinates)
    final Vector2i coordsFromParent(Vector2i pos) {
        return pos - mContainedWidgetBounds.p1;
    }

    ///coordsToParent(coordsFromParent(p)) == p
    final Vector2i coordsToParent(Vector2i pos) {
        return pos + mContainedWidgetBounds.p1;
    }

    ///rectangle the Widget takes up in parent container
    final Rect2i containedBounds() {
        return mContainedWidgetBounds;
    }

    ///widget size
    final Vector2i size() {
        return mContainedWidgetBounds.size;
    }

    ///rectangle of the Widget in its own coordinates (.p1 is always (0,0))
    final Rect2i widgetBounds() {
        return Rect2i(Vector2i(0), size);
    }

    // --- layouting stuff

    WidgetLayout layout() {
        return mLayout;
    }

    void setLayout(WidgetLayout wl) {
        mLayout = wl;
        needRelayout();
    }

    ///only for Containers which kick around their children in quite nasty ways
    ///i.e. scrolling containers
    ///requires some cooperation from the parent's layoutSizeAllocation()
    final void adjustPosition(Vector2i pos) {
        auto s = mContainedWidgetBounds.size;
        mContainedWidgetBounds.p1 = pos;
        mContainedWidgetBounds.p2 = pos + s;
    }

    /// Report wished size (or minimal size) to the parent container.
    /// Can also be used to precalculate the layout (must independent of the
    /// current size).
    /// Widgets must override this; no default implementation.
    abstract protected Vector2i layoutSizeRequest();

    /// Return what layoutContainerSizeRequest() would return, but possibly
    /// cache the result.
    /// Container should use this to know child-Widget sizes
    /// (may the name lead to confusion with layoutSizeRequest())
    final Vector2i layoutCachedContainerSizeRequest() {
        //yyy no idea why caching the size doesn't really work
        //if (!mCachedContainedRequestSizeValid) {
            mCachedContainedRequestSizeValid = true;
            mCachedContainedRequestSize = layoutContainerSizeRequest();
        //}

        return mCachedContainedRequestSize;
    }

    /// assigns this Widget a new region
    /// Containers should use this to place children
    final void layoutContainerAllocate(Rect2i rect) {
        mContainerBounds = rect;
        layoutCalculateSubAllocation(rect);
        auto oldsize = mContainedWidgetBounds.size;
        mContainedWidgetBounds = rect;
        if (!mLayoutNeedReallocate && oldsize == rect.size) {
            //huh, no need to reallocate, because only the size matters.
            //(reallocation can be expensive; so avoid it)
        } else {
            mLayoutNeedReallocate = false;
            layoutSizeAllocation();
        }
    }

    /// Override this to actually do Widget-internal layouting.
    /// default implementation: empty (and isn't required to be invoked)
    protected void layoutSizeAllocation() {
    }

    ///called by a Widget itself when it wants to report a changed
    ///layoutSizeRequest(), or if any layouting parameter was changed
    ///if only the size was changed, maybe rather use needResize
    ///but if layoutSizeAllocation must be called, use needRelayout()
    ///relayouting won't happen if there's no parent!
    final void needRelayout() {
        mLayoutNeedReallocate = true;
        mCachedContainedRequestSizeValid = false;
        requestRelayout();
    }

    ///like needRelayout(), but less strict
    ///only_if_changed == only relayout if requested size changed
    final void needResize(bool only_if_changed) {
        if (only_if_changed && mCachedContainedRequestSizeValid) {
            //read the cache, invalidate it, and see if the size really changed
            auto oldsize = mCachedContainedRequestSize;
            mCachedContainedRequestSizeValid = false;
            if (oldsize == layoutCachedContainerSizeRequest())
                return;
        } else {
            mCachedContainedRequestSizeValid = false;
        }
        //difference to needRelayout: don't set the mLayoutNeedReallocate flag
        requestRelayout();
    }

    //call the parent container to relayout this Widget
    //internal to needRelayout() and needResize()
    private void requestRelayout() {
        if (parent) {
            parent.doRequestedRelayout(this);
        } else if (isTopLevel) {
            layoutContainerAllocate(mContainerBounds);
        } else {
            //hm.... Widget without parent wants relayout
            //do nothing (and don't relayout it)
        }
    }

    ///manually set the position/size, outside the normal layouting process
    final void manualRelayout(Rect2i c) {
        layoutContainerAllocate(c);
    }

    /// Size including the not-really-client-area.
    protected Vector2i layoutContainerSizeRequest() {
        auto msize = layoutSizeRequest();
        //just padding
        msize.x += mLayout.pad*2; //both borders for each component
        msize.y += mLayout.pad*2;
        msize += mLayout.padA + mLayout.padB;
        return msize;
    }

    /// according to WidgetLayout, adjust area such that the Widget feels warm
    /// and snugly; can be overridden... but with care and don't forget
    /// also to override layoutContainerSizeRequest()
    void layoutCalculateSubAllocation(inout Rect2i area) {
        //xxx doesn't handle under-sized stuff
        Vector2i psize = area.size();
        Vector2i offset;
        auto rsize = layoutCachedContainerSizeRequest();
        //fit the widget with its size into the area
        for (int n = 0; n < 2; n++) {
            if (mLayout.expand[n]) {
                //fill, 0-1 selects the rest of the size
                rsize[n] = rsize[n]
                    + cast(int)((psize[n] - rsize[n]) * mLayout.fill[n]);
            }
            //and align; this again selects the rest of the size
            //and add the border padding (padB is the second border, implicit)
            offset[n] = cast(int)((psize[n] - rsize[n]) * mLayout.alignment[n])
                + mLayout.pad + mLayout.padA[n];
            //remove the border from the size (the size is for the widget)
            rsize[n] = rsize[n] - mLayout.pad*2 - mLayout.padB[n] - mLayout.padA[n];
        }
        area.p1 = area.p1 + offset;
        area.p2 = area.p1 + rsize;
    }

    // --- input handling

    //check if the mouse "hits" this gui object
    //by default just look if it's inside the bounding rect
    //but for the sake of overengineering, anything is possible
    bool testMouse(Vector2i pos) {
        auto s = size;
        return (pos.x >= 0 && pos.y >= 0 && pos.x < s.x && pos.y < s.y);
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
    //xxx: currently works a bit... strange
    protected void onMouseEnterLeave(bool mouseIsInside) {
    }

    //I hate D
    package void doMouseEnterLeave(bool mii) {
        onMouseEnterLeave(mii);
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
    bool handleMouseEvent(MouseInfo* mi, KeyInfo* ki) {
        //call user's event handler
        assert(!!mi != !!ki);
        if (mi) {
            //update mousepos too!
            mMousePos = mi.pos;
            onMouseEnterLeave(true);
            return onMouseMove(*mi);
        } else {
            onMouseEnterLeave(true);
            return callKeyHandler(*ki);
        }
    }

    //return true if event was handled
    //overridden by Container
    bool handleKeyEvent(KeyInfo info) {
        return callKeyHandler(info);
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    // --- simulation and drawing

    //overridden by Container
    void internalSimulate(Time curTime, Time deltaT) {
        simulate(curTime, deltaT);
    }

    void simulate(Time curTime, Time deltaT) {
    }

    void doDraw(Canvas c) {
        c.pushState();
        //map (0,0) to the position of the widget and clip by widget-size
        c.setWindow(mContainedWidgetBounds.p1, mContainedWidgetBounds.p2);

        //user's draw routine
        onDraw(c);

        version (WidgetDebug) {
            c.drawRect(Vector2i(0), size - Vector2i(1,1),
                Color(1,focused ? 1 : 0,0));
        }

        c.popState();
    }

    ///you should override this for custom drawing / normal widget rendering
    protected void onDraw(Canvas c) {
    }


    // --- focus handling

    /// Return true if this can have a focus (used for treatment of <tab>).
    /// default implementation: return false
    bool canHaveFocus() {
        return false;
    }

    /// Return true if focus should set to this element when it becomes active.
    /// Only used if canHaveFocus() is true.
    /// default implementation: return false
    bool greedyFocus() {
        return false;
    }

    /// call if canHaveFocus() could have changed, although object was not added
    /// or removed to the GUI *sigh*
    final void recheckFocus() {
        if (parent)
            parent.doRecheckChildFocus(this);
    }

    /// claim global focus (try to make this.focused() == true)
    final void claimFocus() {
        //in some cases, this might even safe you from infinite loops
        if (focused)
            return;
        //set focus: recursively claim focus on parents
        if (parent) {
            parent.localFocus = this; //local
            parent.claimFocus();      //global (recurse upwards)
        }
    }

    /// if globally focused
    final bool focused() {
        return mHasFocus;
    }

    /// if locally focused
    final bool localFocused() {
        return parent ? parent.localFocus is this : isTopLevel;
    }

    /// focus the next element; returns if a new focus could be set
    /// used to focus to the next element using <tab>
    /// normal Widgets return true and claim focus if they weren't focused
    ///   else they return false and don't do anything
    /// Containers return true if another sub-Widget could be focused without
    ///   wrapping the internal list
    bool nextFocus() {
        if (canHaveFocus && !focused) {
            claimFocus();
            return true;
        }
        return false;
    }

    /// called when focused() changes
    /// default implementation: set Widget zorder to front
    protected void onFocusChange() {
        gDefaultLog("global focus change for %s: %s", this, mHasFocus);
        //also adjust zorder, else it looks strange
        if (focused)
            toFront();
    }

    //cf. Container
    protected Widget findLastFocused() {
        return this;
    }

    /// possibly update focus state
    final void pollFocusState() {
        if (parent) {
            //recheck focus
            mHasFocus = (parent.localFocus is this) && parent.focused;
        } else {
            mHasFocus = isTopLevel;
        }

        if (mOldFocus != focused()) {
            mOldFocus = focused();
            onFocusChange();
        }
    }
}
