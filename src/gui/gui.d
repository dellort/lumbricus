module gui.gui;

import framework.console;
import framework.framework;
import framework.event;
import game.common;
import game.game;
import game.scene;
import gui.guiobject;
import gui.frame;
import gui.layout;
import std.string;
import utils.mylist;
import utils.time;
import utils.configfile;
import utils.log;
import utils.rect2;

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
    private MainFrame mMainFrame;

    private Time mLastTime;
    private Vector2i mSize;

    GuiFrame mainFrame() {
        return mMainFrame;
    }

    private class MainFrame : GuiFrame {
        override bool isTopLevel() {
            return true;
        }
        bool putKeyEvent(KeyInfo info) {
            if (info.isMouseButton) {
                internalHandleMouseEvent(null, &info);
                return true; //???
            } else {
                return internalHandleKeyEvent(info);
            }
        }

        void putMouseMove(MouseInfo info) {
            internalHandleMouseEvent(&info, null);
        }

        protected override bool onKeyDown(char[] bind, KeyInfo key) {
            if (key.code == Keycode.TAB) {
                mMainFrame.nextFocus();
                return true;
            }
            return false;
        }

        GuiLayouterNull layout;

        this() {
            layout = new GuiLayouterNull();
            addLayouter(layout);
        }

        //not particularly elegant; but this will make all added GuiObjects to
        //be layouted such that they'll cover the whole screen
        /+package+/ override void doAdd(GuiObject o) {
            super.doAdd(o);
            layout.add(o);
        }
    }

    this(Vector2i size) {
        mLastTime = timeCurrentTime();

        mMainFrame = new MainFrame();
        //??? can't harm
        mMainFrame.stateChanged();

        this.size = size;
    }

    void size(Vector2i size) {
        mSize = size;
        mMainFrame.bounds = Rect2i(Vector2i(0), size);
    }
    Vector2i size() {
        return mSize;
    }

    void doFrame(Time curTime) {
        Time deltaT = curTime - mLastTime;

        mMainFrame.doSimulate(curTime, deltaT);

        mLastTime = curTime;
    }

    void draw(Canvas canvas) {
        mMainFrame.view.draw(canvas);
    }

    //distribute events to these EventSink things
    bool putOnKeyDown(KeyInfo info) {
        assert(info.type == KeyEventType.Down);
        return putKeyEvent(info);
    }
    bool putOnKeyPress(KeyInfo info) {
        assert(info.type == KeyEventType.Press);
        return putKeyEvent(info);
    }
    bool putOnKeyUp(KeyInfo info) {
        assert(info.type == KeyEventType.Up);
        return putKeyEvent(info);
    }
    bool putKeyEvent(KeyInfo info) {
        return mMainFrame.putKeyEvent(info);
    }
    void putOnMouseMove(MouseInfo info) {
        mMainFrame.putMouseMove(info);
    }
}
