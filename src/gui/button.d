module gui.button;
import framework.event;
import gui.guiobject;
import gui.label;

class GuiButton : GuiLabel {
    void delegate() onClick;

    this() {
        super();
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT && bounds.isInside(mousePos)) {
            if (onClick) {
                onClick();
            }
            return true;
        }
        return false;
    }
}
