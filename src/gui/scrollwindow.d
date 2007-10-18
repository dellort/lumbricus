module gui.scrollwindow;

import common.visual;
import gui.button;
import gui.container;
import gui.tablecontainer;
import gui.widget;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
import utils.misc;
import utils.time;

/// The child for ScrollArea can implement this; then scrolling can be owner
/// defined; else the ScrollArea will scroll it as Widget.
interface ScrollClient {
    //Get the maximal scroll value
    Vector2i getScrollSize();
    //Set the scroll position (i.e. actually scroll)
    //guaranteed to be between 0..getScrollSize for each component
    void setScrollPositions(Vector2i pos);
}

/// This frame always sizes its child to its requested size, and enables
/// scrolling within it.
class ScrollArea : SimpleContainer {
    private {
        Vector2i mOffset;
        Vector2i mScrollSize;

        //stuff for smooth scrolling
        bool mEnableSmoothScrolling;

        Vector2f mScrollDest, mScrollOffset;
        long mTimeLast;

        const cScrollStepMs = 10;
        const float K_SCROLL = 0.01f;
    }

    //changes to scroll size or scrollability
    void delegate(ScrollArea sender) onStateChange;
    //changes to the scroll position
    void delegate(ScrollArea sender) onPositionChange;

    protected {
        ScrollClient mScroller; //maybe null, even if child available
        //[x, y], true if allow scrolling if it's "required"
        bool[2] mEnableScroll = [true, true];
    }

    this() {
        setBinContainer(true);
    }

    override protected void onAddChild(Widget c) {
        //optional ScrollClient interface
        mScroller = cast(ScrollClient)c;
    }
    override protected void onRemoveChild(Widget c) {
        mScroller = null;
    }

    void setEnableScroll(bool[2] enable) {
        mEnableScroll[] = enable;
        needRelayout();
    }
    void getEnableScroll(bool[2] enable) {
        enable[] = mEnableScroll;
    }

    void setScroller(ScrollClient c) {
        mScroller = c;
        updateScrollSize();
    }

    final Vector2i getScrollSize() {
        return mScrollSize;
    }

    //same as child.coordsToParent, but uses current scroll destination instead
    //of actual position
    //xxx doesn't work with mScroller
    final Vector2i fromClientCoordsScroll(Vector2i p) {
        auto child = getBinChild();
        return child ? p + toVector2i(mScrollDest) : p;
    }

    override protected Vector2i layoutSizeRequest() {
        auto r = Vector2i(0);

        auto child = getBinChild();
        if (child) {
            r = child.layoutCachedContainerSizeRequest();
        }

        if (mScroller) {
            //hm, just leave it as it is
        } else {
            //expand to child's size if it doesn't want to scroll
            r.x = mEnableScroll[0] ? 0 : r.x;
            r.y = mEnableScroll[1] ? 0 : r.y;
        }

        return r;
    }
    override protected void layoutSizeAllocation() {
        auto child = getBinChild();
        if (child) {
            Vector2i csize = child.layoutCachedContainerSizeRequest;
            if (!mScroller) {
                //as in layoutSizeRequest()
                csize.x = mEnableScroll[0] ? csize.x : size.x;
                csize.y = mEnableScroll[1] ? csize.y : size.y;
            }
            child.layoutContainerAllocate(Rect2i(Vector2i(0), csize));
        }
        updateScrollSize();
    }

    //recalculate mScrollSize and maybe adjust mOffset
    public void updateScrollSize() {
        auto child = getBinChild();

        Vector2i ssize;

        if (mScroller) {
            ssize = mScroller.getScrollSize();
        } else if (child) {
            auto csize = child.layoutCachedContainerSizeRequest();
            auto msize = size;
            auto diff = csize - msize;
            //if it's too small, the child will be layouted using the
            //normal Widget layout stuff (on this axis)
            ssize.x = diff.x > 0 ? diff.x : 0;
            ssize.y = diff.y > 0 ? diff.y : 0;
        }

        mScrollSize.x = mEnableScroll[0] ? ssize.x : 0;
        mScrollSize.y = mEnableScroll[1] ? ssize.y : 0;

        //assert it's within the scrolling region (call setter...)
        offset = mOffset;

        if (onStateChange)
            onStateChange(this);
    }

