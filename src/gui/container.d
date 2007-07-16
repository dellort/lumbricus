module gui.container;
import common.scene;
import gui.widget;
import gui.gui;
import utils.array;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.log;

//layout parameters which should be useful to all Widgets/Containers
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

/// Group of Widgets, like a window.
/// for own containers, override for layouting:
///   override protected Vector2i layoutSizeRequest();
///   override protected void layoutSizeAllocation();
/// to request sizes/set allocations in these functions:
///   Vector2i layoutDoRequestChild(PerWidget widget);
///   void layoutDoAllocChild(PerWidget widget, Rect2i bounds);
///default behaviour if default args of constructor are used:
///doesn't take focus for itself, but manages children's focus and delegates any
///events to focused children; doesn't draw anything (except its children);
///for layout, allocates all children to its own size and reports maximum size
///of all children as request-size
class Container : Widget {
    private {
        PerWidget[] mWidgets; //sorted by order of insertion
        Widget mFocus; //local focus
        //only grows, wonder what happens if it overflows
        int mCurrentFocusAge;
        //frame is "transparent"
        bool mIsVirtualFrame = true;
        //only one element per child
        bool mIsBinFrame;

        int mLastZOrder2;

        //to send mouse-leave events
        Widget mLastMouseReceiver;
    }

    //used to store container-specific per-widget data
    //can be overridden by derived Containers, cf. newPerWidget()
    //this wouldn't be needed in AspectJ!
    //btw. dmd doesn't want to allow deriving inner classes in derived classes
    //so this is "static" and needs that "container" pointer
    static protected class PerWidget {
        private Widget mChild;
        private Container mContainer;
        private int mFocusAge;
        private int mZOrder;  //any value, higher means more on top
        private int mZOrder2; //what was last clicked, argh

        WidgetLayout layout;

        final Widget child() {
            return mChild;
        }
        final Container container() {
            return mContainer;
        }

        this(Container a_container, Widget a_child) {
            assert(a_child !is null && a_container !is null);
            mChild = a_child;
            mContainer = a_container;

            mZOrder = a_child.zorder;
        }

        protected Vector2i layoutDoRequestChild() {
            auto size = child.internalSizeRequest();
            //just padding
            size.x += layout.pad*2; //both borders for each component
            size.y += layout.pad*2;
            size += layout.padA + layout.padB;
            return size;
        }

        ///a container shall call this to actually alloc a child
        ///this will take care about what happens if the child doesn't get the
        ///requested size, and about alignment, etc., whatever
        ///use with layoutDoRequestChild()
        protected void layoutDoAllocChild(Rect2i area) {
            //xxx doesn't handle under-sized stuff
            Vector2i psize = area.size();
            Vector2i offset;
            auto size = layoutDoRequestChild();
            //fit the widget with its size into the area
            for (int n = 0; n < 2; n++) {
                if (layout.expand[n]) {
                    //fill, 0-1 selects the rest of the size
                    size[n] = size[n]
                        + cast(int)((psize[n] - size[n]) * layout.fill[n]);
                }
                //and align; this again selects the rest of the size
                //and add the border padding (padB is the second border, implicit)
                offset[n] = cast(int)((psize[n] - size[n]) * layout.alignment[n])
                    + layout.pad + layout.padA[n];
                //at the end, remove the border from the size again...
                size[n] = size[n] - layout.pad - layout.padA[n] - layout.padB[n];
            }
            area.p1 = area.p1 + offset;
            area.p2 = area.p1 + size;
            child.internalLayoutAllocation(area);
        }
    }

    //or override these functions, if you want
    protected Vector2i layoutDoRequestChild(PerWidget child) {
        return child.layoutDoRequestChild();
    }
    protected void layoutDoAllocChild(PerWidget child, Rect2i area) {
        return child.layoutDoAllocChild(area);
    }

    //override when needed
    protected PerWidget newPerWidget(Widget child) {
        return new PerWidget(this, child);
    }

