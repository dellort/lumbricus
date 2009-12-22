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
    private char[60] mBuffer;
    bool showDeltas;

    protected override void onDraw(Canvas c) {
        calcDeltas();
        if (gFramework.FPS != mFps) {
            mFps = gFramework.FPS;
            if (showDeltas) {
                mText = myformat_s(mBuffer, "FPS: {:f2} Min: {} Max: {}", mFps,
                    tmin_s, tmax_s);
            } else {
                mText = myformat_s(mBuffer, "FPS: {:f2}", mFps);
            }
            mPos = (size - mFont.textSize(mText)).X;
        }
        mFont.drawText(c, mPos, mText);
    }

    private Time tlast, tshow, tmin = timeSecs(999), tmax, tmin_s, tmax_s;
    void calcDeltas() {
        Time now = timeCurrentTime();
        Time delta = now - tlast;
        if (delta != Time.Null) {
            tmin = min(delta, tmin); tmax = max(delta, tmax);
        }
        tlast = now;
        if (now - tshow > timeSecs(5)) {
            tmin_s = tmin; tmax_s = tmax;
            tshow = now;
            tmin = timeSecs(999); tmax = Time.Null;
        }
    }

    this() {
        focusable = false;
        isClickable = false;
        mFont = gFontManager.loadFont("fpsfont");
    }
}
