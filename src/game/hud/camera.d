module game.hud.camera;

import framework.timesource;
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

///The CameraFrame can manage several CameraObjects, which want to control the
///camera in any way; the CameraFrame picks one.
interface CameraObject {
    Vector2i getCameraPosition();
    ///returns true if this CameraObject should be removed (polled each frame)
    bool isCameraAlive();
}

///Does camera-movement
///xxx maybe should be extended so that several active camera targets are
///supported at a time
///xxx also it's a bit annoying to use MouseScroller
class Camera {
    MouseScroller control;
    bool enable = true;

    private CameraStyle mCameraStyle;
    private CameraObject mCameraFollowObject;
    private bool mCameraFollowLock;
    private TimeSource mTime;
    private Time mLastScrollOur, mLastScrollExtern;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cScrollIdleTimeMs = 3000;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    private const cCameraBorder = 150;

    public void paused(bool set) {
        mTime.paused = set;
    }

    this() {
        mTime = new TimeSource();
    }

    void reset() {
        if (control)
            control.noticeAction();
    }

    public void doFrame() {
        if (!control)
            return;

        mTime.update();

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
        if (mCameraFollowObject && mCameraFollowObject.isCameraAlive &&
            (curTimeMs - lastAction >= cScrollIdleTimeMs || mCameraFollowLock)
            && enable)
        {
            auto pos = mCameraFollowObject.getCameraPosition;
            auto visible = control.visibleArea(control.scrollDestination);
            switch (mCameraStyle) {
                case CameraStyle.Normal:
                    auto border = Vector2i(cCameraBorder);
                    visible.extendBorder(-border);
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
}