    //accept_null = don't assert(result !is null)
    //must_find = widget must be a child of us
    protected PerWidget findChild(Widget child, bool accept_null = false,
        bool must_find = true)
    {
        if (child is null) {
            assert(accept_null);
            return null;
        }

        PerWidget found;
        foreach (w; mWidgets) {
            if (w.child is child) {
                found = w;
                break;
            }
        }

        if (must_find)
            assert(found !is null);

        assert(!!found == (child.parent is this));

        return found;
    }

    //return thought-to-be-invariant array of all children
    //(in D2.0, this could be really a const or an invariant array...)
    protected PerWidget[] children() {
        return mWidgets;
    }

    /// Add GUI element (makes
    protected PerWidget addChild(Widget o) {
        assert(o.parent is null);
        assert(findChild(o, false, false) is null);
        auto pw = newPerWidget(o);
        insertWidget(pw);
        o.internalDoAdd(this);

        gDefaultLog("added %s to %s", o, this);

        return pw;
    }

    /// Remove GUI element; that element gets destroyed.
    /+protected+/ void removeChild(Widget obj) {
        assert(obj.parent is this);
        removeWidget(findChild(obj));
        obj.internalDoRemove(this);

        gDefaultLog("removed %s from %s", obj, this);

        if (obj is mFocus) {
            mFocus = null;
            recheckFocus(); //yyy: check if correct
        }
    }

    ///set this child to highest z-order possible for it (
    void childToTop(Widget child) {
        //xxx: if you need performance here, you must rewrite it completely!
        //in this form, it iterates at least 6 times or so over mWidgets
        //and even changes its size in two cases
        PerWidget w = findChild(child);
        w.mZOrder2 = ++mLastZOrder2;
        updateZFor(w);
    }

    void setChildZOrder(Widget child, int zorder) {
        PerWidget w = findChild(child);
        removeWidget(w);
        w.mZOrder = zorder;
        insertWidget(w);
    }

    //internal; don't use this, use removeChild()
    //override for removal notification
    protected void removeWidget(PerWidget w) {
        arrayRemove(mWidgets, w);
        scene().remove(w.child.scene);
    }
    //insert by z-order
    private void insertWidget(PerWidget w) {
        assert(arraySearch(mWidgets, w) < 0);
        //insert...
        mWidgets ~= w;
        scene().add(w.child.scene);
        updateZFor(w);
    }
    //null = update everything
    private void updateZFor(PerWidget w) {
        //ok, and since 20:16 today this even creates a new array to sort it
        //argh.
        PerWidget[] foo = mWidgets.dup;
        arraySort(foo,
            (PerWidget w1, PerWidget w2) {
                if (w1 == w2) {
                    return w1.mZOrder2 <= w2.mZOrder2;
                } else {
                    return w1.mZOrder <= w2.mZOrder;
                }
            }
        );
        Scene s = scene();
        foreach (wuhu; foo) {
            //confusing, but correct: remove scene and add as tail (=> reorder)
            s.remove(wuhu.child.scene);
            s.add(wuhu.child.scene);
        }
    }

    void setChildLayout(Widget child, WidgetLayout layout) {
        findChild(child).layout = layout;
        needRelayout();
    }

    //if we're a (transitive) parent of obj
    bool isTransitiveParentOf(Widget obj) {
        //assume no cyclic parents
        while (obj) {
            if (obj is this)
                return true;
            obj = obj.parent;
        }
        return false;
    }

    override bool testMouse(Vector2i pos) {
        if (!super.testMouse(pos))
            return false;

        //virtual frame => only if a child was hit
        if (mIsVirtualFrame) {
            foreach (o; mWidgets) {
                if (o.child.testMouse(o.child.coordsFromParent(pos)))
                    return true;
            }
            return false;
        }

        return true;
    }

