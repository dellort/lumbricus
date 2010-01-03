module gui.widget;

import framework.config;
import framework.filesystem;
import framework.framework;
import framework.event;
import framework.i18n;
import gui.global;
import gui.renderbox;
import gui.rendertext;
import gui.styles;
import utils.configfile;
import utils.factory;
import utils.time;
import utils.vector2;
import utils.rect2;
import utils.output;
import utils.log;
import utils.mybox;
import str = utils.string;
import array = tango.core.Array;
import marray = utils.array;

//debugging (draw a red frame for the widget's bounds)
//version = WidgetDebug;
//for what this is, see where it's used
//version = ResizeDebug;

private {
    Log log;
    static this() { log = registerLog("GUI"); }

    //only grows, must not overflow
    static int gNextFocusAge;
    //also grows only; used to do "soft" zorder
    static int gNextZOrder2;
}

//layout parameters for dealing with e.g. size overallocation
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

    //border padding; adds to border area
    Vector2i border;

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

    void loadFrom(ConfigNode node) {
        //xxx loading only the "important" fields (rest seems to be unused...)
        pad = node.getIntValue("pad", pad);
        expand[0] = node.getBoolValue("expand_x", expand[0]);
        expand[1] = node.getBoolValue("expand_y", expand[1]);
        alignment[0] = node.getFloatValue("align_x", alignment[0]);
        alignment[1] = node.getFloatValue("align_y", alignment[1]);
        fill[0] = node.getFloatValue("fill_x", fill[0]);
        fill[1] = node.getFloatValue("fill_y", fill[1]);
    }
}

//base class for gui stuff
//Widgets are simulated with absolute time, and can
//accept events by key bindings
class Widget {
    private {
        Widget mParent;
        int mZOrder; //any value, higher means more on top
        int mZOrder2; //what was last clicked, argh

        //hold global GUI state; null if Widget isn't part of the GUI
        GUI mGUI;

        //sub widgets
        Widget[] mWidgets;
        Widget[] mZWidgets; //sorted by z-orders

        //last known mousepos (client coords)
        Vector2i mMousePos;

        //value set by focusable()
        bool mFocusable = true;
        //used only to raise onFocusChange()
        bool mOldFocus;
        //used to find out globally which widget was last focused
        int mFocusAge;

        bool mMouseIsInside;

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

        StylesLookup mStyles;

        //this is added to the graphical position of the widget (onDraw)
        //it is intended to support animations (without messing up the layouting)
        Vector2i mAddToPos;

        //current content scaling, as set by scale()
        //used only if the fw driver supports it
        Vector2f mScale = {1.0f, 1.0f};

        //minimum total size, including border and padding
        Vector2i mMinSize;
        //border around widget, adds to size
        BoxProperties mBorderStyle;
        bool mDrawBorder;
        int mWidgetPad = 0;
        Rect2i mBorderArea;   //just for drawing

        //invisible widgets don't draw anything, and don't accept
        //or forward events
        bool mVisible = true;
        //disabled widgets are drawn in gray and don't accept events
        bool mEnabled = true;

        //tentative useless feature
        Surface mBmpBackground;

        MyBox[char[]] mStyleOverrides;
    }

    ///clip graphics to the inside
    bool doClipping = true;

    ///return value for the default onTestMouse()
    protected bool isClickable = true;

    ///text to display as tooltip
    ///note that there are no popup tooltips (and there'll never be one)
    ///instead, you need something else to display them
    char[] tooltip;

    ///use Widget.doesCover
    protected bool checkCover = false;

    //-------

    this() {
        mStyles = new StylesLookupImpl();

        //register with _actual_ classes of the object
        //(that's how D ctors work... this wouldn't work in C++)
        auto curclass = this.classinfo;
        char[][] myclasses;
        while (curclass) {
            char[] clsname = WidgetFactory.lookupDynamic(curclass);
            if (clsname.length) {
                myclasses ~= "w-" ~ clsname;
            }
            curclass = curclass.base;
        }
        myclasses ~= "w-any"; //class for all widgets
        mStyles.addClasses(myclasses);
    }

    final StylesLookup styles() {
        return mStyles;
    }

    /// Add sub GUI element
    protected void addChild(Widget o) {
        if (o.parent !is null) {
            assert(false, "already added");
        }
        assert(marray.arraySearch(mWidgets, o) < 0);

        o.mParent = this;
        mWidgets ~= o;
        mZWidgets ~= o;
        updateZOrder(o, true);

        o.do_add();

        log("on child add {} {}", this, o);
        onAddChild(o);

        //just to be sure
        o.needRelayout();

        fix_focus_on_add(o);
    }

    /// Undo addChild()
    protected void removeChild(Widget o) {
        if (o.parent !is this) {
            assert(false, "was not child of this");
        }

        bool had_focus = o.focused();

        o.do_remove();

        //copy... when a function is iterating through these arrays and calls
        //this function (through event handling), and we modify the array, and
        //then return to that function, it gets fucked up
        //but if these functions use foreach (copies the array descriptor), and
        //we copy the array memory, we're relatively safe *SIGH!*
        mWidgets = mWidgets.dup;
        mZWidgets = mZWidgets.dup;
        marray.arrayRemove(mWidgets, o);
        marray.arrayRemove(mZWidgets, o);
        o.mParent = null;
        o.styles.parent = null;

        log("on child remove {} {}", this, o);
        onRemoveChild(o);

        if (had_focus) {
            //that's just kind and friendly?
            o.pollFocusState();
            //find a replacement widget for focus
            if (gui)
                assert(gui.mFocus is null);
            focusSomething();
        }

        needRelayout();
    }

    //most important initializations & cleanups, which must be done recursively
    //called right after/before the actual insert/remove code
    //they must not trigger any further events or user-code
    private void do_add() {
        assert(!!mParent);
        mGUI = mParent.mGUI;
        if (mGUI) {
            mStyles.parent = mGUI.stylesRoot;
            //how to handle this?
            //for now, always force re-read of the style properties
            mStyles.didChange = true;
            //xxx shitty hack
            mCachedContainedRequestSizeValid = false;
            mLayoutNeedReallocate = true;
            //xxx not good to call user code during this "critical" phase...?
            readStyles();
        }
        foreach (c; mWidgets) {
            c.do_add();
        }
    }
    private void do_remove() {
        assert(!!mParent);
        if (mGUI) {
            mGUI.do_remove(this);
        }
        mGUI = null;
        foreach (c; mWidgets) {
            c.do_remove();
        }
        //reset some more transient state
        mMouseIsInside = false;
    }

    //called after child has been added/removed, and before relayouting etc.
    //  is done -- might be very fragile
    protected void onAddChild(Widget c) {
    }
    protected void onRemoveChild(Widget c) {
    }

    private void updateZOrder(Widget child, bool hard) {
        assert(child.parent is this);
        child.mZOrder2 = ++gNextZOrder2;
        //avoid unneeded work (note that mZOrder2 still must be set)
        if (!hard && mZWidgets[$-1] is child)
            return;
        array.sort(mZWidgets,
            (Widget a, Widget b) {
                if (a.mZOrder == b.mZOrder) {
                    return a.mZOrder2 < b.mZOrder2;
                }
                return a.mZOrder < b.mZOrder;
            }
        );
    }

    protected void setChildLayout(Widget child, WidgetLayout layout) {
        child.setLayout(layout);
        needRelayout();
    }

