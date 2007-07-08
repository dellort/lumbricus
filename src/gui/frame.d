module gui.frame;
import framework.framework : Canvas;
import game.scene;
import gui.guiobject;
import gui.gui;
import gui.layout;
import utils.misc;
import framework.event;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.log;

/// Group of GUI objects, like a window.
class GuiFrame : GuiObject {
    private {
        Scene mFrameScene;
        SceneView mFrameView;
        GuiObject[] mGuiObjects;
        GuiObject mFocus; //local focus
        //only grows, wonder what happens if it overflows
        int mCurrentFocusAge;
        //thought about making them GuiObjects, but it seems simpler this way
        GuiLayouter[] mLayouters;
        //frame is "transparent"
        bool mIsVirtualFrame;
    }

    SceneView view() {
        return mFrameView;
    }
    Scene scene() {
        return mFrameScene;
    }

    /// Add an element to the GUI, which gets automatically cleaned up later.
    void add(GuiObject obj) {
        obj.parent = this;
    }

    //called by GuiObject.parent(...)
    void doAdd(GuiObject o) {
        assert(o.parent is this);
        assert(arraySearch(mGuiObjects, o) < 0);
        mGuiObjects ~= o;
        recheckSubFocus(o);
        gDefaultLog("added %s to %s", o, this);
    }

    //called by this.remove()
    protected void doRemove(GuiObject obj) {
        assert(obj.parent is this);
        obj.mParent = null;
        arrayRemove(mGuiObjects, obj);
        obj.remove();
    }

    /// Remove GUI element; that element gets destroyed.
    void removeSubobject(GuiObject obj) {
        doRemove(obj);
        if (obj is mFocus) {
            mFocus = null;
            recheckFocus(); //yyy: check if correct
        }
        gDefaultLog("removed %s from %s", obj, this);
    }

    /+package+/ override void stateChanged() {
        //2 nops if already done, so no need to know if it was just added or so
        //(this was later added and didn't fit in elsewhere, grrr)
        mFrameView.scene = mParent ? mParent.scene : null;
        mFrameView.zorder = zorder;
        mFrameView.active = true;
        super.stateChanged();
    }

    //called by GuiObject.to
    /+package+/ void subObjectToFront(GuiObject sub) {
        assert(sub.parent is this);
        int pos = arraySearch(mGuiObjects, sub);
        swap(mGuiObjects[pos], mGuiObjects[$-1]);
    }

    //if we're a (transitive) parent of obj
    bool isTransitiveParentOf(GuiObject obj) {
        //assume no cyclic parents
        while (obj) {
            if (obj is this)
                return true;
            obj = obj.parent;
        }
        return false;
    }

    override bool testMouse(Vector2i pos) {
        if (mIsVirtualFrame) {
            pos = coordsToClient(pos);
            foreach (o; mGuiObjects) {
                if (o.testMouse(pos))
                    return true;
            }
            return false;
        } else {
            return super.testMouse(pos);
        }
    }

    //the GuiFrame itself accepts to be focused
    //look at GuiVirtualFrame if the frame shouldn't be focused itself
    override bool canHaveFocus() {
        if (mIsVirtualFrame) {
            //xxx maybe a bit expensive; cache it?
            foreach (o; mGuiObjects) {
                if (o.canHaveFocus)
                    return true;
            }
        }
        return true;
    }
    override bool greedyFocus() {
        if (mIsVirtualFrame) {
            foreach (o; mGuiObjects) {
                if (o.greedyFocus)
                    return true;
            }
        }
        return false;
    }

    /// "Virtual" frame: It just groups all its subobject, but isn't visible
    /// itself, doesn't accept any events for itself (only sub objects, but i.e.
    /// doesn't take focus or accept mouse events for itself), doesn't draw
    /// anything (except to show sub objects),  but it does clipping
    void virtualFrame(bool set) {
        mIsVirtualFrame = set;
    }

    this() {
        mFrameScene = new Scene();
        mFrameView = new SceneView();
        mFrameView.clientscene = mFrameScene;
        mFrameView.zorder = zorder;
    }

    /// Deinitialize GUI.
    //xxx: ???
    protected void killGui() {
        foreach (GuiObject o; mGuiObjects) {
            //should be enough
            removeSubobject(o);
        }
        mGuiObjects = null;
    }

    /// Remove from parent.
    override void remove() {
        super.remove();
        //killGui();
    }

    void addLayouter(GuiLayouter gl) {
        assert(arraySearch(mLayouters, gl) < 0);
        mLayouters ~= gl;
        gl.frame = this;
        needRelayout();
    }

    void removeLayouter(GuiLayouter gl) {
        arrayRemove(mLayouters, gl);
        gl.frame = null;
    }

