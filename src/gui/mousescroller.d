module gui.mousescroller;
import gui.widget;
import gui.container;
import framework.framework;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;
import utils.time;

/// The child for MouseScroller can implement this; then scrolling will can be
/// enabled.
interface ScrollClient {
    //Get the maximal scroll value
    Vector2f getScrollSize();
    //Set the scroll position (i.e. actually scroll)
    //guaranteed to be between 0..getScrollSize for each component
    void setScrollPositions(Vector2f pos);
}

/// This frame always sizes its child to its requested size, and enables
/// scrolling within it.
//(this is what the SceneObjectViewer was)
class MouseScroller : SimpleContainer {
    private {
        Vector2i mOffset;
        Vector2f mScrollDest, mScrollOffset;
        bool mMouseScrolling;
        long mTimeLast;

        const cScrollStepMs = 10;
        const float K_SCROLL = 0.01f;
    }

    protected {
        //currently unused
        //[x, y], true if scrolling is possible on this axis
        //could be used to show/hide scrollbars
        bool[2] mAllowScroll;
    }

    this() {
        setBinContainer(true);
        mTimeLast = timeCurrentTime().msecs;
    }

    override protected Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }
    override protected void layoutSizeAllocation() {
        //it's ok; maybe readjust scrolling (this function happens on resize)
        Vector2i clientsize = layoutDoRequestChild(getBinChild());
        layoutDoAllocChild(getBinChild(), Rect2i(Vector2i(0), clientsize));
        //xxx nasty?
        doSetScrollPos();
    }

    ///Stop all active scrolling and stay at the currently visible position
    public void scrollReset() {
        mScrollOffset = toVector2f(offset);
        mScrollDest = mScrollOffset;
    }

    private void scrollUpdate(Time curTime) {
        long curTimeMs = curTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            offset = toVector2i(mScrollOffset);
        } else {
            mTimeLast = timeCurrentTime().msecs;
        }
    }

    ///call this when the user moves the mouse to scroll by delta
    ///idle time will be reset
    public void scrollMove(Vector2i delta) {
        scrollDoMove(delta);
    }

    ///internal method that will move the camera by delta without affecting
    ///idle time
    private void scrollDoMove(Vector2i delta) {
        mScrollDest = mScrollDest - toVector2f(delta);
        clipOffset(mScrollDest);
    }

    ///One-time center the camera on scenePos
    public void scrollCenterOn(Vector2i scenePos, bool instantly = false) {
        mScrollDest = -toVector2f(scenePos - size/2);
        clipOffset(mScrollDest);
        mTimeLast = timeCurrentTime().msecs;
        if (instantly) {
            mScrollOffset = mScrollDest;
            offset = toVector2i(mScrollOffset);
        }
    }

    //offset
    private void doSetScrollPos() {
        clipOffset(mOffset);
        getBinChild().child.adjustPosition(mOffset);
    }

    Vector2i offset() {
        return mOffset;
    }
    void offset(Vector2i offs) {
        mOffset = offs;
        doSetScrollPos();
    }

    ///Vector2i wrapper for offset clipping
    public void clipOffset(inout Vector2i offs) {
        Vector2f tmp = toVector2f(offs);
        clipOffset(tmp);
        offs = toVector2i(tmp);
    }

    ///clip an offset value to make sure its sane
    ///scenes bigger than the viewport are prevented from showing black
    ///borders, whereas smaller scenes will be centered
    protected void clipOffset(inout Vector2f offs) {
        Vector2i clientsize = getBinChild().child.size;

        if (size.x < clientsize.x) {
            //view window is smaller than scene (x-dir)
            //-> don't allow black borders
            if (offs.x > 0)
                offs.x = 0;
            if (offs.x + clientsize.x < size.x)
                offs.x = size.x - clientsize.x;
            mAllowScroll[0] = true;
        } else {
            //view is larger than scene -> no scrolling, center
            offs.x = size.x/2 - clientsize.x/2;
            mAllowScroll[0] = false;
        }

        //same for y
        if (size.y < clientsize.y) {
            if (offs.y > 0)
                offs.y = 0;
            if (offs.y + clientsize.y < size.y)
                offs.y = size.y - clientsize.y;
            mAllowScroll[1] = true;
        } else {
            offs.y = size.y/2 - clientsize.y/2;
            mAllowScroll[1] = false;
        }
    }

    public bool mouseScrolling() {
        return mMouseScrolling;
    }
    public void mouseScrolling(bool enable) {
        if (enable == mMouseScrolling)
            return;
        if (enable) {
            //globals.framework.grabInput = true;
            gFramework.cursorVisible = false;
            gFramework.lockMouse();
            scrollReset();
        } else {
            //globals.framework.grabInput = false;
            gFramework.cursorVisible = true;
            gFramework.unlockMouse();
        }
        mMouseScrolling = enable;
    }
    public void mouseScrollToggle() {
        mouseScrolling(!mMouseScrolling);
    }

    override void simulate(Time curTime, Time deltaT) {
        scrollUpdate(curTime);
    }

    override protected bool onKeyDown(char[] bind, KeyInfo key) {
        /*if (bind == "scroll_toggle") {
            //scrollToggle();
            return true;
        }*/
        if (key.code == Keycode.MOUSE_RIGHT) {
            mouseScrollToggle();
            return true;
        }
        return false;
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        return false;
    }

    override bool testMouse(Vector2i pos) {
        return true;
    }

    override bool onMouseMove(MouseInfo mi) {
        if (mMouseScrolling) {
            scrollMove(mi.rel);
            return true;
        }
        return false;
    }
}
