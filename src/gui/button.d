module gui.button;

import common.common;
import framework.restypes.bitmap;
import framework.event;
import framework.framework;
import framework.font;
import gui.widget;
import gui.label;
import utils.time;
import utils.timer;

///small helper to let checkboxes behave like radio buttons
struct CheckBoxGroup {
    Button[] buttons;

    int checkedIndex() {
        foreach (int index, b; buttons) {
            if (b.checked)
                return index;
        }
        return -1;
    }

    Button checked() {
        int n = checkedIndex();
        return n >= 0 ? buttons[n] : null;
    }

    void add(Button b) {
        buttons ~= b;
        b.checked = false;
    }

    void check(Button b) {
        foreach (bu; buttons) {
            bu.checked = bu is b;
        }
    }
}

//xxx this is a hack
class Button : Label {
    private {
        bool mMouseOver, mMouseInside;
        bool mMouseDown;   //last reported mouse button click
        bool mButtonState; //down or up (true if down)
        bool mIsCheckbox, mChecked;
        Timer mAutoRepeatTimer;
    }

    ///if true, the Button will send click events while pressed
    ///see autoRepeatRate to set number of events per time
    ///if true, behaviour of the button will change: a click event is sent on
    ///the first mouse down event; if false, a single event is sent on mouse up
    bool autoRepeat = false;

    ///auto repeat rate when autoRepeat is enabled
    ///gives the number of click events spawned per second (clicks/seconds)
    Time autoRepeatInterval = timeMsecs(50);
    Time autoRepeatDelay = timeMsecs(500);

    void delegate(Button sender) onClick;
    void delegate(Button sender) onRightClick;
    void delegate(Button sender, bool over) onMouseOver;

    this(Font font = null) {
        super(font);
        mAutoRepeatTimer = new Timer(autoRepeatDelay, &autoRepOnTimer);
        //check time since last click; if framerate is too low, click rate also
        //drops (which is good since simulate() will not be called if the Widget
        //is made invisible temporarly...)
        mAutoRepeatTimer.mode = TimerMode.fixedDelay;
    }

    bool isCheckbox() {
        return mIsCheckbox;
    }
    void isCheckbox(bool set) {
        mIsCheckbox = set;
        if (mIsCheckbox) {
            drawBorder = false;
        }
        updateCheckboxState();
    }

    bool checked() {
        return mChecked;
    }
    void checked(bool set) {
        mChecked = set;
        updateCheckboxState();
    }

    private void updateCheckboxState() {
        if (!mIsCheckbox)
            return;
        auto imgname = mChecked ? "checkbox_on" : "checkbox_off";
        image = globals.guiResources.get!(Surface)(imgname);
    }

    override void onDraw(Canvas c) {
        super.onDraw(c);
        //*g*
        if (mMouseOver) {
            c.drawFilledRect(Vector2i(0), size, Color(1,1,1,0.3));
        }
        //small optical hack: make it visible if the button is pressed
        //feel free to replace this by better looking rendering
        if (mButtonState) {
            c.drawFilledRect(Vector2i(0), size, Color(1,1,1,0.7));
        }
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        mMouseOver = mouseIsInside;
        if (onMouseOver) {
            onMouseOver(this, mouseIsInside);
        }
    }

    //mButtonState: false -> true
    private void buttonSetState(bool state) {
        if (state == mButtonState)
            return;

        mButtonState = state;

        if (state) {
            if (autoRepeat) {
                doClick();
                mAutoRepeatTimer.interval = autoRepeatDelay;
                mAutoRepeatTimer.enabled = true;
            }
        } else {
            mAutoRepeatTimer.enabled = false;
            if (!autoRepeat && mMouseInside) {
                doClick();
            }
        }
    }

    private void doClick() {
        if (mIsCheckbox) {
            mChecked = !mChecked;
            updateCheckboxState();
        }
        if (onClick)
            onClick(this);
    }

    override protected bool onKeyEvent(KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT /*&& bounds.isInside(mousePos)*/) {
            if (key.isDown) {
                //capturing is used to track if the mouse moves inside/outside
                //the button (if mouse is pressed, it stays captured)
                if (captureEnable()) {
                    mMouseDown = true;
                    buttonSetState(true);
                }
            } else if (key.isUp) {
                mMouseDown = false;
                captureDisable();
                buttonSetState(false);
                //xxx: nasty nasty hack (to make it look better, can be removed)
                //should be handled in widget.d or so
                if (!mMouseInside)
                    doMouseEnterLeave(false);
            }
            return true;
        }
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (key.isUp && onRightClick) {
                onRightClick(this);
            }
            return true;
        }
        return super.onKeyEvent(key);
    }

    override protected bool onMouseMove(MouseInfo mi) {
        mMouseInside = testMouse(mi.pos);

        if (!mMouseInside) {
            //if button is pressed, keep captured (normal behaviour across GUIs
            //such as win32, GTK)
            if (!mMouseDown) {
                captureDisable();
            }
            buttonSetState(false);
        } else {
            //true if mouse enters again and button is still pressed
            if (mMouseDown)
                buttonSetState(true);
        }

        return true;
    }

    private void autoRepOnTimer(Timer sender) {
        doClick();
        sender.interval = autoRepeatInterval;
    }

    override void simulate() {
        mAutoRepeatTimer.update();
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        autoRepeat = node.getBoolValue("auto_repeat", autoRepeat);
        autoRepeatDelay = timeMsecs(node.getIntValue("auto_repeat_delay",
            autoRepeatDelay.msecs));
        autoRepeatInterval = timeMsecs(node.getIntValue("auto_repeat_interval",
            autoRepeatInterval.msecs));

        super.loadFrom(loader);

        isCheckbox = node.getBoolValue("check_box", isCheckbox);
        checked = node.getBoolValue("checked", checked);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("button");
    }
}
