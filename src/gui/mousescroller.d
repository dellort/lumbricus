module gui.mousescroller;
import gui.widget;
import gui.container;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.log;

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
class MouseScroller : Container {
    private {
        Vector2i mOffset;
        bool mScrolling;
    }

    this() {
        super(true, true);
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

    //offset
    private void doSetScrollPos() {
        getBinChild().child.adjustPosition(-mOffset);
    }

    void scrollTo(Vector2i offset) {
        mOffset = offset;
        doSetScrollPos();
    }

    override protected bool onKeyDown(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_RIGHT) {
            mScrolling = true;
            gDefaultLog("scroll on");
            return true;
        }
        return false;
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_RIGHT) {
            mScrolling = false;
            gDefaultLog("scroll off");
            return true;
        }
        return false;
    }

    override bool testMouse(Vector2i pos) {
        return true;
    }

    override bool onMouseMove(MouseInfo mi) {
        if (mScrolling) {
            gDefaultLog("scroll to ", mi.pos);
            scrollTo(mi.pos);
            return true;
        }
        return false;
    }
}