    //just do what the code says
    //"virtual frame" meaning the widget itself is unfocusable/no mouse clicks
    protected final void setVirtualFrame(bool click = false) {
        focusable = false;
        isClickable = click;
    }

    final Widget parent() {
        return mParent;
    }

    /// remove this from its parent
    final void remove() {
        if (mParent) {
            mParent.removeChild(this);
        }
    }

    ///return true is this is the root window
    final bool isTopLevel() {
        return mGUI && !mParent;
    }

    //return global GUI state
    //returns null if the Widget-tree is unlinked from the GUI
    final GUI gui() {
        return mGUI;
    }

    ///return if the Widget is linked into the GUI hierarchy, which means it
    ///can be visible, receive events, do layouting etc...
    ///simply having a parent is not enough for this for various silly reasons
    final bool isLinked() {
        return !!mGUI;
    }

    ///return true if other is a direct or indirect parent of this
    /// also returns true for a.isTransitiveChild(a)
    final bool isTransitiveChild(Widget other) {
        return other is this || findDirectChildFor(other);
    }

    ///blergh
    ///if w is a transitive child of this, return the direct child of this,
    /// that's on the path to w; else return null
    ///a.findDirectChildFor(a) == null
    final Widget findDirectChildFor(Widget other) {
        while (other) {
            if (other.parent is this)
                return other;
            other = other.parent;
        }
        return null;
    }

    ///within the parent frame, set this object on the highest zorder
    final void toFrontLocal() {
        if (parent)
            parent.updateZOrder(this, false);
    }

    ///globally set highest zorder (like toFrontLocal(), "soft" zorder only)
    final void toFront() {
        toFrontLocal();
        if (parent)
            parent.toFront();
    }

    final int zorder() {
        return mZOrder;
    }
    ///set the "strict" zorder, will also set the "soft" zorder to top
    final void zorder(int z) {
        mZOrder = z;
        if (parent) {
            parent.updateZOrder(this, true);
        }
    }

    final void minSize(Vector2i s) {
        if (s == mMinSize)
            return;
        mMinSize = s;
        needResize();
    }
    final Vector2i minSize() {
        return mMinSize;
    }

    BoxProperties borderStyle() {
        return mBorderStyle;
    }

    bool drawBorder() {
        return mDrawBorder;
    }

    ///Show or hide the widget
    ///Only affects drawing and events, has no influence on layout
    void visible(bool set) {
        if (set == mVisible)
            return;
        mVisible = set;
        pollFocusState();
    }
    bool visible() {
        return mVisible;
    }

    ///enable/disable the widget
    ///disabling a widget will gray it out and disable events for this widget
    ///and all children
    void enabled(bool set) {
        if (set == mEnabled)
            return;
        mEnabled = set;
        pollFocusState();
        styles.setState("disabled", !mEnabled);
    }
    bool enabled() {
        return mEnabled;
    }

    final Vector2i bordersize() {
        auto b = mLayout.border;
        int pad = mWidgetPad;
        if (mDrawBorder)
            pad += mBorderStyle.borderWidth + mBorderStyle.cornerRadius/3;
        b += Vector2i(pad);
        return b;
    }

    ///translate parent's coordinates (i.e. containedBounds()) to the Widget's
    ///coords (i.e. mousePos(), in case of containers: child object coordinates)
    final Vector2i coordsFromParent(Vector2i pos) {
        pos -= mContainedWidgetBounds.p1;
        if (canScale)
            pos = doScalei(pos);
        return pos;
    }

    ///coordsToParent(coordsFromParent(p)) == p
    final Vector2i coordsToParent(Vector2i pos) {
        if (canScale)
            pos = doScale(pos);
        return pos + mContainedWidgetBounds.p1;
    }

    ///rectangle the Widget takes up in parent container
    ///basically containerBounds() without borders, padding, unoccupied space
    ///(as returned by last call of layoutCalculateSubAllocation())
    ///result.p1 is the container's corrdinate where the client's (0,0) is
    final Rect2i containedBounds() {
        return mContainedWidgetBounds;
    }

    ///like containedBounds() with borders, but without padding and unoccupied
    /// space (e.g. a button that doesn't expand and is allocated inside a
    /// larger area: most of the space outside the button is unallocated, a
    /// space around the button is for the border, and the space inside the
    /// button is used up by the text)
    ///the area between containedBounds() and containedBorderBounds() is used
    /// for the border, and the top-left part of the border area has negative
    /// client coordinates
    ///the border is exactly bordersize() thick (on all 4 sides)
    final Rect2i containedBorderBounds() {
        /+ I don't know why it's stored as mBorderArea; not my fault
        auto res = mContainedWidgetBounds;
        res.p1 -= bordersize();
        res.p2 += bordersize();
        assert(res == mBorderArea);
        return res;
        +/
        return mBorderArea;
    }

    ///value passed to last call of layoutContainerAllocate()
    final Rect2i containerBounds() {
        return mContainerBounds;
    }

    ///position of the widget inside container
    ///note that this is not equal to the client's (0,0) position, because there
    /// may be borders and unused space between those points
    final Vector2i containerPosition() {
        return mContainerBounds.p1;
    }

    final void containerPosition(Vector2i pos) {
        auto rc = mContainerBounds;
        rc += -rc.p1 + pos;
        layoutContainerAllocate(rc); //shouldn't normally trigger relayout
    }

    ///widget client size
    final Vector2i size() {
        if (canScale)
            return doScalei(mContainedWidgetBounds.size);
        else
            return mContainedWidgetBounds.size;
    }

    ///client rectangle of the Widget in its own coordinates
    ///(.p1 is always (0,0))
    final Rect2i widgetBounds() {
        return Rect2i(Vector2i(0), size);
    }

    ///translate pt, which is in relative's coords, to our coordinate system
    ///returns if success (which means pt is valid, else pt is unchanged)
    ///slow because it translates up and down :)
    final bool translateCoords(Widget relative, ref Vector2i pt) {
        if (!relative)
            return false;
        Vector2i p = pt;
        while (relative.parent) {
            p = relative.coordsToParent(p);
            relative = relative.parent;
        }
        //nasty way to do it, but should work
        auto inv = Vector2i(0, 0);
        Widget other = this;
        while (other.parent) {
            inv = other.coordsToParent(inv);
            other = other.parent;
        }
        //they're both roots, so if same screen <=> same widget
        if (other !is relative)
            return false;
        //translate back
        pt = p - inv;
        return true;
    }

    final bool translateCoords(Widget relative, ref Rect2i prc) {
        auto rc = prc;
        if (!translateCoords(relative, rc.p1) ||
            !translateCoords(relative, rc.p2))
        {
            return false;
        }
        prc = rc;
        return true;
    }

    ///this silly function returns the distance between a border of this widget
    /// and the border of the parent widget
    ///e.g. distance of our left border to the right border of the parent
    ///dx=1, dy=0: right screen border
    ///dx=0, dy=-1: top screen border
    ///etc.
    ///right_bottom: false=left or top bottom of this widget, true=right/bottom
    int findParentBorderDistance(int dx, int dy, bool right_bottom) {
        //check the direct parent
        //xxx: we really must do a bit more, I guess
        Vector2i pt = right_bottom ? size : Vector2i(0);
        if (!(parent && parent.translateCoords(this, pt)))
            return 0; //dummy value, doesn't really matter (widget invisible)
        //the border thing is very silly: border isn't part of the widget, so
        //  you have to deal with it manually to get the real left/right border
        pt += bordersize * (right_bottom ? +1 : -1);
        if (dx > 0 || dy > 0)
            pt = parent.size - pt;

        if ((dx == 1 || dx == -1) && dy == 0)
            return pt.x;
        if ((dy == 1 || dy == -1) && dx == 0)
            return pt.y;
        assert(false, "one of dx or dy must be 1 or -1, the other must be 0");
    }

