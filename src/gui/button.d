module gui.button;

import framework.drawing;
import framework.event;
import framework.font;
import framework.surface;
import gui.boxcontainer;
import gui.global;
import gui.label;
import gui.widget;
import utils.time;
import utils.timer;
import utils.misc;

///small helper to let checkboxes behave like radio buttons
struct CheckBoxGroup {
    CheckBox[] buttons;

    int checkedIndex() {
        foreach (int index, b; buttons) {
            if (b.checked)
                return index;
        }
        return -1;
    }

    CheckBox checked() {
        int n = checkedIndex();
        return n >= 0 ? buttons[n] : null;
    }

    void add(CheckBox b) {
        buttons ~= b;
        b.checked = false;
    }

    void check(CheckBox b) {
        foreach (bu; buttons) {
            bu.checked = bu is b;
        }
    }
}

class ButtonBase : Widget {
    private {
        bool mMouseOver; //mouse is inside Widget or captured
        bool mMouseInside; //mouse is really inside the Widget
        bool mMouseDown;   //last reported mouse button click
        bool mButtonState; //down or up (true if down)
        Timer mAutoRepeatTimer;
        Widget mClient;
        Label mLabel;
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

    void delegate() onClick2;


    this() {
        focusable = true;
        mAutoRepeatTimer = new Timer(autoRepeatDelay, &autoRepOnTimer);
        //check time since last click; if framerate is too low, click rate also
        //drops (which is good since simulate() will not be called if the Widget
        //is made invisible temporarly...)
        mAutoRepeatTimer.mode = TimerMode.fixedDelay;

        auto lbl = new Label();
        setClient(lbl, lbl);
    }

    //can be used to disable keyboard focus
    void allowFocus(bool f) {
        focusable = f;
    }

    override void readStyles() {
        super.readStyles();
        //whatever
        //hack can be removed when styles stuff is improved
        if (auto label = getLabel(false)) {
            auto f = styles.get!(Font)("text-font");
            //xxx possibly triggering resize
            label.font = f;
        }
    }

    override void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        mMouseOver = mouseIsInside;
        if (!mMouseOver)
            mMouseInside = false;
    }

    //state = if button is up (false) or down (true)
    //so normally, going from true -> false generates a click event
    private void buttonSetState(bool state, bool bykeyboard = false) {
        if (state == mButtonState)
            return;

        mButtonState = state;
        styles.setState("button-down", mButtonState);

        if (mClient)
            mClient.setAddToPos(mButtonState ? Vector2i(1) : Vector2i(0));

        if (state) {
            if (autoRepeat) {
                doClick();
                mAutoRepeatTimer.interval = autoRepeatDelay;
                mAutoRepeatTimer.enabled = true;
            }
        } else {
            mAutoRepeatTimer.enabled = false;
            if (!autoRepeat && (mMouseInside || bykeyboard)) {
                doClick();
            }
        }
    }

    protected void doClick() {
        if (onClick2)
            onClick2();
    }

    protected void doRightClick() {
    }

    override bool onKeyDown(KeyInfo key) {
        return handleKey(key);
    }
    override void onKeyUp(KeyInfo key) {
        handleKey(key);
    }

    private bool handleKey(KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT || key.code == Keycode.SPACE) {
            bool kb = !key.isMouseButton;
            if (key.isDown && !key.isRepeated) {
                mMouseDown = true;
                buttonSetState(true, kb);
            } else if (key.isUp) {
                mMouseDown = false;
                buttonSetState(false, kb);
            }
            return true;
        }
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (key.isUp) {
                doRightClick();
            }
            return true;
        }
        return false;
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

        if (auto label = getLabel(false)) {
            label.renderer.translator = loader.locale();
            auto txt = node.getStringValue("text");
            auto markup = node.getStringValue("markup");
            if (txt.length) {
                label.setTextFmt(true, r"\t({})", txt);
            } else if (markup.length) {
                label.textMarkup = markup;
            }
        }

        autoRepeat = node.getBoolValue("auto_repeat", autoRepeat);
        autoRepeatDelay = timeMsecs(node.getIntValue("auto_repeat_delay",
            autoRepeatDelay.msecs));
        autoRepeatInterval = timeMsecs(node.getIntValue("auto_repeat_interval",
            autoRepeatInterval.msecs));

        super.loadFrom(loader);
    }

    //set the client area of the button
    //if label is non-null, it will be returned by getLabel(), and the text
    //  accessor functions will use the label as backend (otherwise, the text
    //  accessors will raise an exception as called)
    void setClient(Widget client, Label label = null) {
        clear();
        mClient = client;
        mLabel = label;
        if (mClient)
            addChild(mClient);
    }

    //if a label is set, return it
    //this is used for the text accessors
    //if must_exist==true, never return null, and raise an exception instead
    Label getLabel(bool must_exist = true) {
        if (!mLabel && must_exist)
            throw new Exception("button has no label");
        return mLabel;
    }

    //tunnel through the text accessors
    //see Label

    void text(string txt) {
        getLabel().text = txt;
    }
    void textMarkup(string txt) {
        getLabel().textMarkup = txt;
    }
    void setText(bool as_markup, string txt) {
        getLabel().setText(as_markup, txt);
    }
    void setTextFmt(T...)(bool as_markup, string fmt, T args) {
        getLabel().setTextFmt(as_markup, fmt, args);
    }
    //returns an empty string if no label set (never throws an exception)
    string text() {
        if (auto label = getLabel(false))
            return label.text;
        return "";
    }
}

class Button : ButtonBase {
    //this shit can go away as soon as GUI uses Events
    void delegate(Button sender) onClick;
    void delegate(Button sender) onRightClick;
    void delegate(Button sender, bool over) onMouseOver;

    this() {
    }

    override void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        if (onMouseOver)
            onMouseOver(this, mMouseOver);
    }

    override void doClick() {
        super.doClick();
        if (onClick)
            onClick(this);
    }

    override void doRightClick() {
        super.doRightClick();
        if (onRightClick)
            onRightClick(this);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("button");
    }
}

class ImageButton : Button {
    private {
        ImageLabel mImage;
    }

    this() {
        mImage = new ImageLabel();
        setClient(mImage);
    }

    void image(Surface img) {
        mImage.image = img;
    }
    Surface image() {
        return mImage.image;
    }

    static this() {
        WidgetFactory.register!(typeof(this))("imagebutton");
    }
}

class CheckBox : ButtonBase {
    private {
        bool mChecked;
        HBoxContainer mBox;
        ImageLabel mStateImage;
    }

    void delegate(CheckBox sender) onClick;

    this() {
        //xxx: spacing should be in styles stuff
        //  (actually, somehow, the layout in general should be)
        mBox = new HBoxContainer(false, 3);
        mStateImage = new ImageLabel();
        mStateImage.setLayout(WidgetLayout.Noexpand());
        mBox.add(mStateImage);
        auto lbl = getLabel();
        lbl.remove();
        mBox.add(lbl);
        setClient(mBox, lbl);
        updateCheckBoxState();
    }

    override void doClick() {
        mChecked = !mChecked;
        updateCheckBoxState();
        super.doClick();
        if (onClick)
            onClick(this);
    }

    bool checked() {
        return mChecked;
    }
    void checked(bool set) {
        mChecked = set;
        updateCheckBoxState();
    }

    private void updateCheckBoxState() {
        auto imgname = mChecked ? "checkbox_on" : "checkbox_off";
        mStateImage.image = gGuiResources.get!(Surface)(imgname);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;
        checked = node.getBoolValue("checked", checked);

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("checkbox");
    }
}
