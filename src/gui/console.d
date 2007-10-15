module gui.console;

import framework.console;
import framework.framework;
import common.common;
import gui.widget;

class GuiConsole : Widget {
    Console console;

    override bool canHaveFocus() {
        return console.visible;
    }
    override bool greedyFocus() {
        return true;
    }

    this() {
        console = new Console(globals.framework.getFont("console"));
        Color console_color;
        if (parseColor(globals.anyConfig.getSubNode("console")
            .getStringValue("backcolor"), console_color))
        {
            console.backcolor = console_color;
        }
    }

    override bool testMouse(Vector2i pos) {
        return false;
    }

    //xxx: maybe should register a callback on Console instead of requiring this
    void toggle() {
        console.toggle();
        recheckFocus();
    }

    void onDraw(Canvas canvas) {
        console.frame(canvas);
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override protected void layoutSizeAllocation() {
        console.height = size.y/2;
    }

    override protected bool onKeyEvent(KeyInfo key) {
        if (key.isPress && console.visible && globals.cmdLine.keyPress(key))
            return true;
        return false;
    }
}