    //the GuiFrame itself accepts to be focused
    //look at GuiVirtualFrame if the frame shouldn't be focused itself
    override bool canHaveFocus() {
        if (mIsVirtualFrame) {
            //xxx maybe a bit expensive; cache it?
            foreach (o; mWidgets) {
                if (o.child.canHaveFocus)
                    return true;
            }
        }
        return true;
    }
    override bool greedyFocus() {
        if (mIsVirtualFrame) {
            foreach (o; mWidgets) {
                if (o.child.greedyFocus)
                    return true;
            }
        }
        return false;
    }

    /// "Virtual" frame: It just groups all its child object, but isn't visible
    /// itself, doesn't accept any events for itself (only child objects, but
    /// i.e. doesn't take focus or accept mouse events for itself), doesn't draw
    /// anything (except to show child objects),  but it does clipping
    protected void setVirtualFrame(bool v) {
        mIsVirtualFrame = v;
    }

    /// if true, allow only one child and enable getBinChild()
    protected void setBinContainer(bool b) {
        if (b) {
            assert(children.length <= 1);
        }
        mIsBinFrame = b;
    }

    protected PerWidget getBinChild() {
        assert(mIsBinFrame);
        assert(mWidgets.length <= 1);
        return mWidgets.length ? mWidgets[0] : null;
    }

    //focus rules:
    // object becomes active => if greedy focus, set focus immediately
    // object becomes inactive => object which was focused before gets focus
    //    to do that, PerWidget.mFocusAge is used
    // tab => next focusable Widget in scene is focused

    //added = true: o was added newly or o.canhaveFocus got true
    //see recheckChildFocus(Widget o)
    private void doRecheckChildFocus(PerWidget o, bool added) {
        assert(o !is null);
        if (added) {
            if (o.child.canHaveFocus && o.child.greedyFocus) {
                o.mFocusAge = ++mCurrentFocusAge;
                localFocus = o.child;
                //propagate upwards
                if (parent) {
                    parent.recheckChildFocus(this);
                }
            }
        } else {
            //maybe was killed, take focus
            if (mFocus is o.child) {
                //the element which was focused before should be picked
                //pick element with highest age, take old and set new focus
                PerWidget winner;
                foreach (curgui; mWidgets) {
                    if (curgui.child.canHaveFocus &&
                        (!winner || (winner.mFocusAge < curgui.mFocusAge)))
                    {
                        winner = curgui;
                    }
                }
                localFocus = winner ? winner.child : null;
            }
        }
    }

    //called by anyone if o.canHaveFocus changed
    void recheckChildFocus(Widget o) {
        if (o) {
            doRecheckChildFocus(findChild(o), o.canHaveFocus);
        }
    }

    //like when you press <tab>
    //  forward = false: go backwards in focus list, i.e. undo <tab>
    void nextFocus(bool forward = true) {
        //xxx this might infer with zorder handling so it wouldn't work!
        auto cur = findChild(mFocus, true);
        if (!cur) {
            //forward==true: finally pick first, else last
            cur = forward ? mWidgets[$-1] : mWidgets[0];
        }
        auto iterate = forward ?
            &arrayFindPrev!(PerWidget) : &arrayFindNext!(PerWidget);
        auto next = arrayFindFollowingPred(mWidgets, cur, iterate,
            (PerWidget o) {
                return o.child.canHaveFocus;
            }
        );
        localFocus = next.child;
    }

    //doesn't set the global focus; do "go.focused = true;" for that
    /+protected+/ void localFocus(Widget go) {
        if (go is mFocus)
            return;

        if (mFocus) {
            gDefaultLog("remove local focus: %s from %s", mFocus, this);
            auto tmp = mFocus;
            mFocus = null;
            tmp.stateChanged();
        }
        mFocus = go;
        if (go && go.canHaveFocus) {
            findChild(go).mFocusAge = ++mCurrentFocusAge;
            gDefaultLog("set local focus: %s for %s", mFocus, this);
            go.stateChanged();
        }
    }

