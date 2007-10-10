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

    private Vector2i mSize;

    SimpleContainer mainFrame() {
        return mMainFrame;
    }

    private class MainFrame : SimpleContainer {
        this() {
            doMouseEnterLeave(true); //mous always in, initial event
            pollFocusState();
        }

        override bool isTopLevel() {
            return true;
        }

        void setSize(Vector2i size) {
            layoutContainerAllocate(Rect2i(Vector2i(0), size));
        }

        bool putKeyEvent(KeyInfo info) {
            return handleKeyEvent(info);
        }

        void putMouseMove(MouseInfo info) {
            updateMousePos(info.pos);
            handleMouseEvent(info);
        }

        protected override bool onKeyEvent(KeyInfo key) {
            if (key.isDown && key.code == Keycode.TAB) {
                bool res = mMainFrame.nextFocus();
                if (!res)
                    mMainFrame.nextFocus();
                return true;
            }
            return super.onKeyEvent(key);
        }
    }

    this(Vector2i size) {
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
        mMainFrame.internalSimulate();
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
