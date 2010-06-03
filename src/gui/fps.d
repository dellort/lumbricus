module gui.fps;

import framework.font;
import framework.framework;
import framework.globalsettings;
import gui.widget;
import utils.time;
import utils.misc;

private {
    SettingVar!(bool) gShowFPS, gShowDeltas;
}

static this() {
    gShowFPS = gShowFPS.Add("fps.show", false);
    gShowDeltas = gShowDeltas.Add("fps.show_deltas", false);
}

class GuiFps : Widget {
    private Font mFont;
    private Vector2i mPos;
    private float mFps;
    private char[] mText; //will point to mBuffer
    private char[60] mBuffer, mBuffer2, mBuffer3; //avoid heap allocations
    private bool oldDelta; //change text if setting changes

    protected override void onDraw(Canvas c) {
        if (!gShowFPS.get())
            return;
        bool deltas = gShowDeltas.get();

        calcDeltas();

        if (gFramework.FPS != mFps || deltas != oldDelta) {
            mFps = gFramework.FPS;
            if (deltas) {
                mText = myformat_s(mBuffer, "FPS: {:f2} Min: {} Max: {}", mFps,
                    tmin_s.toString_s(mBuffer2), tmax_s.toString_s(mBuffer3));
            } else {
                mText = myformat_s(mBuffer, "FPS: {:f2}", mFps);
            }
            mPos = (size - mFont.textSize(mText)).X;
        }

        mFont.drawText(c, mPos, mText);
        oldDelta = deltas;
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