    final public Vector2i clipOffset(Vector2i offs) {
        return Rect2i(-mScrollSize, Vector2i(0)).clip(offs);
    }

    //sigh?
    final public Vector2f clipOffset(Vector2f offs) {
        //xxx hack against float rounding error of offs
        //(when scrolling to right border)
        return Rect2f(-toVector2f(mScrollSize) - Vector2f(.99f,.99f),
            Vector2f(0)).clip(offs);
    }

    Vector2i offset() {
        return mOffset;
    }
    void offset(Vector2i offs) {
        mOffset = clipOffset(offs);
        auto child = getBinChild();
        if (mScroller) {
            mScroller.setScrollPositions(mOffset);
        } else if (child) {
            child.adjustPosition(mOffset);
        }
        if (onPositionChange)
            onPositionChange(this);
    }

    ///calculate the offset that would center pos in the middle of this Widget
    ///(pos in the child's coordinates)
    Vector2i centeredOffset(Vector2i pos) {
        //xxx don't know if this is correct when using mScroller or so
        //aim: mOffset + pos == size/2
        return size/2 - pos;
    }

    void scrollDelta(Vector2i d) {
        offset = mOffset - d;
    }

    // --- (optional) smooth scrolling (works completely in top of the rest)

    ///Stop all active scrolling and stay at the currently visible position
    public void stopSmoothScrolling() {
        mEnableSmoothScrolling = false;
    }

    ///smoothly make offs to new offset
    public void scrollToSmooth(Vector2i offs) {
        stopSmoothScrolling();
        scrollDeltaSmooth(-offs);
    }

    public void scrollDeltaSmooth(Vector2i d) {
        if (!mEnableSmoothScrolling) {
            mEnableSmoothScrolling = true;
            mScrollDest = toVector2f(offset);
            mScrollOffset = mScrollDest;
            //xxx: what exactly is the GUIs timesource?
            mTimeLast = timeCurrentTime.msecs();
        }
        mScrollDest = clipOffset(mScrollDest - toVector2f(d));
    }

    override protected void simulate() {
        if (!mEnableSmoothScrolling)
            return;

        long curTimeMs = timeCurrentTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            offset = toVector2i(mScrollOffset-Vector2f(.5f));
        } else {
            mEnableSmoothScrolling = false;
        }
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        bool[2] enable = mEnableScroll;
        enable[0] = node.getBoolValue("enable_scroll_x", enable[0]);
        enable[1] = node.getBoolValue("enable_scroll_y", enable[1]);
        setEnableScroll(enable);

        //will load a child, if available
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("scrollarea");
    }
}

/// Combines a ScrollArea and 0-2 ScrollBars
/// (currently provides access to a ScrollArea directly, hmmm)
//xxx: there's no technical reason why this is derived from a Container, instead
//  of deriving from TableContainer or so, but it seemed unclean
class ScrollWindow : Container {
    private {
        ScrollArea mArea;
        ScrollBar[2] mBars;
        TableContainer mLayout;
        //used to block recursive change notifications (!= 0 means updating)
        int mUpdating;
    }

    this() {
        mArea = new ScrollArea();
        recreateGui();
    }

    //callbacks must be left to this object
    void setScrollArea(ScrollArea arr) {
        destroyGui();
        mArea = arr;
        recreateGui();
    }

    private void destroyGui() {
        //especially remove callbacks; before they are even fired on removal
        foreach (ScrollBar b; mBars) {
            if (b) {
                b.onValueChange = null;
            }
        }
        mBars[] = mBars.init;
        mLayout = null;
        mArea.onPositionChange = null;
        mArea.onStateChange = null;
        clear();
        mArea.remove();
    }