    //"local focus": if the frame had the real focus, the element that'd be
    //  focused now
    //"real/global focus": an object and all its parents are locally focused
    /+protected+/ Widget localFocus() {
        return mFocus;
    }

    override void onFocusChange() {
        super.onFocusChange();
        //propagate focus change downwards...
        foreach (o; mWidgets) {
            o.child.stateChanged();
        }
    }

    override bool internalHandleMouseEvent(MouseInfo* mi, KeyInfo* ki) {
        //NOTE: mouse buttons (ki) don't have the mousepos; use the old one then

        //xxx: mouse capture

        //first check if the parent wants it; if it returns true, don't deliver
        //this event to the children
        if (super.internalHandleMouseEvent(mi, ki))
            //sry!
            goto huhha;

        Widget got_it;

        //check if any children are hit by this
        //objects towards the end of the array are later drawn => _reverse
        foreach_reverse(o; mWidgets) {
            auto child = o.child;
            auto clientmp = child.coordsFromParent(mousePos);
            if (child.testMouse(clientmp)) {
                //huhuhu a hit! call its event handler
                bool res;
                //MouseInfo.pos should contain the translated mousepos
                if (mi) {
                    MouseInfo mi2 = *mi;
                    mi2.pos = clientmp;
                    res = child.internalHandleMouseEvent(&mi2, null);
                } else {
                    res = child.internalHandleMouseEvent(null, ki);
                }
                if (res) {
                    got_it = child;
                    break;
                }
            }
        }
    huhha:

        if (mLastMouseReceiver && (mLastMouseReceiver !is got_it)) {
            mLastMouseReceiver.internalMouseLeave();
        }

        mLastMouseReceiver = got_it;

        return got_it !is null;
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        if (!mouseIsInside && mLastMouseReceiver) {
            mLastMouseReceiver.internalMouseLeave();
            mLastMouseReceiver = null;
        }
    }

    override bool internalHandleKeyEvent(KeyInfo info) {
        //first try to handle locally
        //the super.-method invokes the onKey*() functions
        if (super.internalHandleKeyEvent(info))
            return true;
        //event wasn't handled, handle by child objects
        if (mFocus) {
            if (mFocus.internalHandleKeyEvent(info))
                return true;
        }
        return false;
    }

    override void internalSimulate(Time curTime, Time deltaT) {
        foreach (obj; mWidgets) {
            obj.child.internalSimulate(curTime, deltaT);
        }
        super.internalSimulate(curTime, deltaT);
    }

    protected override Vector2i layoutSizeRequest() {
        //report the biggest
        Vector2i biggest;
        foreach (PerWidget w; children) {
            Vector2i s = layoutDoRequestChild(w);
            biggest.x = max(biggest.x, s.x);
            biggest.y = max(biggest.y, s.y);
        }
        biggest -= getInternalBorder()*2;
        return biggest;
    }
    protected override void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        b.extendBorder(-getInternalBorder());
        foreach (PerWidget w; children) {
            layoutDoAllocChild(w, b);
        }
    }

    //container-side border for children
    //xxx: check usefulness
    protected Vector2i getInternalBorder() {
        return Vector2i();
    }
}

///Container with a public Container-interface
///Container introduces some public methods too, but only ones that need a
///valid object reference to child widgets
///xxx: maybe do it right, I didn't even catch all functions, but it makes
///     problems in widget.d/Widget
class PublicContainer : Container {
    void clear() {
        while (children.length > 0) {
            removeChild(children[0].child);
        }
    }
}

///PublicContainer which supports simple layouting
///by coincidence only needs to add more accessors to the original Container
class SimpleContainer : PublicContainer {
    /// Add an element to the GUI, which gets automatically cleaned up later.
    void add(Widget obj) {
        addChild(obj);
    }

    /// Add and set layout.
    void add(Widget obj, WidgetLayout layout) {
        //xxx maybe do sth. like freezeLayout()
        addChild(obj);
        setChildLayout(obj, layout);
    }
}