    override void relayout() {
        //important: bounds() also defines clipping rect of the frame
        mFrameView.pos = bounds.p1; //yyy???
        mFrameView.size = size;
        //xxx: later maybe support scrolling or such spiffy things
        mFrameScene.size = size;
        //propagate downwards
        foreach (o; mLayouters) {
            o.relayout();
        }
    }

    //focus rules:
    // object becomes active => if greedy focus, set focus immediately
    // object becomes inactive => object which was focused before gets focus
    //    to do that, GuiObject.mFocusAge is used
    // tab => next focusable GuiObject in scene is focused

    //added = true: o was added newly or o.canhaveFocus got true
    //see recheckSubFocus(GuiObject o)
    private void doRecheckSubFocus(GuiObject o, bool added) {
        if (added) {
            if (o.canHaveFocus && o.greedyFocus) {
                o.mFocusAge = ++mCurrentFocusAge;
                localFocus = o;
            }
        } else {
            //maybe was killed, take focus
            if (mFocus is o) {
                //the element which was focused before should be picked
                //pick element with highest age, take old and set new focus
                GuiObject winner;
                foreach (curgui; mGuiObjects) {
                    if (curgui.canHaveFocus &&
                        (!winner || (winner.mFocusAge < curgui.mFocusAge)))
                    {
                        winner = curgui;
                    }
                }
                localFocus = winner;
            }
        }
    }

    //called by anyone if o.canHaveFocus changed
    void recheckSubFocus(GuiObject o) {
        doRecheckSubFocus(o, o.canHaveFocus);
    }

    //like when you press <tab>
    //  forward = false: go backwards in focus list, i.e. undo <tab>
    void nextFocus(bool forward = true) {
        auto cur = mFocus;
        if (!cur) {
            //forward==true: finally pick first, else last
            cur = forward ? mGuiObjects[$-1] : mGuiObjects[0];
        }
        auto iterate = forward ?
            &arrayFindPrev!(GuiObject) : &arrayFindNext!(GuiObject);
        auto next = arrayFindFollowingPred(mGuiObjects, cur, iterate,
            (GuiObject o) {
                return o.canHaveFocus;
            }
        );
        localFocus = next;
    }

    //"local focus": if the frame had the real focus, the element that'd be
    //  focused now
    //"real/global focus": an object and all its parents are locally focused
    GuiObject localFocus() {
        return mFocus;
    }

    //doesn't set the global focus; do "go.focused = true;" for that
    void localFocus(GuiObject go) {
        if (go is mFocus)
            return;

        if (mFocus) {
            gDefaultLog("remove local focus: %s from %s", mFocus, this);
            auto tmp = mFocus;
            mFocus = null;
            tmp.stateChanged();
        }
        mFocus = go;
        if (go && go.canHaveFocus) {
            go.mFocusAge = ++mCurrentFocusAge;
            gDefaultLog("set local focus: %s for %s", mFocus, this);
            go.stateChanged();
        }
    }

    override void onFocusChange() {
        super.onFocusChange();
        //propagate focus change downwards...
        foreach (o; mGuiObjects) {
            o.stateChanged();
        }
    }

    //translate usual coordinates (i.e. bounds(), mousePos()) to the client
    //coords, which are used for the sub objects
    Vector2i coordsToClient(Vector2i pos) {
        //this is enough, because all GuiFrames are done using SceneViews
        return mFrameView.toClientCoords(pos);
    }

    /+package+/ override void internalHandleMouseEvent(MouseInfo* mi, KeyInfo* ki)
    {
        //NOTE: mouse buttons (ki) don't have the mousepos; use the old one then
        if (mi) {
            internalUpdateMousePos(mi.pos);
        }
        //check if any children are hit by this
        auto clientmp = coordsToClient(mousePos);
        //objects towards the end of the array are later drawn => _reverse
        //xxx: mouse capture
        foreach_reverse(o; mGuiObjects) {
            if (o.testMouse(clientmp)) {
                //huhuhu a hit! call its event handler
                if (mi) {
                    MouseInfo mi2 = *mi;
                    mi2.pos = clientmp;
                    o.internalHandleMouseEvent(&mi2, null);
                } else {
                    o.internalHandleMouseEvent(null, ki);
                }
                return;
            }
        }
        //nothing hit; invoke default handler for this
        super.internalHandleMouseEvent(mi, ki);
    }

    override /+package+/ bool internalHandleKeyEvent(KeyInfo info) {
        //first try to handle locally
        //the super.-method invokes the onKey*() functions
        if (super.internalHandleKeyEvent(info))
            return true;
        //event wasn't handled, handle by sub objects
        if (mFocus) {
            if (mFocus.internalHandleKeyEvent(info))
                return true;
        }
        return false;
    }

    override /+package+/ void doSimulate(Time curTime, Time deltaT) {
        foreach (obj; mGuiObjects) {
            obj.doSimulate(curTime, deltaT);
        }
        super.doSimulate(curTime, deltaT);
    }
}