    private void recreateGui() {
        //recreate only if necessary
        //this prevents an infinite loop, triggered by recreating the GUI,
        //which makes the ScrollArea trigger onStateChange, which calls us (this
        //function) again... argh
        //xxx: horrible implementation, make better

        bool[2] scr;
        Vector2i sizes;
        if (mArea) {
            mArea.getEnableScroll(scr);
            sizes = mArea.getScrollSize();
        }
        //sizes as set
        Vector2i setsizes;
        if (mBars[0] && scr)
            setsizes[0] = mBars[0].maxValue;
        if (mBars[1] && scr)
            setsizes[1] = mBars[1].maxValue;

        //if GUI is existing, check if anything that must be changed below is
        //different
        if (mLayout && !!mBars[0] == scr[0] && !!mBars[1] == scr[1])
        {
            if (sizes != setsizes) {
                //only the sizes changed; handle that without triggering
                //relayouting *sigh*
                if (mBars[0]) mBars[0].maxValue = sizes[0];
                if (mBars[1]) mBars[1].maxValue = sizes[1];
            }
            return;
        }

        destroyGui();

        if (!mArea)
            return;

        try {
            mUpdating++;

            mArea.onPositionChange = &onDoScroll;
            mArea.onStateChange = &onScrollChange;
            mLayout = new TableContainer(scr[0]?2:1, scr[1]?2:1);
            mLayout.add(mArea, 0, 0);
            for (int n = 0; n < 2; n++) {
                if (scr[n]) {
                    auto bar = new ScrollBar(!n);
                    mBars[n] = bar;
                    mLayout.add(bar, n?1:0, n?0:1, WidgetLayout.Expand(!n));
                    bar.onValueChange = &onScrollbar;
                    bar.maxValue = sizes[n];
                    bar.curValue = -mArea.offset[n];
                }
            }

            addChild(mLayout);
        } finally {
            mUpdating--;
        }
    }

    private void onScrollbar(ScrollBar sender) {
        if (mUpdating)
            return;

        Vector2i offset = mArea.offset;
        if (sender is mBars[0]) {
            offset[0] = -sender.curValue;
        } else if (sender is mBars[1]) {
            offset[1] = -sender.curValue;
        }
        try {
            mUpdating++;
            mArea.offset = offset;
        } finally {
            mUpdating--;
        }
    }

    //its onPositionChange
    private void onDoScroll(ScrollArea scroller) {
        if (mUpdating)
            return;

        try {
            mUpdating++;
            if (mBars[0])
                mBars[0].curValue = -scroller.offset[0];
            if (mBars[1])
                mBars[1].curValue = -scroller.offset[1];
        } finally {
            mUpdating--;
        }
    }

    //its onStateChange
    private void onScrollChange(ScrollArea scroller) {
        recreateGui();
    }

    void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        //possibly load a child, which must be a ScrollArea (or a subtype of it)
        auto child = node.findNode("area");
        if (child) {
            auto childw = loader.loadWidget(child);
            auto arr = cast(ScrollArea)childw;
            if (!arr)
                throw new Exception("whatever");
            setScrollArea(arr);
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("scrollwindow");
    }
}

class ScrollBar : Container {
    private {
        int mDir; //0=in x direction, 1=y
        Button mSub, mAdd;
        Bar mBar;
        Rect2i mBarArea;

        int mCurValue;
        int mMaxValue;
        //scale factor = pixels / value
        double mScaleFactor;

        //amount of pixels the bar can be moved
        int mBarFreeSpace;

        //that thing which sits between the two buttons
        //xxx: drag and drop code partially copied from window.d
        class Bar : Widget {
            BoxProperties mBorder;
            bool drag_active;
            Vector2i drag_start;

            protected void onDraw(Canvas c) {
                common.visual.drawBox(c, widgetBounds, mBorder);
            }

            override protected Vector2i layoutSizeRequest() {
                return Vector2i(0);
            }

            override protected bool onMouseMove(MouseInfo mouse) {
                if (drag_active) {
                    //get position within the container
                    assert(parent && this.outer.parent);
                    auto pos = coordsToParent(mouse.pos);
                    pos -= drag_start; //click offset

                    curValue = cast(int)((pos[mDir] - mBarArea.p1[mDir]
                        + 0.5*mScaleFactor) / mScaleFactor);

                    return true;
                }
                return false;
            }

            override protected bool onKeyEvent(KeyInfo key) {
                if (!key.isPress && key.isMouseButton) {
                    drag_active = key.isDown;
                    drag_start = mousePos;
                    captureSet(drag_active);
                }
                return key.isMouseButton || super.onKeyEvent(key);
            }
        }
    }

