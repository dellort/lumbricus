//this is not a Lua binding for the GUI
//it just allows a Lua GUI run inside the D GUI
module gui.lua;

import common.scene;
import framework.event;
import framework.lua;
import gui.widget;
import utils.misc;
import utils.rect2;
import utils.vector2;


class LuaGuiAdapter {
    private {
        WidgetAdapt mWidget;
        Vector2i mSizeRequest;
        bool mWasAdded;
    }

    void delegate(Rect2i) OnMap;
    void delegate() OnUnmap;
    void delegate() OnMouseLeave;
    bool delegate(KeyInfo) OnHandleKeyInput;
    bool delegate(MouseInfo) OnHandleMouseInput;
    void delegate(bool) OnSetFocus;
    void delegate(Canvas) OnDraw;

    //alternative to OnDraw - render.draw() will be called if non-null
    SceneObject render;

    //this behaves as if there was a single child widget implemented in Lua
    private class WidgetAdapt : Widget {
        this() {
            focusable = true;
            isClickable = true;
        }

        override bool handleChildInput(InputEvent event) {
            bool res;
            if (event.isKeyEvent) {
                if (OnHandleKeyInput)
                    res = OnHandleKeyInput(event.keyEvent);
            } else if (event.isMouseEvent) {
                if (OnHandleMouseInput)
                    res = OnHandleMouseInput(event.mouseEvent);
            } else {
                assert(false, "doesn't happen");
            }
            if (res) {
                //if event is taken, deliver to us; only done to keep some
                //  internal GUI mechanisms, namely click-on-focus
                deliverDirectEvent(event);
            }
            return res;
        }

        override void onMouseEnterLeave(bool mouseIsInside) {
            if (!mouseIsInside && OnMouseLeave)
                OnMouseLeave();
        }

        override void onFocusChange() {
            super.onFocusChange();
            if (OnSetFocus)
                OnSetFocus(focused());
        }

        override Vector2i layoutSizeRequest() {
            return mSizeRequest;
        }

        override void layoutSizeAllocation() {
            if (isLinked()) {
                mWasAdded = true;
                if (OnMap)
                    OnMap(widgetBounds());
            }
        }

        override void simulate() {
            //lol, this doesn't even work (simulate is, of course, not called
            //  when the widget is not "linked")
            if (mWasAdded && !isLinked()) {
                mWasAdded = false;
                if (OnUnmap)
                    OnUnmap();
            }
        }

        override void onDraw(Canvas c) {
            if (render)
                render.draw(c);
            if (OnDraw)
                OnDraw(c);
        }
    }

    this() {
        mWidget = new WidgetAdapt();
    }

    Widget widget() {
        return mWidget;
    }

    void setCanFocus(bool f) {
        mWidget.focusable = f;
    }
    void setSizeRequest(Vector2i s) {
        mSizeRequest = s;
    }
    void requestResize() {
        mWidget.needResize();
    }
    void requestFocus() {
        mWidget.claimFocus();
    }
}

LuaRegistry gLuaGuiAdapt;

static this() {
    auto g = new LuaRegistry();
    g.setClassPrefix!(LuaGuiAdapter)("Gui");
    g.ctor!(LuaGuiAdapter)();
    g.properties!(LuaGuiAdapter, "OnMap", "OnUnmap", "OnMouseLeave",
        "OnHandleKeyInput", "OnHandleMouseInput", "OnSetFocus", "OnDraw",
        "render")();
    g.methods!(LuaGuiAdapter, "setCanFocus", "setSizeRequest", "requestResize",
        "requestFocus")();
    gLuaGuiAdapt = g;
}

//doesn't really belong here

LuaRegistry gLuaScenes;

static this() {
    auto g = new LuaRegistry();
    g.ctor!(Scene);
    g.methods!(Scene, "add", "remove", "clear");
    g.methods!(SceneObject, "removeThis");
    g.properties_ro!(SceneObject, "parent");
    g.properties!(SceneObject, "zorder", "active");
    g.properties!(SceneObjectCentered, "pos");
    g.properties!(SceneObjectRect, "rc");
    g.ctor!(SceneDrawRect);
    g.properties!(SceneDrawRect, "color", "fill", "width", "stipple");
    g.ctor!(SceneDrawCircle);
    g.properties!(SceneDrawCircle, "radius", "color", "fill");
    g.ctor!(SceneDrawLine);
    g.properties!(SceneDrawLine, "p1", "p2", "color", "width");
    g.ctor!(SceneDrawSprite);
    g.properties!(SceneDrawSprite, "source", "effect");
    g.ctor!(SceneDrawText);
    g.properties!(SceneDrawText, "text");
    g.ctor!(SceneDrawBox);
    g.properties!(SceneDrawBox, "box");
    gLuaScenes = g;
}