    ///Set current content scaling factor
    ///Setting this changes size() and forces a relayout
    void scale(Vector2f s) {
        if (s != mScale) {
            mScale = s;
            //xxx this could be quite expensive, implement better way to
            //    propagate the changed size()
            needRelayout();
        }
    }
    Vector2f scale() {
        return mScale;
    }

    //utility methods, stupid int/float conversions
    protected Vector2i doScale(Vector2i org) {
        return toVector2i(toVector2f(org) ^ mScale);
    }
    protected Vector2i doScalei(Vector2i org) {
        return toVector2i(toVector2f(org) / mScale);
    }

    //returns true if current driver supports Canvas.setScale
    //xxx can be removed if we fully switch to OpenGL
    protected bool canScale() {
        return (gFramework.drawDriver.getFeatures & DriverFeatures.canvasScaling) > 0;
    }

    protected Widget getBinChild() {
        assert(mWidgets.length <= 1);
        return mWidgets.length ? mWidgets[0] : null;
    }

    ///treat the return value as const
    protected Widget[] children() {
        return mWidgets;
    }

    // --- layouting stuff

    WidgetLayout layout() {
        return mLayout;
    }

    void setLayout(WidgetLayout wl) {
        mLayout = wl;
        needRelayout();
    }

    /// Report wished size (or minimal size) to the parent container.
    /// Can also be used to precalculate the layout (must independent of the
    /// current size).
    /// Widgets should override this; by default returns always (0,0).
    protected Vector2i layoutSizeRequest() {
        //report the biggest
        Vector2i biggest = Vector2i(0);
        foreach (w; children) {
            biggest = biggest.max(w.layoutCachedContainerSizeRequest());
        }
        return biggest;
    }

    /// Return what layoutContainerSizeRequest() would return, but possibly
    /// cache the result.
    /// Container should use this to know child-Widget sizes
    /// (may the name lead to confusion with layoutSizeRequest())
    final Vector2i layoutCachedContainerSizeRequest() {
        if (!mCachedContainedRequestSizeValid) {
            mCachedContainedRequestSizeValid = true;
            mCachedContainedRequestSize = layoutContainerSizeRequest();
        }

        return mCachedContainedRequestSize;
    }

