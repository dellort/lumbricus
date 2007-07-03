module gui.guiobject;

import framework.framework;
import game.game;
import game.scene;
import utils.configfile;
import utils.mylist;
import utils.time;

//base class for gui stuff
//gui objects are simulated with absolute time, can be drawn and
//accept events by key bindings
class GuiObject : SceneObjectPositioned {
    package bool mHasFocus;
    package int mFocusAge;
    //linked to onChangeScene
    package void delegate(GuiObject) mChangeActiveness;

    //--- former EventSink start (delegates replaced by empty methods)

    //(optional) set of key bindings for this EventSink
    //if not set, bind parameter will be empty
    private KeyBindings mBindings;

    protected bool onKeyDown(char[] bind, KeyInfo key) {
        return false;
    }
    protected bool onKeyUp(char[] bind, KeyInfo key) {
        return false;
    }
    protected bool onKeyPress(char[] bind, KeyInfo key) {
        return false;
    }
    protected bool onMouseMove(MouseInfo mouse) {
        return false;
    }

    private enum KeyEvent {
        Down,
        Up,
        Press
    }

    package void bindings(KeyBindings bind) {
        mBindings = bind;
    }
    KeyBindings bindings() {
        return mBindings;
    }

    private Vector2i mMousePos;  //see mousePos()

    //last known mouse position, that is inside this "window"
    Vector2i mousePos() {
        return mMousePos;
    }

    package bool callKeyHandler(KeyEvent type, KeyInfo info) {
        char[] bind;
        if (mBindings) {
            bind = mBindings.findBinding(info);
        }
        switch (type) {
            case KeyEvent.Down: return onKeyDown(bind, info);
            case KeyEvent.Up: return onKeyUp(bind, info);
            case KeyEvent.Press: return onKeyPress(bind, info);
            default: assert(false);
        }
    }

    package void callMouseHandler(MouseInfo info) {
        mMousePos = info.pos;
        onMouseMove(info);
    }

    //--- former EventSink end

    /// Return true if this can have a focus (used for treatment of <tab>).
    bool canHaveFocus() {
        return false;
    }

    /// Return true if focus should set to this element when it becomes active.
    /// Only used if canHaveFocus() is true.
    bool greedyFocus() {
        return false;
    }

    this() {
    }

    protected override void onChangeScene(bool changed_activeness) {
        if (changed_activeness)
            recheckFocus();
        super.onChangeScene(changed_activeness);
    }

    //call if canHaveFocus() could have changed, although object was not added
    //or removed to the scene *sigh*
    void recheckFocus() {
        if (mChangeActiveness) {
            mChangeActiveness(this);
        }
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        bindings = new KeyBindings();
        bindings.loadFrom(node);
    }

    void simulate(Time curTime, Time deltaT) {
    }

    void resize() {
    }
}
