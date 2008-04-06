module gui.widget;

import framework.framework;
import framework.event;
import gui.container;
import gui.gui;
import utils.configfile;
import utils.factory;
import utils.mylist;
import utils.time;
import utils.vector2;
import utils.rect2;
import utils.log;

//debugging (draw a red frame for the widget's bounds)
//version = WidgetDebug;

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

        bool mMouseOverState;

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

    ///clip graphics to the inside
    bool doClipping = true;

    package static Log log() {
        return registerLog("GUI");
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

    //recursively searches the tree until toplevel-widget is found
    //returns null if the Widget-tree is unlinked from the GUI
    package MainFrame getTopLevel() {
        Widget w = this;
        while (w) {
            if (auto m = cast(MainFrame)w)
                return m;
            w = w.parent;
        }
        return null;
    }

    ///return if the Widget is linked into the GUI hierarchy, which means it
    ///can be visible, receive events, do layouting etc...
    ///simply having a parent is not enough for this for various silly reasons
    final bool isLinked() {
        //it's ok if it's reachable
        return !!getTopLevel();
    }

    ///return true if other is a direct or indirect parent of this
    /// also returns true for a.isTransitiveChildOf(a)
    final bool isTransitiveChildOf(Widget other) {
        auto cur = this;
        while (cur) {
            if (cur is other)
                return true;
            cur = cur.parent;
        }
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
    /// Widgets should override this; by default returns always (0,0).
    protected Vector2i layoutSizeRequest() {
        return Vector2i(0);
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
            /+auto diff = size - layoutCachedContainerSizeRequest();
            if (diff.x < 0 || diff.y < 0) {
                std.stdio.writefln("warning: diff=%s for %s",diff,this);
            }+/
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
                ;//+ mLayout.pad + mLayout.padA[n];
            //remove the border from the size (the size is for the widget)
            //rsize[n] = rsize[n] - mLayout.pad - mLayout.padA[n] - mLayout.padB[n];
        }
        auto pad = Vector2i(mLayout.pad, mLayout.pad);
        auto ba = mLayout.padA + pad;
        auto bb = mLayout.padB + pad;
        area.p1 += offset + ba;
        area.p2 = area.p1 + rsize - ba - bb;
    }

    // --- input handling

    ///check if the mouse "hits" this gui object
    ///by default all what the bounding box can get, but for the sake of
    ///overengineering, anything is possible
    protected bool onTestMouse(Vector2i pos) {
        return true;
    }

    ///Check where the Widget should receive mouse events
    /// pos = mouse position in local coordinates
    ///(like onTestMouse; this wrapper function is here to enforce the
    ///restriction to widget bounds)
    final bool testMouse(Vector2i pos) {
        auto s = size;
        return (pos.x >= 0 && pos.y >= 0 && pos.x < s.x && pos.y < s.y)
            && onTestMouse(pos);
    }

    //event handler which can be overridden by the user
    //this function shall return true if the event was handled
    //if it doesn't handle an event, an overridden method must call the super-
    //handler and return its result
    //NOTE about down/up/press events: even though you react only i.e. on key-up
    // events in a specific case, always catch down- and press-events as well,
    // else other Widgets might receive this events, leading to stupid confusion
    protected bool onKeyEvent(KeyInfo info) {
        //default: do nothing, return false (to indicate "unhandled")
        return false;
    }

    //return true only if you want block this event for children
    //no meaning for non-Container Widgets (?)
    //  (actually, when children are overlapping and this returns true, the
    //   other (overlapping) children won't get the mouse event)
    protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }

    protected void onMouseEnterLeave(bool mouseIsInside) {
    }

    //calls onMouseEnterLeave(), but avoid unnecessary recursion (cf. Container)
    //(and also is "package" to deal with the stupid D protection attributes)
    void doMouseEnterLeave(bool mii) {
        if (mMouseOverState != mii) {
            mMouseOverState = mii;
            onMouseEnterLeave(mii);
        }
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

    //called by the owning Container only
    package void updateMousePos(Vector2i pos) {
        mMousePos = pos;
    }

    //return if any mouse button is down; this should be ok even "during"
    //dispatching input, because the Framework's getKeyState() is synchronous to
    //the events it pushes into the GUI
    static bool anyMouseButtonPressed() {
        return gFramework.anyButtonPressed(false, true);
    }

    //called whenever an input event passes through this
    final void doDispatchInputEvent(InputEvent event) {
        if (event.isMouseRelated) {
            updateMousePos(event.mousePos);
            doMouseEnterLeave(true);
        }
        dispatchInputEvent(event);
    }

    protected void dispatchInputEvent(InputEvent event) {
        //when this is called it means this Widget definitely gets the event
        auto m = getTopLevel();
        if (event.isMouseRelated() && m) {
            //usually used for the mouse cursor
            m.mouseWidget = this;
            //care about capturing - if we get the event and a mouse button
            //is hold, we should receive all other mouse events until no
            //mouse button is down anymore (see MainFrame)
            if (!m.captureMouse && anyMouseButtonPressed()) {
                log()("capture: %s -> %s", m.captureMouse, this);
                m.captureMouse = this;
            }
        }
       // std.stdio.writefln("disp: %s %s", this, event);
        if (event.isKeyEvent) {
            onKeyEvent(event.keyEvent);
        } else if (event.isMouseEvent) {
            onMouseMove(event.mouseEvent);
        }
    }

    //only useful for Container
    //normal Widgets can only return this, or null to refuse the input
    Widget findInputDispatchChild(InputEvent event) {
        return this;
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    // --- simulation and drawing

    //what cursor should be displayed when the mouse is over this Widget
    //(GUI picks the deepest Widget in the hierarchy where mouse events go to)
    MouseCursor mouseCursor() {
        return MouseCursor.Standard;
    }

    //overridden by Container
    void internalSimulate() {
        simulate();
    }

    void simulate() {
    }

    void doDraw(Canvas c) {
        c.pushState();
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

        //user's draw routine
        onDraw(c);

        version (WidgetDebug) {
            c.drawRect(widgetBounds, Color(1,focused ? 1 : 0,0));
        }

        c.popState();
    }

    //can be used with Container.checkCover (used if that is true)
    //a return value of true means it covers the _container's_ area completely
    //the container then doesn't draw all widgets with lower zorder
    //use with care
    bool doesCover() {
        return false;
    }

    ///you should override this for custom drawing / normal widget rendering
    protected void onDraw(Canvas c) {
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


    // --- focus handling

    /// Return true if this can have a focus (used for treatment of <tab>).
    /// default implementation: return false
    /// use Container.childCanHaveFocus() to know the real value, because
    /// Containers might disable their children for stupid reasons SIGH
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
    /// return success
    final bool claimFocus() {
        //in some cases, this might even safe you from infinite loops
        if (focused)
            return true;
        //set focus: recursively claim focus on parents
        if (parent) {
            parent.localFocus = this; //local
            if (!localFocused())
                return false;
            return parent.claimFocus();      //global (recurse upwards)
        }
        return isTopLevel();
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
        //xxx slightly incorrect because of canHaveFocus
        if (canHaveFocus && !focused) {
            return claimFocus();
        }
        return false;
    }

    /// called when focused() changes
    /// default implementation: set Widget zorder to front
    protected void onFocusChange() {
        log()("global focus change for %s: %s", this, mHasFocus);
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

    // --- captures
    //there are mouse and key captures; both disable the normal per-Container
    //event dispatch mechanism (mouse events are normally dispatched by zorder
    //and testMouse, key events by focus) and pass all events to the grabbing
    //Widget
    //but you still can't capture all _global_ events with this, only the events
    //the Containers pass to their children
    //(mouse and key captures can be easily separated if needed, see Container)

    //keyboard events are delivered even to non-focusable Widgets when captured

    //return value: if operation was successful (a capture can only be canceled/
    //replaced by the Widget which did set it)
    final bool captureSet(bool set) {
        auto m = getTopLevel();
        if (!m)
            return !set;
        if (m.captureUser && m.captureUser !is this)
            return false;
        if ((m.captureUser is this) == set)
            return true;
        //really set/unset
        m.captureUser = set ? this : null;
        return true;
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

        //xxx: load KeyBindings somehow?
        //...

        needRelayout();
    }
}

//only used for Widget.loadFrom(), implemented in loader.d
//used mostly to avoid cyclic dependencies
interface GuiLoader {
    //node specific to the currently loaded Widget
    ConfigNode node();
    //load another Widget which can be used i.e. as a child
    //"from" is a ConfigNode or ConfigValue
    Widget loadWidget(ConfigItem from);
}

//just a trivial Widget: have a minimum size and draw a color on its background
class Spacer : Widget {
    Color color = {1.0f,0,0};
    bool drawBackground = true;

    private Vector2i mMinSize;

    void minSize(Vector2i s) {
        mMinSize = s;
        needResize(true);
    }
    Vector2i minSize() {
        return mMinSize;
    }

    override protected void onDraw(Canvas c) {
        if (drawBackground) {
            c.drawFilledRect(widgetBounds, color);
        }
    }

    Vector2i layoutSizeRequest() {
        return mMinSize;
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;
        color.parse(node.getStringValue("color"));
        drawBackground = node.getBoolValue("draw_background", drawBackground);
        parseVector(node.getStringValue("min_size"), mMinSize);
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("spacer");
    }
}

/// Widget factory; anyone can register here.
/// Used by module gui.layout to create Widgets from names.
static class WidgetFactory : StaticFactory!(Widget) {
}

static this() {
    WidgetFactory.register!(SimpleContainer)("simplecontainer");
}
