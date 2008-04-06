module gui.mousescroller;

import common.common;
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

    override MouseCursor mouseCursor() {
        return mMouseScrolling ? MouseCursor.None : super.mouseCursor();
    }

    private bool checkReleaseLock() {
        if (mMouseScrolling && isLinked())
            return true;
        captureSet(false);
        //gFramework.grabInput = false;
        gFramework.mouseLocked = false;
        return false;
    }

    public bool mouseScrolling() {
        return mMouseScrolling;
    }
    public void mouseScrolling(bool enable) {
        if (enable == mMouseScrolling)
            return;
        if (enable) {
            if (gFramework.mouseLocked() /+ || gFramework.grabInput()+/)
                return;
            //[setting the capture seems to get rid of some strange corner case
            // situations (test: while mouse scrolling is active, resize the
            // window so that the mouse-lock position is outside the window; can
            // be easily done with fullscreen -> windowed mode switching)]
            if (!captureSet(true)) {
                return; //refuse
            }
            //removed the grab; if the SDL driver needs it to grab for some
            //strange reasons, it can do that by itself anyway
            //gFramework.grabInput = true;
            gFramework.mouseLocked = true;
            //use that silly callback in the case when this widget was removed
            //from the GUI while mouse scrolling was enabled
            globals.addFrameCallback(&checkReleaseLock);
            stopSmoothScrolling();
        } else {
            checkReleaseLock();
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

    protected override bool allowInputForChild(Widget child, InputEvent event) {
        if (event.isKeyEvent && event.keyEvent.code == Keycode.MOUSE_RIGHT)
            return false;
        //catch only mouse events
        if (mMouseScrolling)
            return !event.isMouseRelated();
        return true;
    }

    override void loadFrom(GuiLoader loader) {
        //hm, nothing? mouseScrolling() is a runtime-only property
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("mousescroller");
    }
}
