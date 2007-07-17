module gui.fps;

import framework.font;
import framework.framework;
import common.common;
import common.scene;
import common.visual;
import gui.widget;
import std.string;
import utils.time;

class GuiFps : GuiObjectOwnerDrawn {
    private Font mFont;

    protected override void draw(Canvas c) {
        auto text = format("FPS: %1.2f", globals.framework.FPS);
        auto pos = (size - mFont.textSize(text)).X;
        mFont.drawText(c, pos, text);
    }

    this() {
        mFont = globals.framework.getFont("fpsfont");
    }

    override bool testMouse(Vector2i pos) {
        return false;
    }
}
