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
            //shitty hack:
            //- first mouse move event will recheck the mouse cursor shape
            //- the actual mouse cursor is set to the middle of the screen (by
            //  the framework's mouseLocked stuff)
            //- but at that time, the cursor is still visible; only the
            //  following event will set the mouseWidget (which sets the cursor)
            //- so, just set it manually, right here
            //NOTE: somtimes, I still can see the cursor at the wrong position
            //  for a very short time
            if (auto m = getTopLevel()) {
                m.mouseWidget = this;
            }
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

    /+
    override protected void onKeyEvent(KeyInfo key) {
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (key.isDown) {
                mouseScrollToggle();
            }
        }
    }
    +/

    override void onMouseMove(MouseInfo mi) {
        if (mMouseScrolling) {
            scrollDeltaSmooth(mi.rel);
            noticeAction();
        }
    }

    protected override bool allowInputForChild(Widget child, InputEvent event) {
        if (event.isKeyEvent && event.keyEvent.code == Keycode.MOUSE_RIGHT) {
            //ok, this is a dirty hack
            //- we don't want to take the focus, which would happen if we'd
            //  steal the event from the sub widget
            //- so just do it here
            //- we _have_ to relay the input, else the captureKey widget will
            //  change and doc will complain (see TODO r831)
            if (event.keyEvent.isDown) {
                mouseScrollToggle();
            }
            return true;
        }
        //catch only mouse events (mouse moving, mouse cursor shape)
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
