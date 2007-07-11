module gui.button;
import framework.event;
import gui.widget;
import gui.label;

class GuiButton : GuiLabel {
    void delegate(GuiButton sender) onClick;

    this() {
        super();
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT /*&& bounds.isInside(mousePos)*/) {
            if (onClick) {
                onClick(this);
            }
            return true;
        }
        return false;
    }
}
