module gui.button;
import framework.event;
import framework.framework;
import gui.widget;
import gui.label;

//xxx this is a hack
//if an image is set, also disable all GuiLabel rendering completely
class GuiButton : GuiLabel {
    private {
        Texture mImage;
        bool mMouseOver;
    }

    void delegate(GuiButton sender) onClick;
    void delegate(GuiButton sender) onRightClick;
    void delegate(GuiButton sender, bool over) onMouseOver;

    void image(Texture img) {
        mImage = img;
        needRelayout();
    }

    override Vector2i layoutSizeRequest() {
        return mImage ? mImage.size : super.layoutSizeRequest();
    }

    override void draw(Canvas c) {
        if (mImage) {
            c.draw(mImage, Vector2i());
        } else {
            super.draw(c);
        }
        //*g*
        if (mMouseOver) {
            c.drawFilledRect(Vector2i(0), size, Color(1,1,1,0.3));
        }
    }

    override protected bool onMouseMove(MouseInfo mouse) {
        //lol... but else, mouse-leave won't work (see container.d/internal...)
        return true;
    }

    override protected void onMouseEnterLeave(bool mouseIsInside) {
        mMouseOver = mouseIsInside;
        if (onMouseOver) {
            onMouseOver(this, mouseIsInside);
        }
    }

    override protected bool onKeyUp(char[] bind, KeyInfo key) {
        if (key.code == Keycode.MOUSE_LEFT /*&& bounds.isInside(mousePos)*/) {
            if (onClick) {
                onClick(this);
            }
            return true;
        }
        if (key.code == Keycode.MOUSE_RIGHT) {
            if (onRightClick) {
                onRightClick(this);
            }
            return true;
        }
        return super.onKeyUp(bind, key);
    }
}