    void delegate(ScrollBar sender) onValueChange;

    ///horizontal if horiz = true, else vertical
    this(bool horiz) {
        mDir = horiz ? 0 : 1;
        //xxx: replace text by images
        mAdd = new Button();
        mAdd.text = "A";
        mAdd.onClick = &onAddSub;
        mAdd.autoRepeat = true;
        addChild(mAdd);
        mSub = new Button();
        mSub.text = "B";
        mSub.onClick = &onAddSub;
        mSub.autoRepeat = true;
        addChild(mSub);
        mBar = new Bar();
        addChild(mBar);
    }

    private void onAddSub(Button sender) {
        if (sender is mAdd) {
            curValue = curValue+1;
        } else if (sender is mSub) {
            curValue = curValue-1;
        }
    }

    override protected bool onKeyEvent(KeyInfo ki) {
        if (super.onKeyEvent(ki))
            return true;

        //nothing was hit -> free area of scrollbar, between the bar and the
        //two buttons

        auto at = mousePos;
        if (ki.isMouseButton && mBarArea.isInside(at)) {
            if (ki.isDown) {
                //xxx: would need some kind of auto repeat too
                //also, this looks ugly
                auto bar = mBar.containedBounds;
                int dir = (at[mDir] > ((bar.p1 + bar.p2)/2)[mDir]) ? +1 : -1;
                //multiply dir with the per-click increment (fixed to 1 now)
                curValue = curValue + dir*1;
            }
            return true;
        }
        return false;
    }

    //prevent Container from returning false if no child is hit
    override bool testMouse(Vector2i pos) {
        return true;
    }

    override protected Vector2i layoutSizeRequest() {
        auto r1 = mSub.requestSize;
        auto r2 = mAdd.requestSize;
        Vector2i res;
        auto mindir = max(r1[mDir], r2[mDir])*2;
        //leave at least mindir/4 space for the bar, as a hopefully-ok guess
        res[mDir] = mindir + mindir/4;
        res[!mDir] = max(r1[!mDir], r2[!mDir]);
        return res;
    }

    override protected void layoutSizeAllocation() {
        auto sz = size;

        Vector2i buttons = mSub.requestSize.max(mAdd.requestSize);
        buttons[!mDir] = sz[!mDir];
        auto bsize = Rect2i(Vector2i(0), buttons);

        mSub.layoutContainerAllocate(bsize);
        Vector2i r;
        r[mDir] = sz[mDir] - mAdd.requestSize[mDir];
        mAdd.layoutContainerAllocate(bsize + r);
        mBarArea = widgetBounds;
        mBarArea.p1[mDir] = mSub.requestSize[mDir];
        mBarArea.p2[mDir] = r[mDir];

        adjustBar();
    }

    //reset position of mBar according to mCurValue/mMaxValue
    private void adjustBar() {
        //"height" (size along mDir) should be chosen to a useful size, but
        //for now make it... something
        int barh = mAdd.requestSize[mDir];
        int areah = mBarArea.size[mDir];
        if (mMaxValue == 0) //no scrolling in this case
            barh = areah;
        if (barh > areah)
            barh = areah;
        mBarFreeSpace = areah - barh;
        Vector2i sz = size;
        sz[mDir] = barh;
        //pixel offset of bar inside mBarArea
        mScaleFactor = mMaxValue ? (1.0/mMaxValue)*mBarFreeSpace : 0;
        int pos = cast(int)(mScaleFactor*mCurValue);
        Vector2i start = mBarArea.p1;
        start[mDir] = start[mDir] + pos;
        mBar.layoutContainerAllocate(Rect2i(start, start+sz));
    }

    int curValue() {
        return mCurValue;
    }
    void curValue(int v) {
        v = clampRangeC(v, 0, mMaxValue);
        mCurValue = v;
        adjustBar();
        if (onValueChange)
            onValueChange(this);
    }

    int maxValue() {
        return mMaxValue;
    }
    void maxValue(int v) {
        assert(v >= 0);
        mMaxValue = v;
        //hmmmm
        curValue = curValue;
    }
}
