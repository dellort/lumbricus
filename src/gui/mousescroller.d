module gui.mousescroller;

import gui.scrollwindow;
import gui.widget;
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
            if (!captureEnable()) {
                //to avoid some problems when draging around the containing
                //window (TestFrame3 in test.d)
                return; //refuse
            }
            gFramework.grabInput = true;
            gFramework.cursorVisible = false;
            gFramework.lockMouse();
            stopSmoothScrolling();
        } else {
            captureDisable();
            gFramework.grabInput = false;
            gFramework.cursorVisible = true;
            gFramework.unlockMouse();
        }
        mMouseScrolling = enable;
    }
    public void mouseScrollToggle() {
        mouseScrolling(!mMouseScrolling);
    }

    override protected bool onKeyEvent(KeyInfo key) {
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (key.isDown) {
                mouseScrollToggle();
            }
            return true;
        }
        return super.onKeyEvent(key);
    }

    override bool onMouseMove(MouseInfo mi) {
        if (mMouseScrolling) {
            scrollDeltaSmooth(mi.rel);
            noticeAction();
            return true;
        }
        return super.onMouseMove(mi);
    }

    override void loadFrom(GuiLoader loader) {
        //hm, nothing? mouseScrolling() is a runtime-only property
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("mousescroller");
    }
}
