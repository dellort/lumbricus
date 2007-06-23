module gui.guiobject;

import framework.framework;
import game.game;
import game.scene;
import utils.configfile;
import utils.mylist;
import utils.time;

class EventSink {
    //(optional) set of key bindings for this EventSink
    //if not set, bind parameter will be empty
    private KeyBindings mBindings;

    bool delegate(char[] bind, KeyInfo key) onKeyDown;
    bool delegate(char[] bind, KeyInfo key) onKeyUp;
    bool delegate(char[] bind, KeyInfo key) onKeyPress;
    bool delegate(MouseInfo mouse) onMouseMove;

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
    package GuiObject mObject; //(mObject.getEventSink() is this) == true

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
            case KeyEvent.Down: return onKeyDown ? onKeyDown(bind, info) : false;
            case KeyEvent.Up: return onKeyUp ? onKeyUp(bind, info) : false;
            case KeyEvent.Press: return onKeyPress ? onKeyPress(bind, info) : false;
            default: assert(false);
        }
    }

    package void callMouseHandler(MouseInfo info) {
        mMousePos = info.pos;
        if (onMouseMove)
            onMouseMove(info);
    }

    package this(GuiObject owner) {
        mObject = owner;
    }
}

//base class for gui stuff
//gui objects are simulated with absolute time, can be drawn and
//accept events by key bindings
class GuiObject : SceneObjectPositioned {
    protected EventSink mEvents;
    package bool mHasFocus;
    //called if the object was removed, used by GuiMain
    package void delegate(GuiObject) mOnKilled;

    this() {
        //all gui objects accept events (thats their nature)
        //you can just leave the callbacks blank to pass an event on
        mEvents = new EventSink(this);
    }

    protected override void onChangeScene() {
        if (!active && mOnKilled) {
            mOnKilled(this);
        }
        super.onChangeScene();
    }

    //load a set of key bindings for this control (used only for own events)
    void loadBindings(ConfigNode node) {
        KeyBindings binds = new KeyBindings();
        binds.loadFrom(node);
        events.bindings = binds;
    }

    package EventSink events() {
        return mEvents;
    }

    /*void engine(GameEngine eng) {
        mEngine = eng;
    }*/

    void simulate(Time curTime, Time deltaT) {
    }

    void resize() {
    }
}
