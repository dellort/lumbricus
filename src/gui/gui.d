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
import utils.log;

//ZOrders!
//maybe keep in sync with game.Scene.cMaxZOrder
//these values are for globals.toplevel.guiscene
enum GUIZOrder : int {
    Invisible = 0,
    Background,
    Game,
    Gui,
    Loading,
    Console,
    FPS,
}

//main gui class, manages gui elements and forwards events
//(should be) singleton
class GuiMain {
    private Scene mGuiScene;
    private SceneView mRootView;

    private Time mLastTime;

    private GuiObject mFocus;
    private GuiEventsObject events;

    private Vector2i mSize, mMousePos;

    class GuiEventsObject : GuiObject {
        protected override bool onKeyDown(char[] bind, KeyInfo key) {
            if (key.code == Keycode.TAB) {
                nextFocus();
                return true;
            }
            return false;
        }
    }

    this(Vector2i size) {
        mGuiScene = new Scene();
        mGuiScene.size = size;
        mRootView = new SceneView();
        mRootView.clientscene = mGuiScene;
        mRootView.pos = Vector2i(0);
        mRootView.size = size;

        //for root events, e.g. focus change
        events = new GuiEventsObject();

        mLastTime = timeCurrentTime();
    }

    void add(GuiObject o, GUIZOrder z) {
        o.mChangeActiveness = &onSubObjectChanged;
        o.setScene(mGuiScene, z);
        onSubObjectChanged(o); //xxx??? shouldn't be needed (to set initial focus)
        o.resize();
    }

    //focus rules:
    // object becomes active => if greedy focus, set focus immediately
    // object becomes inactive => object which was focused before gets focus
    //    to do that, GuiObject.mFocusAge is used
    // tab => next focusable GuiObject in scene is focused

    //only grows, wonder what happens if it overflows
    private int mCurrentFocusAge;

    //linked to a subobject's onChangeScene()
    private void onSubObjectChanged(GuiObject o) {
        gDefaultLog("change %s", o);
        //if object was added/removed, o.active = new state
        if (o.active && o.canHaveFocus) {
            if (o.greedyFocus) {
                o.mFocusAge = ++mCurrentFocusAge;
                setFocus(o);
            }
        } else {
            //maybe was killed, take focus
            if (mFocus is o) {
                //the element which was focused before should be picked
                //pick element with highest age, take old and set new focus
                GuiObject winner;
                foreach (SceneObject cur; mGuiScene.activeObjects) {
                    assert(cur.active);
                    GuiObject curgui = cast(GuiObject)cur;
                    if (curgui && curgui.canHaveFocus &&
                        (!winner || (winner.mFocusAge < curgui.mFocusAge)))
                    {
                        winner = curgui;
                    }
                }
                setFocus(winner);
            }
        }
    }

    //like when you press <tab>
    //  forward = false: go backwards in focus list, i.e. undo <tab>
    void nextFocus(bool forward = true) {
        //NOTE: the stupid thing is that not all objects here are GuiObjects
        auto objects = mGuiScene.activeObjects();
        SceneObject current = mFocus;
        if (!current) {
            //forward==true: finally pick first, else last
            current = forward ? objects.tail() : objects.head();
        }
        do {
            if (forward) {
                current = objects.ring_next(current);
            } else {
                current = objects.ring_prev(current);
            }
            GuiObject curgui = cast(GuiObject)current;
            if (curgui && curgui.canHaveFocus) {
                setFocus(curgui);
                return;
            }
        } while (current !is mFocus);
        setFocus(null);
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
        Time deltaT = curTime - mLastTime;

        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go)
                go.simulate(curTime, deltaT);
        }

        mLastTime = curTime;
    }

    void draw(Canvas canvas) {
        mRootView.draw(canvas);
    }

    void takeFocus() {
        setFocus(null);
    }

    void setFocus(GuiObject go) {
        if (go is mFocus)
            return;

        if (mFocus) {
            gDefaultLog("remove focus: %s", mFocus);
            mFocus.mHasFocus = false;
            mFocus = null;
        }
        mFocus = go;
        if (go && go.canHaveFocus) {
            go.mHasFocus = true;
            go.mFocusAge = ++mCurrentFocusAge;
            gDefaultLog("set focus: %s", mFocus);
        }
    }

    private bool doKeyEvent(GuiObject.KeyEvent ev, KeyInfo info) {
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
        return doKeyEvent(GuiObject.KeyEvent.Down, info);
    }
    bool putOnKeyPress(KeyInfo info) {
        return doKeyEvent(GuiObject.KeyEvent.Press, info);
    }
    bool putOnKeyUp(KeyInfo info) {
        return doKeyEvent(GuiObject.KeyEvent.Up, info);
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
                    go.callMouseHandler(info);
                }
            }
        }
    }

    //duplicated from above
    void doMouseButtons(GuiObject.KeyEvent ev, KeyInfo info) {
        //last mouse position in mMousePos should be valid
        foreach (obj, int z; mGuiScene) {
            GuiObject go = cast(GuiObject)obj;
            if (go) {
                auto pso = cast(SceneObjectPositioned)obj;
                if (isInside(pso, mMousePos)) {
                    //deliver
                    go.callKeyHandler(ev, info);
                }
            }
        }
    }

    private static bool isInside(SceneObjectPositioned obj, Vector2i pos) {
        return pos.isInside(obj.pos, obj.size);
    }
}
