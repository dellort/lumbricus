module gui.button;
import framework.event;
import framework.framework;
import gui.widget;
import gui.label;

//xxx this is a hack
class Button : Label {
    private {
        bool mMouseOver;
    }

    void delegate(Button sender) onClick;
    void delegate(Button sender) onRightClick;
    void delegate(Button sender, bool over) onMouseOver;

    override void onDraw(Canvas c) {
        super.onDraw(c);
        //*g*
        if (mMouseOver) {
            c.drawFilledRect(Vector2i(0), size, Color(1,1,1,0.3));
        }
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        super.onMouseEnterLeave(mouseIsInside);
        mMouseOver = mouseIsInside;
        if (onMouseOver) {
            onMouseOver(this, mouseIsInside);
        }
    }

    override protected bool onKeyEvent(KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT /*&& bounds.isInside(mousePos)*/) {
            //NOTE: even though you react only on key-up events, catch down-
            // and press-events as well, else other Widgets might receive this
            // events, leading to stupid confusion
            if (key.isUp && onClick) {
                onClick(this);
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
}
