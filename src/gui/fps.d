module gui.fps;

import framework.font;
import framework.framework;
import common.scene;
import common.visual;
import gui.widget;
import std.string;
import utils.time;

class GuiFps : Widget {
    private Font mFont;

    protected override void onDraw(Canvas c) {
        auto text = format("FPS: %1.2f", gFramework.FPS);
        auto pos = (size - mFont.textSize(text)).X;
        mFont.drawText(c, pos, text);
    }

    this() {
        mFont = gFramework.getFont("fpsfont");
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override bool testMouse(Vector2i pos) {
        return false;
    }
}
