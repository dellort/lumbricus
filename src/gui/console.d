module gui.console;

import framework.commandline;
import framework.console;
import framework.framework;
import common.common;
import gui.widget;

class GuiConsole : Widget {
    private {
        Console mConsole;
        int mHeight_div;
        CommandLine mCmdline;
    }

    final Console console() {
        return mConsole;
    }
    final CommandLine cmdline() {
        return mCmdline;
    }

    override bool canHaveFocus() {
        return console.visible;
    }
    override bool greedyFocus() {
        return true;
    }

    //standalone: if false: hack to keep "old" behaviour of the system console
    this(bool standalone = true) {
        mHeight_div = standalone ? 1 : 2;
        mConsole = new Console(globals.framework.getFont(
            standalone ? "sconsole" : "console"));
        mConsole.visible = standalone; //system console hidden by default
        Color console_color;
        if (!standalone && parseColor(globals.anyConfig.getSubNode("console")
            .getStringValue("backcolor"), console_color))
        {
            console.backcolor = console_color;
            console.drawBackground = true;
        }
        mCmdline = new CommandLine(mConsole);
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
        console.height = size.y/mHeight_div;
    }

    override protected bool onKeyEvent(KeyInfo key) {
        if (key.isPress && console.visible && cmdline.keyPress(key))
            return true;
        return false;
    }
}
