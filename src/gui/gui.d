module gui.gui;

import framework.console;
import framework.framework;
import game.common;
import game.game;
import game.scene;
import gui.guiobject;
import std.string;
import utils.mylist;
import utils.time;
import utils.configfile;

//ZOrders!
//maybe keep in sync with game.Scene.cMaxZOrder
//these values are for globals.toplevel.guiscene
enum GUIZOrder : int {
    Invisible = 0,
    Background,
    Game,
    Gui,
    Console,
    FPS,
}

//main gui class, manages gui elements and forwards events
//(should be) singleton
class GuiMain {
    private Scene mGuiScene;
    private SceneView mRootView;

    private Time mLastTime;
    private GameEngine mEngine;

    private EventSink mFocus, events;

    private Vector2i mSize, mMousePos;

    this(Vector2i size) {
        mGuiScene = new Scene();
        mGuiScene.size = size;
        mRootView = new SceneView();
        mRootView.clientscene = mGuiScene;
        mRootView.pos = Vector2i(0);
        mRootView.size = size;

        //for root events, e.g. focus change
        events = new EventSink();

        mLastTime = timeCurrentTime();
    }

    void add(GuiObject o, GUIZOrder z) {
        o.setScene(mGuiScene, z);
        o.resize();
    }

    void engine(GameEngine engine) {
        mEngine = engine;
        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go)
                go.engine = engine;
        }
    }

    //load a set of key bindings for the main gui (override all others)
    void loadBindings(ConfigNode node) {
        KeyBindings binds = new KeyBindings();
        binds.loadFrom(node);
        events.bindings = binds;
    }

    void size(Vector2i size) {
        mSize = size;
        mGuiScene.size = mSize;
        mRootView.size = mSize;

        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go)
                go.resize();
        }
    }
    Vector2i size() {
        return mSize;
    }

    void doFrame(Time curTime) {
        float deltaT = (curTime.msecs - mLastTime.msecs)/1000.0f;

        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go)
                go.simulate(deltaT);
        }

        mLastTime = curTime;
    }

    void draw(Canvas canvas) {
        mRootView.draw(canvas);
    }

    void setFocus(GuiObject go) {
        mFocus = go ? go.events : null;
    }

    private bool doKeyEvent(EventSink.KeyEvent ev, KeyInfo info) {
        if (info.isMouseButton) {
            doMouseButtons(ev, info);
        }
        //process main gui events (keyboard only)
        if (events.callKeyHandler(ev, info)) {
            return true;
        }
        //avoid to send the event twice
        //this still could be wrong, though
        if (mFocus && !info.isMouseButton) {
            return mFocus.callKeyHandler(ev, info);
        }
        return false;
    }
    //distribute events to these EventSink things
    bool putOnKeyDown(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Down, info);
    }
    bool putOnKeyPress(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Press, info);
    }
    bool putOnKeyUp(KeyInfo info) {
        return doKeyEvent(EventSink.KeyEvent.Up, info);
    }
    void putOnMouseMove(MouseInfo info) {
        doMouseMove(info);
    }

    //event handling
    void doMouseMove(MouseInfo info) {
        //xxx following line
        mMousePos = info.pos;

        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go) {
                auto pso = cast(SceneObjectPositioned)obj;
                if (isInside(pso, info.pos)) {
                    //deliver
                    go.events.callMouseHandler(info);
                }
            }
        }
    }

    //duplicated from above
    void doMouseButtons(EventSink.KeyEvent ev, KeyInfo info) {
        //last mouse position in mMousePos should be valid
        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go) {
                auto pso = cast(SceneObjectPositioned)obj;
                if (isInside(pso, mMousePos)) {
                    //deliver
                    go.events.callKeyHandler(ev, info);
                }
            }
        }
    }

    private static bool isInside(SceneObjectPositioned obj, Vector2i pos) {
        return pos.isInside(obj.pos, obj.size);
    }
}
