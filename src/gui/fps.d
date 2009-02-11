module gui.fps;

import framework.font;
import framework.framework;
import gui.widget;
import utils.time;
import utils.misc;

class GuiFps : Widget {
    private Font mFont;
    private Vector2i mPos;
    private float mFps;
    private char[] mText; //will point to mBuffer
    private char[40] mBuffer;

    protected override void onDraw(Canvas c) {
        if (gFramework.FPS != mFps) {
            mFps = gFramework.FPS;
            mText = myformat_s(mBuffer, "FPS: {:f2}", mFps);
            mPos = (size - mFont.textSize(mText)).X;
        }
        mFont.drawText(c, mPos, mText);
    }

    this() {
        mFont = gFramework.getFont("fpsfont");
    }

    override Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override bool onTestMouse(Vector2i pos) {
        return false;
    }
}
