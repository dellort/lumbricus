module gui.mousescroller;

//xxx I like the idea of gui being independent from common
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
        bool mMouseScrolling, mMouseFollow;
        Time mLastMouseScroll;
        Vector2i mFollowBorder;
    }

    //if mouse scrolling is enabled, do not deliver mouse click events to child
    //  widgets (mouse move events are always filtered)
    bool filterClicks = false;

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
        GUI.getLog()("disable mouse scrolling");
        captureRelease();
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
            GUI.getLog()("enable mouse scrolling");
            if (mMouseFollow)
                stopMouseFollow();
            if (gFramework.mouseLocked())
                return;
            //[setting the capture seems to get rid of some strange corner case
            // situations (test: while mouse scrolling is active, resize the
            // window so that the mouse-lock position is outside the window; can
            // be easily done with fullscreen -> windowed mode switching)]
            //yyy doesn't work anymore
            if (!captureEnable(true, false, false))
                return;
            //here's a bunch of hacks...
            //- enabling capture will not yet set the new mouse cursor, because
            //  the mouse cursor will only be set with the next mouse move event
            //- so create an artifical mouse move event in (d) to fix this
            //- (b) will move the cursor, which is why we hide it in (a) to
            //  avoid having a visible cursor in the wrong position
            //- to have (d) working, must do (c); the event triggered by (d)
            //  will check mMouseScrolling
            //- the cursor should be hidden before moving, so (a) is needed
            //  even though there's (d)
            //- the actual cursor is set "later" by the GUI code, so we need (a)
            //  even if (c)+(d) was done before (b)
            //this all is to avoid only briefly visible visual ugliness
            gFramework.mouseCursor = MouseCursor.None; //(a)
            gFramework.mouseLocked = true; //(b)
            mMouseScrolling = true; //(c)
            if (gui)
                gui.fixMouse(); //(d)
            //use that silly callback in the case when this widget was removed
            //from the GUI while mouse scrolling was enabled
            globals.addFrameCallback(&checkReleaseLock);
            stopSmoothScrolling();
        } else {
            mMouseScrolling = false;
            checkReleaseLock();
        }
    }
    public void mouseScrollToggle() {
        mouseScrolling(!mMouseScrolling);
    }

    //don't allow mouse to go further than border
    void startMouseFollow(Vector2i border) {
        assert(border.quad_length > 0);
        if (mMouseScrolling)
            mouseScrolling(false);
        mMouseFollow = true;
        mFollowBorder = border;
    }
    void stopMouseFollow() {
        mMouseFollow = false;
    }
    bool mouseFollow() {
        return mMouseFollow;
    }

    override bool handleChildInput(InputEvent event) {
        if (event.isMouseEvent && mMouseFollow) {
            //another dirty hack: don't eat movement events
            auto mousePos = event.mousePos;
            //when the mouse would go outside the visible area,
            //scroll to correct (-> "pushing" the borders)
            auto visible = Rect2i(size);
            visible.extendBorder(-mFollowBorder);
            if (!visible.isInsideB(mousePos)) {
                //cursor went outside
                auto npos = visible.clip(mousePos);
                auto offs = scrollDestination();
                scrollDeltaSmooth(mousePos - npos);
                //check how much we actually scrolled to correct...
                auto doffs = scrollDestination() - offs;
                //... and move the mouse back by that amount (keep it inside)
                if (doffs.quad_length > 0)
                    gFramework.mousePos = gFramework.mousePos + doffs;
                noticeAction();
            }
        }
        //apparently mMouseFollow shouldn't eat events...? so be it.
        bool take;
        take |= event.isMouseEvent && mMouseScrolling;
        take |= event.isMouseRelated && filterClicks && mMouseScrolling;
        if (take) {
            deliverDirectEvent(event, false);
            return true;
        }
        return super.handleChildInput(event);
    }

    override void onMouseMove(MouseInfo mouse) {
        if (mMouseScrolling) {
            scrollDeltaSmooth(mouse.rel);
            noticeAction();
        }
    }

    override void loadFrom(GuiLoader loader) {
        //hm, nothing? mouseScrolling() is a runtime-only property
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("mousescroller");
    }
}
