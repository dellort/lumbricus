module gui.button;

import framework.restypes.bitmap;
import framework.event;
import framework.framework;
import gui.widget;
import gui.label;
import utils.time;

//xxx this is a hack
class Button : Label {
    private {
        bool mMouseOver, mMouseInside;
        bool mMouseDown;   //last reported mouse button click
        bool mButtonState; //down or up (true if down)
        bool mIsCheckbox, mChecked;
        Time mLastAutoRepeat; //last time an auto repeated click event was sent
    }

    ///if true, the Button will send click events while pressed
    ///see autoRepeatRate to set number of events per time
    ///if true, behaviour of the button will change: a click event is sent on
    ///the first mouse down event; if false, a single event is sent on mouse up
    bool autoRepeat = false;

    ///auto repeat rate when autoRepeat is enabled
    ///gives the number of click events spawned per second (clicks/seconds)
    float autoRepeatRate = 2;

    void delegate(Button sender) onClick;
    void delegate(Button sender) onRightClick;
    void delegate(Button sender, bool over) onMouseOver;

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
        auto imgname = mChecked ? "/checkbox_on" : "/checkbox_off";
        image = gFramework.resources.resource!(BitmapResource)(imgname)
            .get().createTexture();
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
                mLastAutoRepeat = timeCurrentTime();
                doClick();
            }
        } else {
            if (!autoRepeat && mMouseInside) {
                doClick();
            }
        }
    }

    private void doClick() {
        //setting this is only useful when autoRepeat enabled
        mLastAutoRepeat = timeCurrentTime();
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

    override void simulate() {
        if (!autoRepeat || !mButtonState)
            return;
        //check time since last click; if framerate is too low, click rate also
        //drops (which is good since simulate() will not be called if the Widget
        //is made invisible temporarly...)
        Time diff = timeCurrentTime() - mLastAutoRepeat;
        if (diff.secsf > 1.0f/autoRepeatRate)
            doClick();
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        autoRepeat = node.getBoolValue("auto_repeat", autoRepeat);
        autoRepeatRate = node.getFloatValue("auto_repeat_rate", autoRepeatRate);

        super.loadFrom(loader);

        isCheckbox = node.getBoolValue("check_box", isCheckbox);
        checked = node.getBoolValue("checked", checked);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("button");
    }
}
