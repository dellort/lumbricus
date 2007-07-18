module gui.gui;

import framework.console;
import framework.framework;
public import framework.event;
import common.common;
import gui.widget;
import gui.container;
import std.string;
import utils.mylist;
import utils.time;
import utils.configfile;
import utils.log;
import utils.rect2;

//main gui class, manages gui elements and forwards events
//(should be) singleton
class GuiMain {
    private MainFrame mMainFrame;

    private Time mLastTime;
    private Vector2i mSize;

    SimpleContainer mainFrame() {
        return mMainFrame;
    }

    private class MainFrame : SimpleContainer {
        this() {
            pollFocusState();
        }

        override bool isTopLevel() {
            return true;
        }

        void setSize(Vector2i size) {
            layoutContainerAllocate(Rect2i(Vector2i(0), size));
        }

        bool putKeyEvent(KeyInfo info) {
            if (info.isMouseButton) {
                return handleMouseEvent(null, &info);
            } else {
                return handleKeyEvent(info);
            }
        }

        void putMouseMove(MouseInfo info) {
            handleMouseEvent(&info, null);
        }

        protected override bool onKeyDown(char[] bind, KeyInfo key) {
            if (key.code == Keycode.TAB) {
                bool res = mMainFrame.nextFocus();
                if (!res)
                    mMainFrame.nextFocus();
                return true;
            }
            return false;
        }
    }

    this(Vector2i size) {
        mLastTime = timeCurrentTime();
        mMainFrame = new MainFrame();
        this.size = size;
    }

    void size(Vector2i size) {
        mSize = size;
        mMainFrame.setSize(mSize);
    }
    Vector2i size() {
        return mSize;
    }

    void doFrame(Time curTime) {
        Time deltaT = curTime - mLastTime;

        mMainFrame.internalSimulate(curTime, deltaT);

        mLastTime = curTime;
    }

    void draw(Canvas canvas) {
        mMainFrame.doDraw(canvas);
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
