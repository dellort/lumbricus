//this is not a Lua binding for the GUI
//it just allows a Lua GUI run inside the D GUI
module gui.lua;

import common.scene;
import framework.event;
import framework.keybindings;
import framework.lua;
import gui.widget;
import utils.misc;
import utils.rect2;
import utils.vector2;


class LuaGuiAdapter {
    private {
        WidgetAdapt mWidget;
        bool mWasAdded;
    }

    Vector2i sizeRequest;

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
    //warning: because callEventHandler is overridden, some normal widget event
    //  handlers such as onKeyDown etc. won't be called
    private class WidgetAdapt : Widget {
        this() {
            focusable = true;
            doClipping = true;
            //this property is practically overridden by the Lua event handler
            isClickable = true;
        }

        override bool callEventHandler(InputEvent event, bool filter) {
            bool res = false;
            if (event.isKeyEvent) {
                if (OnHandleKeyInput)
                    res = OnHandleKeyInput(event.keyEvent);
            } else if (event.isMouseEvent) {
                if (OnHandleMouseInput)
                    res = OnHandleMouseInput(event.mouseEvent);
            } else {
                assert(false, "doesn't happen");
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
            return sizeRequest;
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
            if (render && render.active)
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

    void canFocus(bool f) {
        mWidget.focusable = f;
    }
    bool canFocus() {
        return mWidget.focusable;
    }

    void requestResize() {
        mWidget.needResize();
    }
    void requestFocus() {
        mWidget.claimFocus();
    }

    bool isLinked() {
        return mWidget.isLinked();
    }
}

//wrapper prevents memory allocation in D
Keycode getKeycode(TempString s) {
    return translateKeyIDToKeycode(s.raw);
}

LuaRegistry gLuaGuiAdapt;

static this() {
    auto g = new LuaRegistry();
    g.setClassPrefix!(LuaGuiAdapter)("Gui");
    g.ctor!(LuaGuiAdapter)();
    g.properties!(LuaGuiAdapter, "OnMap", "OnUnmap", "OnMouseLeave",
        "OnHandleKeyInput", "OnHandleMouseInput", "OnSetFocus", "OnDraw",
        "render", "sizeRequest", "canFocus")();
    g.methods!(LuaGuiAdapter, "requestResize", "requestFocus")();
    g.properties_ro!(LuaGuiAdapter, "isLinked");
    g.ctor!(KeyBindings)();
    g.method!(KeyBindings, "scriptAddBinding")("addBinding");
    g.func!(getKeycode)("keycode");
    gLuaGuiAdapt = g;
}

//doesn't really belong here

LuaRegistry gLuaScenes;

//xxx possibly remove in favour of directly using Canvas?
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

LuaRegistry gLuaCanvas;

static this() {
    auto g = new LuaRegistry();
    //drawSprite?
    g.methods!(Canvas, "draw", "drawPart", "drawCircle", "drawFilledCircle",
        "drawLine", "drawRect", "drawFilledRect", "setWindow", "translate",
        "clip", "setScale", "setBlend", "pushState", "popState", "drawTiled",
        "drawTexLine", "drawStretched");
    g.method!(Canvas, "drawSpriteEffect")("drawSprite");
    //Note: for text rendering, FormattedText will have to do
    //      it's already registered in game.lua.base
    gLuaCanvas = g;
}
