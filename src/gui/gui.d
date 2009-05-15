module gui.gui;

import common.config;
import framework.framework;
public import framework.event;
import framework.i18n;
import gui.widget;
import gui.container;
import gui.styles;
import utils.time;
import utils.configfile;
import utils.log;
import utils.rect2;

//top-level-widget, only one instance of this is allowed per GUI
package class MainFrame : SimpleContainer {
    //where the last mouse-event did go to - used for the mousecursor
    //if !!captureMouse, then it should be the same like this (maybe)
    Widget mouseWidget;
    //Widget which currently unconditionally gets all mouse input events because
    //a mouse button was pressed down (releasing all mouse buttons undoes it)
    Widget captureMouse;
    //same for key-events; this makes sure the Widget receiving the key-down
    //event also receive the according key-up event
    //Widget captureKey; xxx not important?
    //user-requested mouse/keyboard capture, which works the same as above
    Widget captureUser;

    private {
        MouseCursor mMouseCursor = MouseCursor.Standard;
        Styles style_root;
    }

    this() {
        //first parent, this is used to provide default values for all
        //properties; the actual GUI styling should be somewhere else
        style_root = new Styles();
        style_root.addRules(gConf.loadConfig("gui_style_root")
            .getSubNode("root"));
        styles.parent = style_root;

        //load the theme (it's the theme because this is the top-most widget)
        //styles.addRules(gConf.loadConfig("gui_theme").getSubNode("styles"));

        doMouseEnterLeave(true); //mous always in, initial event
        pollFocusState();

        gOnChangeLocale ~= &onLocaleChange;
    }

    override bool isTopLevel() {
        return true;
    }

    override void onFocusChange() {
        assert(focused());
    }

    package void setSize(Vector2i size) {
        layoutContainerAllocate(Rect2i(Vector2i(0), size));
    }

    package void putInput(InputEvent event) {
        doDispatchInputEvent(event);
        if (captureMouse && !anyMouseButtonPressed()) {
            captureMouse = null;
            log()("capture release");
            //generate an artifical mouse move event to deal with the mouse
            //enter/leave-events, the mouse cursor etc.
            //sadly, the generated mouse move events are often redundant hrmm
            InputEvent ie;
            ie.isMouseEvent = true;
            ie.mousePos = gFramework.mousePos();
            ie.mouseEvent.pos = ie.mousePos;
            ie.mouseEvent.rel = Vector2i(0); //what would be the right thing?
            doDispatchInputEvent(ie);
        }
    }

    override void nextFocus(bool invertDir = false) {
        //no tab focus change on global level
    }

    void doFrame() {
        internalSimulate();

        void checkW(ref Widget w) {
            if (w && !w.isLinked())
                w = null;
        }

        checkW(mouseWidget);
        checkW(captureMouse);
        checkW(captureUser);

        mMouseCursor = mouseWidget ? mouseWidget.mouseCursor()
            : MouseCursor.Standard;
    }

    override MouseCursor mouseCursor() {
        return mMouseCursor;
    }
}

//main gui class, manages gui elements and forwards events
//(should be) singleton
class GuiMain {
    private MainFrame mMainFrame;

    private Vector2i mSize;

    SimpleContainer mainFrame() {
        return mMainFrame;
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
        mMainFrame.doFrame();
        gFramework.mouseCursor = mMainFrame.mouseCursor;
    }

    void draw(Canvas canvas) {
        mMainFrame.doDraw(canvas);
    }

    void putInput(InputEvent event) {
        mMainFrame.putInput(event);
    }
}
