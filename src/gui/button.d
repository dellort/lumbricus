module gui.button;

import common.common;
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
        bool mMouseOver; //mouse is inside Widget or captured
        bool mMouseInside; //mouse is really inside the Widget
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

    ///if this is a checkbox, use the standard checkbox images
    ///if false, don't touch the image
    bool useCheckBoxImages = true;

    ///auto repeat rate when autoRepeat is enabled
    ///gives the number of click events spawned per second (clicks/seconds)
    Time autoRepeatInterval = timeMsecs(50);
    Time autoRepeatDelay = timeMsecs(500);

    ///True to light up the button on mouseover/click
    //-- was never disabled, if needed add as style bool enableHighlight = true;

    void delegate(Button sender) onClick;
    void delegate() onClick2;
    void delegate(Button sender) onRightClick;
    void delegate(Button sender, bool over) onMouseOver;

    this() {
        super();
        mAutoRepeatTimer = new Timer(autoRepeatDelay, &autoRepOnTimer);
        //check time since last click; if framerate is too low, click rate also
        //drops (which is good since simulate() will not be called if the Widget
        //is made invisible temporarly...)
        mAutoRepeatTimer.mode = TimerMode.fixedDelay;
    }

    //undo what was set in label.d
    override bool onTestMouse(Vector2i) {
        return true;
    }

    bool isCheckbox() {
        return mIsCheckbox;
    }
    void isCheckbox(bool set) {
        if (mIsCheckbox == set)
            return;
        if (set) {
            styles.addClass("checkbox");
        } else {
            styles.removeClass("checkbox");
        }
        mIsCheckbox = set;
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
        if (useCheckBoxImages) {
            auto imgname = mChecked ? "checkbox_on" : "checkbox_off";
            image = globals.guiResources.get!(Surface)(imgname);
        }
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        mMouseOver = mouseIsInside;
        if (!mMouseOver)
            mMouseInside = false;
        if (onMouseOver) {
            onMouseOver(this, mouseIsInside);
        }
    }

    //state = if button is up (false) or down (true)
    //so normally, going from true -> false generates a click event
    private void buttonSetState(bool state) {
        if (state == mButtonState)
            return;

        mButtonState = state;
        styles.setState("button-down", mButtonState);

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

    protected void doClick() {
        if (mIsCheckbox) {
            mChecked = !mChecked;
            updateCheckboxState();
        }
        if (onClick)
            onClick(this);
        if (onClick2)
            onClick2();
    }

    override protected void onKeyEvent(KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT) {
            if (key.isDown) {
                mMouseDown = true;
                buttonSetState(true);
            } else if (key.isUp) {
                mMouseDown = false;
                buttonSetState(false);
            }
            return;
        }
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (key.isUp && onRightClick) {
                onRightClick(this);
            }
        }
    }

    override protected void onMouseMove(MouseInfo mi) {
        mMouseInside = testMouse(mi.pos);

        if (!mMouseInside) {
            buttonSetState(false);
        } else {
            //true if mouse enters again and button is still pressed
            if (mMouseDown)
                buttonSetState(true);
        }
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
