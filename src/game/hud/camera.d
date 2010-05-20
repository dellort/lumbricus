module game.hud.camera;

import utils.timesource;
import gui.mousescroller;
import utils.rect2;
import utils.time;
import utils.vector2;

enum CameraStyle {
    Dead,     //not applicable
    Inactive, //disable camera temporarely
    Normal,   //camera follows in a non-confusing way
    Center,   //follows always centered, cf. super sheep
}

///Does camera-movement
///xxx maybe should be extended so that several active camera targets are
///supported at a time
///xxx also it's a bit annoying to use MouseScroller
class Camera {
    MouseScroller control;
    bool enable = true;

    private CameraStyle mCameraStyle;
    private Vector2i mCameraFollowPos;
    private bool mCameraFollowAlive;
    private bool mCameraFollowLock;
    private TimeSource mTime;
    private Time mLastScrollOur, mLastScrollExtern;
    private Vector2i mAutoScroll;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cScrollIdleTimeMs = 2500;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    const Vector2i cCameraBorder = {150, 150};
    private Vector2i mCameraBorder = cCameraBorder;

    this(TimeSourcePublic ts) {
        mTime = new TimeSource("camera", ts);
    }

    TimeSourcePublic ts() {
        return mTime;
    }

    void reset() {
        if (control)
            control.noticeAction();
    }

    void setAutoScroll(Vector2i dir) {
        mAutoScroll = dir;
    }

    public void doFrame() {
        if (!control)
            return;

        mTime.update();

        if (mAutoScroll.x || mAutoScroll.y) {
            control.noticeAction();
            const float speed = 3000f; //pixels/sec
            control.scrollDeltaSmooth(toVector2f(mAutoScroll) * speed
                * mTime.difference.secsf);
        }

        auto ctime = control.lastMouseScroll();

        if (ctime != mLastScrollExtern) {
            //we also could try to provide a function to translate times between
            //timesources... (possible?)
            mLastScrollOur = mTime.current();
            mLastScrollExtern = ctime;
        }

        long curTimeMs = mTime.current().msecs;
        long lastAction = mLastScrollOur.msecs;

        //check for camera
        //there's the following issue/non-issue: if an object moves, the camera
        //should follow it - but that only works if you didn't move the camera
        //for during the last idle time
        if (mCameraFollowAlive &&
            (curTimeMs - lastAction >= cScrollIdleTimeMs || mCameraFollowLock)
            && enable)
        {
            auto pos = mCameraFollowPos;
            auto visible = visibleArea();
            switch (mCameraStyle) {
                case CameraStyle.Normal:
                    visible.extendBorder(-mCameraBorder);
                    if (!visible.isInsideB(pos)) {
                        auto npos = visible.clip(pos);
                        control.scrollDeltaSmooth(pos-npos);
                    }
                    break;
                case CameraStyle.Center:
                    control.scrollDeltaSmooth(pos - visible.center());
                    break;
                default:
                    //dead or so
            }
        }
    }

    Rect2i visibleArea() {
        if (!control)
            return Rect2i.init;
        return control.visibleArea(control.scrollDestination);
    }

/+
    ///Set the active object the camera should follow
    ///Params:
    ///  lock = set to true to prevent user scrolling
    ///  resetIdleTime = set to true to start the cam movement immediately
    ///                  without waiting for user idle
    public void setCameraFocus(CameraObject obj, CameraStyle cs
         = CameraStyle.Normal, bool lock = false, bool resetIdleTime = true)
    {
        if (!obj)
            cs = CameraStyle.Dead;
        mCameraFollowObject = obj;
        mCameraStyle = cs;
        mCameraFollowLock = lock;
        if (resetIdleTime) {
            //evil, blatant hack
            //with this, the time datatype must support negative times
            mLastScrollOur = mTime.current() - timeMsecs(cScrollIdleTimeMs);
        }
    }
+/

    void updateCameraTarget(Vector2i pos, Vector2i camBorder = Vector2i(0)) {
        if (!mCameraFollowAlive) {
            //like in setCameraFocus
            mCameraStyle = CameraStyle.Normal;
            mLastScrollOur = mTime.current() - timeMsecs(cScrollIdleTimeMs);
            mCameraFollowAlive = true;
        }
        mCameraFollowPos = pos;
        if (camBorder.x > 0 && camBorder.y > 0)
            mCameraBorder = camBorder;
        else
            mCameraBorder = cCameraBorder;
    }

    void noFollow() {
        mCameraFollowAlive = false;
        mCameraStyle = CameraStyle.Dead;
    }
}