    //short names cure overengineering
    alias layoutCachedContainerSizeRequest requestSize;

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
            //log("realloc {} {}/{}", this, mContainerBounds, rect);
            layoutSizeAllocation();
        }
    }

    /// Override this to actually do Widget-internal layouting.
    /// default implementation: empty (and isn't required to be invoked)
    protected void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        foreach (w; children) {
            w.layoutContainerAllocate(b);
        }
    }

    ///called by a Widget itself when it wants to report a changed
    ///layoutSizeRequest(), or if any layouting parameter was changed
    ///if only the size was changed, maybe rather use needResize
    ///but if layoutSizeAllocation must be called, use needRelayout()
    ///relayouting won't happen if there's no parent!
    ///clearification:
    ///  needRelayout(): size/allocation calculation changed
    ///  needResize(): only size calculation (possibly) changed
    final void needRelayout() {
        requestRelayout(false);
    }

    ///like needRelayout(), but less strict
    ///if the request size changed, trigger relayout
    final void needResize() {
        requestRelayout(true);
    }

    //call the parent container to relayout this Widget
    //internal to needRelayout() and needResize()
    private void requestRelayout(bool resize_only) {
        if (!resize_only || mLayoutNeedReallocate) {
            mLayoutNeedReallocate = true;
            resize_only = false;
        }

        bool was_resized = true;

        if (mCachedContainedRequestSizeValid) {
            //read the cache, invalidate it, and see if the size really changed
            auto oldsize = mCachedContainedRequestSize;
            mCachedContainedRequestSizeValid = false;
            was_resized = !(oldsize == layoutCachedContainerSizeRequest());
        }

        if (resize_only && !was_resized)
            return;

        //do nothing (and don't relayout it) => more an optimization
        //also, it wouldn't make sense (e.g. styles stuff makes the results
        //  dependent from the parent widget hierarchy [more or less])
        if (!isLinked())
            return;

        if (!was_resized) {
            log("relayout-down: {}", this);
            //don't need to involve parent, just make this widget happy
            layoutContainerAllocate(mContainerBounds);
            return;
        }

        //involve parent, because the size of its child might have changed
        //some container could handle the resize of a single child change more
        //  efficiently, and some require complete relayouting
        if (parent) {
            log("relayout-up: {}", this);
            parent.needRelayout();
        } else {
            assert(isTopLevel());
            layoutContainerAllocate(mContainerBounds);
        }
    }

    private void requestedRelayout(Widget child) {
        assert(child.parent is this);
        //propagate upwards, indirectly
        needRelayout();
    }

    /// Size including the not-really-client-area.
    protected Vector2i layoutContainerSizeRequest() {
        auto msize = layoutSizeRequest();
        msize = msize.max(mMinSize);
        //just padding
        msize.x += mLayout.pad*2; //both borders for each component
        msize.y += mLayout.pad*2;
        msize += mLayout.padA + mLayout.padB;
        msize += bordersize*2;
        return msize;
    }

    /// according to WidgetLayout, adjust area such that the Widget feels warm
    /// and snugly <- what
    final void layoutCalculateSubAllocation(inout Rect2i area) {
        //xxx doesn't handle under-sized stuff
        Vector2i psize = area.size();
        Vector2i offset;
        auto rsize = layoutCachedContainerSizeRequest();
        version (ResizeDebug) {
            //assertion must work - checking this subverts optimization
            assert(rsize == layoutContainerSizeRequest());
            Trace.formatln("parent-alloc {}: {} {}", this, rsize, area);
        }
        //fit the widget with its size into the area
        for (int n = 0; n < 2; n++) {
            if (mLayout.expand[n]) {
                //fill, 0-1 selects the rest of the size
                rsize[n] = rsize[n]
                    + cast(int)((psize[n] - rsize[n]) * mLayout.fill[n]);
            }
            //and align; this again selects the rest of the size
            offset[n] = cast(int)((psize[n] - rsize[n]) * mLayout.alignment[n]);
        }
        auto pad = Vector2i(mLayout.pad, mLayout.pad);
        auto ba = mLayout.padA + pad;
        auto bb = mLayout.padB + pad;
        area.p1 += offset + ba;
        area.p2 = area.p1 + rsize - ba - bb;
        mBorderArea = area;
        area.p1 += bordersize;
        area.p2 -= bordersize;
        version (ResizeDebug) {
            auto cs = layoutSizeRequest();
            if (area.size.x < cs.x || area.size.y < cs.y) {
                Trace.formatln("underallocation in {}, {} {}",
                    this.classinfo.name, area.size, cs);
                area.p2 = area.p1 + cs.max(area.size);
            }
            assert(area.size.x >= cs.x);
            assert(area.size.y >= cs.y);
            Trace.formatln("sub-alloc {}: {}", this, area);
        }
        //force no negative sizes
        area.p2 = area.p1 + area.size.max(Vector2i(0));
    }

    // --- input handling

    ///check if the mouse "hits" this gui object
    ///by default return isClickable, but for the sake of
    ///overengineering, anything is possible
    ///NOTE: doesn't need to account for child widgets (onTestMouse() can't
    ///      "shadow" them)
    ///      the area outside widgetBounds is automatically excluded
    protected bool onTestMouse(Vector2i pos) {
        return isClickable;
    }

    ///Check where the Widget should receive mouse events
    /// pos = mouse position in local coordinates
    ///(like onTestMouse; this wrapper function is here to enforce the
    ///restriction to widget bounds)
    ///actually, checks border area now, which means widget can receive negative
    /// or too big mouse coordinates
    final bool testMouse(Vector2i pos) {
        if (!mVisible || !mEnabled)
            return false;
        if (!mBorderArea.isInside(coordsToParent(pos)))
            return false;
        return onTestMouse(pos);
    }

    ///if the widget could receive input if it had focus
    ///considers parent widget state as well
    final bool canTakeInput() {
        if (!isLinked())
            return false;
        if (mParent && !mParent.canTakeInput())
            return false;
        return mVisible && mEnabled;
    }

    //event handler which can be overridden by the user
    //the default implementation is always empty and doesn't need to be called
    protected void onKeyEvent(KeyInfo info) {
    }

    //handler for mouse move events
    protected void onMouseMove(MouseInfo mouse) {
    }

    protected void onMouseEnterLeave(bool mouseIsInside) {
    }

    //called on parents after child.onMouseEnterLeave(mouseIsInside)
    //this will "bubble up" all the way to the root window's widget
    protected void onChildMouseEnterLeave(Widget child, bool mouseIsInside) {
    }

    //calls onMouseEnterLeave(), but avoid unnecessary recursion
    //mii = mouseIsInside (too much typing hurts my old knuckle joints)
    private void doMouseEnterLeave(bool mii) {
        if (mMouseIsInside != mii) {
            mMouseIsInside = mii;
            styles.setState("hover", mii);
            onMouseEnterLeave(mii);
            auto cur = parent;
            while (cur) {
                cur.onChildMouseEnterLeave(this, mii);
                cur = cur.parent;
            }
        }
    }

    ///return true if the mouse pointer currently is inside the widget
    ///considers canTakeInput() and testMouse()
    final bool mouseIsInside() {
        return mMouseIsInside;
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

    final char[] findBind(KeyInfo k) {
        char[] bind;
        if (mBindings) {
            bind = mBindings.findBinding(k);
        }
        return bind;
    }

    //dispatch either to this widget or children widgets
    //return true if the event was handled
    private bool handleInput(InputEvent event) {
        if (!gui)
            return false;

        //handleChildInput checks this
        //can only fail if MainFrame is set to disabled/invisible or so
        assert(canTakeInput());

        auto focus = gui.mFocus;

        if (handleChildInput(event))
            return true;

        //again the two dispatch methods - final event test
        if (event.isMouseRelated()) {
            if (!testMouse(event.mousePos))
                return false;
        } else {
            if (this !is focus)
                return false;
        }

        gui.deliverDirectEvent(this, event);

        return true;
    }

    //this function is called to deliver events to child widgets
    //this function is just overrideable to be able to "bend the rules"; for
    //  proper input handling use onKeyEvent etc.
    //this also determines if the input is sent to this widget:
    //  return false => event may be delivered to this (or not at all if that
    //      fails; there's still a final event test)
    //  return true => event is considered to be handled by the function
    //if you override this and never call the super function, children never
    //  receive input
    //even if you override this and return "false", it doesn't mean this Widget
    //  will receive the event, because handleInput() may decide that the event
    //  is not for this widget (e.g. Widget not focused)
    //if the widget wants to route the event to itself, don't call the super
    //  method, call deliverDirectEvent(event), and return true
    protected bool handleChildInput(InputEvent event) {
        if (event.isMouseRelated()) {
            return childDispatchByMouse(event);
        } else {
            return childDispatchByFocus(event);
        }
    }

    private bool childDispatchByMouse(InputEvent event) {
        //objects towards the end of the array are later drawn => _reverse
        //(in ambiguous cases, mouse should pick what's visible first)
        foreach_reverse (child; mZWidgets) {
            auto cevent = translateEvent(child, event);

            //child.parent !is this: not sure if this happens; probably when an
            //i nput event handler called by us removes a widget which has a
            //  lower zorder
            //also, we test the border area instead of using testMouse(),
            //  because testMouse() doesn't check for sub-widgets (it mustn't
            //  be allowed to block sub-widget mouse events)
            if (child.parent is this
                && child.mBorderArea.isInside(event.mousePos)
                && child.canTakeInput()
                && child.handleInput(cevent))
            {
                return true;
            }
        }
        return false;
    }

    private bool childDispatchByFocus(InputEvent event) {
        //could send event directly to gui.mFocus
        //but let it "tingle" down, so that widgets overriding
        //  handleChildInput() can do their evil stuff etc.

        if (!gui || !gui.mFocus)
            return false;

        auto child = findDirectChildFor(gui.mFocus);

        if (!child || !child.canTakeInput())
            return false;

        auto cevent = translateEvent(child, event);
        return child.handleInput(cevent);
    }

    //directly deliver an event to this widget (without considering children or
    //  proper event routing)
    protected final void deliverDirectEvent(InputEvent event) {
        if (!gui)
            return;
        gui.deliverDirectEvent(this, event);
    }

    //return true if tab-handling steals the event
    private bool checkTabKey(InputEvent event) {
        if (!event.isKeyEvent)
            return false;

        if (event.keyEvent.code == Keycode.TAB
            && findBind(event.keyEvent) == "" && !usesTabKey)
        {
            bool shift = modifierIsExact(event.keyEvent.mods, Modifier.Shift);
            bool none = event.keyEvent.mods == 0;

            if (none || shift) {
                if (event.keyEvent.isPress)
                    nextFocus(shift);
                //always eat all tab key events (down, up events)
                return true;
            }
        }

        return false;
    }

    //return an event changed so that the child can handle it; currently
    //translates the mouse positions to the child's coordinate system
    //child must be a direct child of this
    InputEvent translateEvent(Widget child, InputEvent event) {
        assert(child.parent is this);
        debug if (event.isMouseEvent)
            assert(event.mousePos == event.mouseEvent.pos);
        event.mousePos = child.coordsFromParent(event.mousePos);
        if (event.isMouseEvent) {
            event.mouseEvent.pos = event.mousePos;
        }
        return event;
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    //override if you internally use the <tab> key (blocks <tab> focus changing)
    //(keybindings can always override, no need to use this)
    protected bool usesTabKey() {
        return false;
    }

    // --- focus handling

    /// The user can set whether the widget is supposed to be focusable.
    /// If it really can be focused depends from visible/enabled state (see
    /// canTakeInput()).
    /// If a container has focusable==false, child widgets still can be focused.
    protected final void focusable(bool s) {
        mFocusable = s;
        pollFocusState();
    }
    protected final bool focusable() {
        return mFocusable;
    }

    /// if this returns false, sub widgets aren't allowed to take focus
    /// must call pollFocusState() if the return value changed
    //xxx really need to decide if those options should be (protected)
    //    properties or just virtual functions
    protected bool allowSubFocus() {
        return true;
    }

    private bool checkSubFocus() {
        if (!parent)
            return true;
        return parent.allowSubFocus() && parent.checkSubFocus();
    }

    /// If a widget could actually take focus under the current conditions.
    final bool canFocus() {
        return focusable() && canTakeInput() && checkSubFocus();
    }

    /// Return true if focus should set to this element when it becomes active.
    /// Only used if focusable() is true.
    bool greedyFocus() {
        return false;
    }

    ///if true, try to focus child widgets instead of this widget; accept focus
    /// only if this isn't possible
    ///needed e.g. for Windows
    ///only matters if canFocus() is true and there are child widgets
    protected bool doesDelegateFocusToChildren() {
        return false;
    }

    /// claim global focus (try to make this.focused() == true)
    /// return success
    final bool claimFocus() {
        //do this before exiting-on-failure, because next time the widget is
        //  visible, the focus claim can be executed
        //(not sure if this is a good idea)
        mFocusAge = ++gNextFocusAge;

        if (focused)
            return true;
        if (!gui || !canFocus())
            return false;

        if (doesDelegateFocusToChildren()) {
            //try to focus any child
            if (subFocused())
                return true;
            if (focusSomething(false))
                return true;
        }

        //actual change
        auto old = gui.mFocus;
        gui.mFocus = this;
        if (old)
            old.pollFocusState();
        pollFocusState();
        return true;
    }

    //focus in reaction to a mouse click
    //this one tries to focus parent widgets (claimFocus() mustn't do this)
    final bool focusOnInput() {
        if (!checkSubFocus()) {
            //sub-focus stuff makes focusOnInput recursively claim focus
            if (parent)
                return parent.focusOnInput();
        }
        return claimFocus();
    }

    /// if globally focused
    final bool focused() {
        return gui ? gui.mFocus is this : false;
    }

    /// if this widget contains a focused widget
    /// if w.focused() => w.subFocused() == true
    final bool subFocused() {
        if (!gui)
            return false;
        auto focus = gui.mFocus;
        return isTransitiveChild(focus);
    }

    //fix up focus state; call when...
    //- focus was explicitly changed
    //- focusable(), canFocus(), canTakeInput() return values changed
    //does nothing if nothing has actually changed
    final void pollFocusState() {
        if (focused() && !canFocus()) {
            //break old focus
            assert(!!gui());
            if (gui.mFocus is this) {
                //defocus
                gui.mFocus = null;
                pollFocusState();
                //switch focus to something else
                focusSomething();
            }
        }

        if (mOldFocus != focused()) {
            mOldFocus = focused();
            log("focus={} for {}", mOldFocus, this);
            onFocusChange();
        }
    }

    /// called when focused() changes
    /// default implementation: set Widget zorder to front
    protected void onFocusChange() {
        //log("focus change for {}: {}", this, focused());
        //also adjust zorder, else it looks strange
        if (focused)
            toFront();
        styles.setState("focused", focused);
    }

    //focus something when the focused widget was removed from the GUI tree
    //if global==false, the widget must be a direct or indirect child of this
    //  widget, and if nothing is found do nothing; never focus "this"
    final bool focusSomething(bool global = true) {
        Widget best = focus_find_something(global);

        log("focus something {} {} {}", global, this, best);

        if (!best)
            return false;
        return best.claimFocus();
    }

    //find a focusable widget (see focusSomething)
    //also used to find out if something is focusable
    private Widget focus_find_something(bool global) {
        if (!gui)
            return null;

        //special case if not global: never focus "this" (claimFocus needs it)
        Widget exclude = global ? null : this;

        //search the whole gui for a focusable widget with the highest "age"
        Widget best;
        void find(Widget w) {
            if (!w)
                return;
            if (w.canFocus() && w !is exclude) {
                if (!best || w.mFocusAge > best.mFocusAge)
                    best = w;
            }
            foreach (c; w.mZWidgets) {
                find(c);
            }
        }
        find(global ? gui.mRoot : this);
        return best;
    }

    //run fix_focus_up() on child and all its children
    private void fix_focus_on_add(Widget child) {
        if (!gui)
            return;
        //have to do this with all children of child
        //because any child may be the focusable one
        void rec(Widget w) {
            fix_focus_up(w);
            foreach (s; w.mWidgets) {
                rec(s);
            }
        }
        rec(child);
    }

    //1. focus "greedy focus" widgets
    //2. possibly delegate focus to sub-children as they are created
    private void fix_focus_up(Widget child) {
        if (child.parent is this) {
            if (child.greedyFocus())
                child.claimFocus();
        }

        if (focused() && child.canFocus() && doesDelegateFocusToChildren()) {
            //delegate the focus to the child
            child.claimFocus();
        }

        if (parent)
            parent.fix_focus_up(child);
    }

    //rel=-1 for previous sibling, rel=+1 for next
    protected Widget directSibling(int rel) {
        if (!parent)
            return null;
        int idx = marray.arraySearch(parent.mWidgets, this);
        assert(idx >= 0);
        idx += rel;
        return (idx >= 0 && idx < parent.mWidgets.length)
            ? parent.mWidgets[idx] : null;
    }
    //like directSibling(), but walk the tree to get siblings
    //the tree is always traversed in preorder (parent comes first)
    //it's circular and thus never returns null
    protected Widget neighborWidget(int rel) {
        assert(rel == -1 || rel == +1);
        if (rel > 0) {
            if (mWidgets.length)
                return mWidgets[0];
            Widget cur = this;
            for (;;) {
                if (auto n = cur.directSibling(1))
                    return n;
                if (!cur.parent)
                    break;
                cur = cur.parent;
            }
            return cur;
        } else {
            auto pre = (!parent) ? this : directSibling(-1);
            if (!pre)
                return parent;
            for (;;) {
                if (!pre.mWidgets.length)
                    return pre;
                pre = pre.mWidgets[$-1];
            }
        }
    }

    /// focus the next element inside (containers) or after this widget
    /// used to focus the next element using <tab>
    /// normal Widgets call their parent to focus the next widget
    /// Containers try to focus the next child and call their parent
    ///    if that fails
    /// set invertDir = true to go to the previous element
    void nextFocus(bool invertDir = false) {
        if (!gui)
            return;
        Widget cur = gui.mFocus;
        if (!cur)
            cur = this; //what

        Widget window = cur;
        while (window) {
            if (!window.allowLeaveFocusByTab())
                break;
            window = window.parent;
        }

        //find the next focusable widget after "cur"
        //or before "cur" if invertDir==true
        int dir = invertDir ? -1 : +1;
        Widget start = cur;

        for (;;) {
            cur = cur.neighborWidget(dir);
            if (cur is start)
                break;
            if (!cur.canFocus())
                continue;
            if (window && !window.isTransitiveChild(cur))
                continue;
            //never focus a widget which would delegate its focus to another
            //  widget (this breaks tabbing through the widget list)
            if (cur.doesDelegateFocusToChildren()
                && cur.focus_find_something(false))
                continue;
            //all ok
            break;
        }

        log("nextFocus({}): start={} found={}", invertDir, start, cur);

        cur.claimFocus();
    }

    //another special case for windows
    //if true, focus by tab must be any (transitive) child
    protected bool allowLeaveFocusByTab() {
        return true;
    }

    // --- captures
    //there are mouse and key captures; both disable the global
    //event dispatch mechanism (mouse events are normally dispatched by zorder
    //and testMouse, key events by focus) and pass all events to the grabbing
    //Widget
    //be aware that this really blocks all global events, which may be nasty
    //(mouse and key captures can be easily separated if needed, see Container)

    //events are delivered even to non-focusable Widgets when captured
    //removing a widget breaks the capture

    //mouse = capture applies to mouse events (mouse move, mouse button clicks)
    //key = capture applies to keyboard events
    //direct = true: directly send to this widget (handleChildEvents not called)
    //direct = false: send to this widget and then use normal event routing
    //return = success (can fail if not linked to GUI or capture is already set
    //         for a different widget)
    final bool captureEnable(bool mouse, bool key, bool direct) {
        if (!gui)
            return false;
        if (gui.captureUser && gui.captureUser !is this)
            return false;
        gui.captureUser = this;
        gui.captureUser_key = key;
        gui.captureUser_mouse = mouse;
        gui.captureUser_direct = direct;
        return true;
    }

    //return = if the capture was set to this widget
    //if false is released, the capture state isn't changed
    final bool captureRelease() {
        if (!gui)
            return false;
        if (gui.captureUser !is this)
            return false;
        gui.captureUser = null;
        return true;
    }

    //called whenever captureUser is set from this widget to something else
    //protected void onCaptureLost() {
    //}

    // --- simulation and drawing

    //what cursor should be displayed when the mouse is over this Widget
    //(GUI picks the deepest Widget in the hierarchy where mouse events go to)
    MouseCursor mouseCursor() {
        return MouseCursor.Standard;
    }

    //re-read all style properties (doing fine-grained per-properties updates
    //  would be too complicated)
    //can be overridden by derived widget classes
    protected void readStyles() {
        mBorderStyle.border = styles.get!(Color)("border-color");
        mBorderStyle.back = styles.get!(Color)("border-back-color");
        mBorderStyle.bevel = styles.get!(Color)("border-bevel-color");
        mBorderStyle.drawBevel = styles.get!(bool)("border-bevel-enable");
        mBorderStyle.noRoundedCorners = styles.get!(bool)("border-not-rounded");
        mBorderStyle.borderWidth = styles.get!(int)("border-width");
        mBorderStyle.cornerRadius = styles.get!(int)("border-corner-radius");
        mWidgetPad = styles.get!(int)("widget-pad");

        char[] back = styles.get!(char[])("bitmap-background-res");
        mBmpBackground = back == "" ? null : gGuiResources.get!(Surface)(back);

        //draw-border is a misnomer, because it has influence on layout (size)?
        mDrawBorder = styles.get!(bool)("border-enable");
    }

    //check if there were style changes, and if yes, do all necessary updates
    //NOTE: widget addition code will use different code for various reasons to
    //      handle the initial readStyles() call
    final void updateStyles() {
        styles.checkChanges();
        if (!isLinked())
            return;
        if (!styles.didChange)
            return;
        styles.didChange = false;
        readStyles();
        needResize();
    }

    //like updateStyles(), but disregard change-check; needed by style overrides
    final void forceUpdateStyles() {
        styles.didChange = true;
        updateStyles();
    }

    //override a specific style property (name) with a constant value
    //box must have the correct type
    //exception: an empty box resets the style override
    //unknown/mistyped names will be silently ignored
    final void setStyleOverride(char[] name, MyBox value) {
        if (value.empty) {
            mStyleOverrides.remove(name);
        } else {
            if (!styles.onStyleOverride)
                styles.onStyleOverride = &styleOverrideCb;
            mStyleOverrides[name] = value;
        }
        forceUpdateStyles();
    }

    //helper
    final void setStyleOverrideT(T)(char[] name, T val) {
        setStyleOverride(name, MyBox.Box(val));
    }
    final void clearStyleOverride(char[] name) {
        setStyleOverride(name, MyBox());
    }

    private MyBox styleOverrideCb(StylesLookup sender, char[] name, MyBox orig)
    {
        if (auto pval = name in mStyleOverrides)
            return *pval;
        return orig;
    }

    //xxx make final, after removing SOMEONE's hack in gameframe.d
    void internalSimulate() {
        updateStyles();
        foreach (obj; mWidgets) {
            obj.internalSimulate();
        }
        simulate();
    }

    void simulate() {
    }

    //small hack for window.d (would be much more complicated without)
    protected void onDrawBackground(Canvas c, Rect2i area) {
        if (drawBorder) {
            drawBox(c, area, mBorderStyle);
        }

        if (mBmpBackground) {
            if (styles.get!(bool)("bitmap-background-tile")) {
                c.drawTiled(mBmpBackground, area.p1, area.size);
            } else {
                c.draw(mBmpBackground, area.p1 + area.size/2
                    - mBmpBackground.size/2);
            }
        }
    }

    final void doDraw(Canvas c) {
        if (!mVisible)
            return;

        //early out if it isn't visible at all
        if (!c.visibleArea.intersects(mBorderArea+mAddToPos))
            return;

        c.pushState();
        onDrawBackground(c, mBorderArea+mAddToPos);
        if (doClipping) {
            //map (0,0) to the position of the widget and clip by widget-size
            c.setWindow(mContainedWidgetBounds.p1+mAddToPos,
                mContainedWidgetBounds.p2+mAddToPos);
        } else {
            //xxx don't know if this enough, since setWindow() also affects the
            //clientSize() stuff; but then again, GUI widgets which use this
            //rely on clipping
            c.translate(mContainedWidgetBounds.p1+mAddToPos);
        }
        if (canScale && mScale.length != 1.0f)
            c.setScale(mScale);

        auto background = styles.get!(Color)("widget-background");
        if (background.a >= Color.epsilon) {
            c.drawFilledRect(Vector2i(0), size, background);
        }

        //user's draw routine
        onDraw(c);

        onDrawChildren(c);

        version (WidgetDebug) {
            c.drawRect(widgetBounds, Color(1,focused ? 1 : 0,0));
        }

        c.popState();

        //xxx shouldn't overdraw children graphics; only here because focus rect
        // is extended to border area
        onDrawFocus(c);

        //small optical hack: highlighting
        //feel free to replace this by better looking rendering
        //here because of drawing to nonclient area
        auto highlightAlpha = styles.get!(float)("highlight-alpha");
        if (highlightAlpha > 0) {
            //brighten
            c.drawFilledRect(mBorderArea + mAddToPos,
                Color(1,1,1,highlightAlpha));
        } else if (highlightAlpha < 0) {
            //disabled, so overdraw with gray
            c.drawFilledRect(mBorderArea + mAddToPos,
                Color(0.5,0.5,0.5,-highlightAlpha));
        }
    }

    //can be used with Widget.checkCover (used if that is true)
    //a return value of true means it covers the _container's_ area completely
    //the container then doesn't draw all widgets with lower zorder
    //use with care
    bool doesCover() {
        return false;
    }

    ///you should override this for custom drawing / normal widget rendering
    protected void onDraw(Canvas c) {
    }

    protected void onDrawChildren(Canvas c) {
        if (!checkCover) {
            //normal case
            foreach (obj; mZWidgets) {
                obj.doDraw(c);
            }
        } else {
            //special hack-like thing to speed up drawing *shrug*
            //if a widget fully covers other widgets, don't draw the other ones
            Widget last_cover;
            foreach (obj; mZWidgets) {
                if (obj.doesCover)
                    last_cover = obj;
            }
            bool draw = !last_cover;
            foreach (obj; mZWidgets) {
                draw |= obj is last_cover;
                if (draw)
                    obj.doDraw(c);
            }
        }
    }

    ///default focus drawing
    ///this is specially called here, because the user may just override onDraw,
    /// and forget about the focus stuff; if the drawing is bogus, the stupid
    /// implementer will notice it and will have to do something about it, like
    /// adding proper drawing code by overriding this method (which is why
    /// there's no simpler method of disabling this code)
    ///xxx not sure about the drawing context; right now it's in non-client
    /// area, but this may change
    protected void onDrawFocus(Canvas c) {
        if (!focused())
            return;

        auto rc = containedBorderBounds();
        const border = 3;
        auto s = rc.size;
        if (border*2 < min(s.x, s.y)) {
            rc.extendBorder(Vector2i(-border));
        }
        c.drawStippledRect(rc, Color(0.5), 2);
    }

    ///when drawing, add an additional offset to the Widget for the purpose of
    ///animation - it has no influence on anything else like input handling, the
    ///reported Widget position, or Widget layouting
    void setAddToPos(Vector2i delta) {
        mAddToPos = delta;
    }
    Vector2i getAddToPos() {
        return mAddToPos;
    }

    protected void clear() {
        while (children.length > 0) {
            removeChild(children[$-1]);
        }
    }

    // --- blabla rest

    /// load Widget properties from a config file, i.e. the WidgetLayout
    /// (needRelayout() is guaranteed to be called after this, so the Widget
    ///  will be relayouted)
    /// NOTE: normally, loadFrom() shall only reset the fields mentioned in
    ///       loader.node() (and leave all other fields as they are, but
    ///       containers can remove all their children before reloading
    void loadFrom(GuiLoader loader) {
        auto lay = loader.node.findNode("layout");
        if (lay) {
            mLayout.loadFrom(lay);
        }

        zorder = loader.node.getIntValue("zorder", zorder);
        mVisible = loader.node.getBoolValue("visible", mVisible);
        enabled = loader.node.getBoolValue("enabled", mEnabled);
        mMinSize = loader.node.getValue("min_size", mMinSize);

        mDrawBorder = loader.node.getBoolValue("draw_border", mDrawBorder);

        auto bnode = loader.node.findNode("border_style");
        if (bnode)
            assert(false == false);

        tooltip = loader.locale()(loader.node.getStringValue("tooltip",
            tooltip));

        //xxx not possible anymore - has to use style classes etc...
        /+
        if (auto stnode = loader.node.findNode("styles")) {
            styles.addRules(stnode);
        }
        +/

        styles.addClasses(str.split(loader.node.getStringValue("style_class")));

        //xxx: load KeyBindings somehow?
        //...

        needRelayout();
    }

    void onLocaleChange() {
        foreach (w; children) {
            w.onLocaleChange();
        }
    }

    //only intended for debugging; not to subvert any protection
    //rather use this.children() (which is protected)
    void enumChildren(void delegate(Widget w) callback) {
        foreach (w; children.dup) {
            callback(w);
        }
    }
}

//top-level-widget, only one instance of this is allowed per GUI
//also provides methods to add Widgets
final class MainFrame : Widget {
    private this(GUI top) {
        super();
        mGUI = top;
        styles.parent = mGUI.stylesRoot;

        doMouseEnterLeave(true); //mous always in, initial event
        pollFocusState();

        gOnChangeLocale ~= &onLocaleChange;
    }

    void add(Widget obj) {
        addChild(obj);
    }

    void add(Widget obj, WidgetLayout layout) {
        setChildLayout(obj, layout);
        addChild(obj);
    }

    override bool doesDelegateFocusToChildren() {
        return true;
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }
}

//global GUI information
//if I were sane, this would be just a bunch of global variables
final class GUI {
    private {
        //where the last mouse-event did go to - used for the mousecursor
        //this widget will also be the one with mouse over = true
        //this may change on every input event
        Widget mMouseWidget;

        //Widget which currently unconditionally gets all mouse input events
        //  because a mouse button was pressed down (releasing all mouse buttons
        //  undoes it)
        Widget mCaptureMouse;
        //same for key-events; this makes sure the Widget receiving the key-down
        //  event also receive the according key-up event
        Widget mCaptureKey;

        //user-requested mouse/keyboard capture, which works the same as above
        //used at least by the mouse scroller
        Widget captureUser;
        //which event types captureUser should catch
        bool captureUser_key, captureUser_mouse;
        //if false, events to captureUser are sent using the proper event
        //  dispatching mechanism - just that event dispatching starts at
        //  captureUser
        //(mCaptureKey and mCaptureMouse always use true for this option)
        bool captureUser_direct;

        MouseCursor mMouseCursor = MouseCursor.Standard;
        StylesBase mStyleRoot;
        MainFrame mRoot; //container with all further widgets
        Vector2i mSize;
        Widget mFocus;

        //only for mCaptureKey stuff (idiotically, framework also contains a
        //keystate array, can be queried with Framework.getKeyState())
        //this keeps track which key-down events were sent to mCaptureKey widget
        bool[Keycode.max+1] mCaptureKeyState;
    }

    this() {
        //first parent, this is used to provide default values for all
        //properties; the actual GUI styling should be somewhere else
        mStyleRoot = new StylesPseudoCSS();

        //load the theme (it's the theme because this is the top-most widget)
        auto themes = listThemes();
        loadTheme(themes.length ? themes[0] : "");

        mRoot = new MainFrame(this);
    }

    MainFrame mainFrame() {
        return mRoot;
    }

    StylesBase stylesRoot() {
        return mStyleRoot;
    }

    void size(Vector2i size) {
        mSize = size;
        mRoot.layoutContainerAllocate(Rect2i(Vector2i(0), size));
    }

    Vector2i size() {
        return mSize;
    }

    //return the widget with the current focus
    Widget focused() {
        return mFocus;
    }

    //return if any mouse button is down; this should be ok even "during"
    //dispatching input, because the Framework's getKeyState() is synchronous to
    //the events it pushes into the GUI
    static bool anyMouseButtonPressed() {
        return gFramework.anyButtonPressed(false, true);
    }

    private struct InputInfo {
        Widget widget;
        bool direct;
    }

    //which widget is going to get the input, and how
    private InputInfo getInputTarget(InputEvent event) {
        bool bymouse = event.isMouseRelated;

        if (bymouse && mCaptureMouse)
            return InputInfo(mCaptureMouse, true);

        if (captureUser
            && (captureUser_key != bymouse || captureUser_mouse == bymouse))
            return InputInfo(captureUser, captureUser_direct);

        return InputInfo(mRoot, false);
    }

    //translate the event (i.e. adjust mouse coordinates) until widget "to"
    private InputEvent translateEventUntil(Widget to, InputEvent event) {
        assert(!!to);
        if (to.parent) {
            event = translateEventUntil(to.parent, event);
            event = to.parent.translateEvent(to, event);
        }
        return event;
    }

    void putInput(InputEvent event) {
        auto oldmouse = mMouseWidget;

        //captures always take all events globally
        //old code used to make captures local to containing widgets
        auto dest = getInputTarget(event);

        event = translateEventUntil(dest.widget, event);

        if (!dest.direct) {
            //send using the usual event routing (mouse pos, keyboard focus)
            bool handled = dest.widget.handleInput(event);
            if (!handled)
                log("unhandled event: {}", event);
        } else {
            //send event directly to receiver (== don't route the event using
            //  focus, mouse position etc.); also don't try to send events to
            //  children of that widget (intended)
            deliverDirectEvent(dest.widget, event);
        }

        //when a mouse button is released, generate an artifical mouse move
        //  event to deal with the mouse enter/leave-events and the mouse cursor
        if (mCaptureMouse && !anyMouseButtonPressed()) {
            mCaptureMouse = null;
            log("mouse capture release");
            fixMouse();
        }

        //for simplification, the mouse over state works only on the mouse event
        //  receiving widget, instead of all widgets (containers...) in the
        //  tree; maybe this is bad, e.g. what if a button was composed of a
        //  frame widget and a label sub-widget?
        if (oldmouse !is mMouseWidget) {
            if (oldmouse) oldmouse.doMouseEnterLeave(false);
            if (mMouseWidget) mMouseWidget.doMouseEnterLeave(true);
        }
    }

    //generate artificial mouse move to fix up mouse related state
    //e.g. mouse over state and mouse cursor icon
    void fixMouse() {
        //sadly, the generated mouse move events are often redundant hrmm
        InputEvent ie;
        ie.isMouseEvent = true;
        ie.mousePos = gFramework.mousePos();
        ie.mouseEvent.pos = ie.mousePos;
        ie.mouseEvent.rel = Vector2i(0); //what would be the right thing?
        mRoot.handleInput(ie);
    }

    //always called when a Widget definitely receives a keyboard event
    //this code takes care of sending artificial key-release events for all
    //keys that were pressed, if mCaptureKey changes
    private void updateKeyCapture(Widget w, KeyInfo event) {
        if (!event.isDown() && !event.isUp())
            return;

        assert(!!w);

        if (mCaptureKey !is w) {
            log("capture key {} -> {}", mCaptureKey, w);
            //input widget changed; send release events to old widget
            auto old = mCaptureKey;
            foreach (int i, ref bool state; mCaptureKeyState) {
                if (!state)
                    continue;
                //if this happens, it means mCaptureKey and mCaptureKeyState can
                //somehow change when calling the event handlers; so should the
                //assertion fail, you should at least ensure no bogus events are
                //sent
                assert(old is mCaptureKey);
                state = false;
                if (old) {
                    //slightly evil: call user event handler directly?
                    KeyInfo e;
                    e.type = KeyEventType.Up;
                    e.code = cast(Keycode)i;
                    //e.unicode = oops
                    //e.mods = huh
                    old.onKeyEvent(e);
                }
            }
            mCaptureKey = null;
        }

        mCaptureKey = w;
        mCaptureKeyState[event.code] = event.isDown();

        //if we get the event and a mouse button is hold, we should receive all
        //  other mouse events until no mouse button is down anymore
        if (!mCaptureMouse && event.isMouseButton) {
            log("mouse capture: {}", w);
            mCaptureMouse = w;
        }
    }

    //called by Widget (xxx idiotic code structure, move to Widget)
    private void deliverDirectEvent(Widget receiver, InputEvent event) {
        log("deliver event to {}: {}", receiver, event);

        if (receiver.checkTabKey(event)) {
            log("tab stuff eats event");
            return;
        }

        if (event.isMouseRelated) {
            receiver.mMousePos = event.mousePos;
        }

        //set focus on mouse down clicks
        //xxx: mouse wheel will set focus too, is that ok?
        if (event.isKeyEvent && event.isMouseRelated && event.keyEvent.isDown)
            receiver.focusOnInput();

        if (event.isKeyEvent) {
            //keyboard capture, so that artificial key-release events are always
            //generated (e.g. on focus change while key is pressed)
            updateKeyCapture(receiver, event.keyEvent);

            receiver.onKeyEvent(event.keyEvent);
        } else if (event.isMouseEvent) {
            //usually used for the mouse cursor
            //NOTE: not for mouse click events... this is a hack to prevent the
            //  mouse cursor from appearing for a brief moment, if you right
            //  click into a MouseScroller (which is what the game uses)
            if (mMouseWidget !is receiver) {
                log("set mouse cursor widget: {} -> {}", mMouseWidget,
                    receiver);
                mMouseWidget = receiver;
            }

            receiver.onMouseMove(event.mouseEvent);
        }
    }

    //w goes from isLinked==true to isLinked==false
    //xxx what about disabling input focus/events in various ways
    private void do_remove(Widget w) {
        void checkrm(ref Widget r) {
            if (r is w)
                r = null;
        }
        checkrm(mMouseWidget);
        checkrm(mCaptureKey);
        checkrm(mCaptureMouse);
        checkrm(captureUser);
        checkrm(mFocus);
    }

    //execute per-frame updates (it is unknown why this isn't done on drawing)
    //also adjusts mouse cursor icon
    void frame() {
        //when a widget gets removed, the focused widget may be unlinked, and
        //  the focus is left unclaimed
        if (!mFocus) {
            log("fix focus");
            mRoot.focusSomething();
        }

        mRoot.internalSimulate();

        mMouseCursor = mMouseWidget ? mMouseWidget.mouseCursor()
            : MouseCursor.Standard;

        gFramework.mouseCursor = mMouseCursor;
    }

    void draw(Canvas c) {
        mRoot.doDraw(c);
    }

    //xxx not very happy about having filesystem code and dependencies in the
    //    GUI core
    const cThemeFolder = "/gui_themes/";
    const cThemeNone = "<none>";

    //theme = relative filename of the theme, can be cThemeNone for no theme
    void loadTheme(char[] theme) {
        log("load theme '{}'", theme);
        mStyleRoot.clearRules();
        loadRules(loadConfig("gui_style_root"));
        if (theme != cThemeNone)
            loadRules(loadConfig(cThemeFolder ~ theme, true));
    }

    void loadRules(ConfigNode from) {
        mStyleRoot.addRules(from.getSubNode("styles"));
    }

    static char[][] listThemes() {
        //xxx in i18n we have something similar, the code in i18n looks reboster
        char[][] list;
        gFS.listdir(cThemeFolder, "*.conf", false, (char[] filename) {
            list ~= filename;
            return true;
        });
        //sorting prevents random order
        list.sort;
        list ~= cThemeNone;
        return list;
    }

    static Log getLog() {
        return log;
    }
}

//only used for Widget.loadFrom(), implemented in loader.d
//used mostly to avoid cyclic dependencies
interface GuiLoader {
    //node specific to the currently loaded Widget
    ConfigNode node();
    //load another Widget which can be used e.g. as a child
    Widget loadWidget(ConfigNode from);
    //locale of current config file
    Translator locale();
}

//just a trivial Widget: have a minimum size and draw a color on its background
class Spacer : Widget {
    this() {
        focusable = false;
    }

    static this() {
        WidgetFactory.register!(typeof(this))("spacer");
    }
}

class UnclickableSpacer : Spacer {
    this() {
        focusable = false;
        isClickable = false;
    }

    static this() {
        WidgetFactory.register!(typeof(this))("unclickablespacer");
    }
}

/// Widget factory; anyone can register here.
/// Used by module gui.layout to create Widgets from names.
alias StaticFactory!("Widgets", Widget) WidgetFactory;

