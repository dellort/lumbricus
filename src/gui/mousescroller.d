module gui.mousescroller;

import gui.scrollwindow;
import framework.event;
import framework.framework;
import utils.time;

/// This frame always sizes its child to its requested size, and enables
/// scrolling within it.
//(this is what the SceneObjectViewer was)
class MouseScroller : ScrollArea {
    private {
        bool mMouseScrolling;
        Time mLastMouseScroll;
    }

    ///return last time the area was scrolled using the mouse
    ///more a hack to make it work with game/gui/camera.d
    public Time lastMouseScroll() {
        return mLastMouseScroll;
    }

    ///reset lastMouseScroll() to now
    public void noticeAction() {
        mLastMouseScroll = timeCurrentTime();
    }

    public bool mouseScrolling() {
        return mMouseScrolling;
    }
    public void mouseScrolling(bool enable) {
        if (enable == mMouseScrolling)
            return;
        if (enable) {
            gFramework.grabInput = true;
            gFramework.cursorVisible = false;
            gFramework.lockMouse();
            stopSmoothScrolling();
        } else {
            gFramework.grabInput = false;
            gFramework.cursorVisible = true;
            gFramework.unlockMouse();
        }
        mMouseScrolling = enable;
    }
    public void mouseScrollToggle() {
        mouseScrolling(!mMouseScrolling);
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

    /*override bool testMouse(Vector2i pos) {
        return true;
    }*/

    override bool onMouseMove(MouseInfo mi) {
        if (mMouseScrolling) {
            scrollDeltaSmooth(mi.rel);
            noticeAction();
            return true;
        }
        return super.onMouseMove(mi);
    }
}
