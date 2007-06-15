module gui.console;

import framework.console;
import framework.framework;
import game.common;
import gui.guiobject;

class GuiConsole : GuiObject {
    Console console;

    this() {
        console = new Console(globals.framework.getFont("console"));
        Color console_color;
        if (parseColor(globals.anyConfig.getSubNode("console")
            .getStringValue("backcolor"), console_color))
        {
            console.backcolor = console_color;
        }
        events.onKeyPress = &keyPress;
    }

    void draw(Canvas canvas) {
        if (console)
            console.frame(canvas);
    }

    bool keyPress(char[] bind, KeyInfo key) {
        if (console.visible && globals.cmdLine.keyPress(key))
            return true;
    }
}
