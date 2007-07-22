module game.gui.camera;

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

    private CameraStyle mCameraStyle;
    private CameraObject mCameraFollowObject;
    private bool mCameraFollowLock;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cScrollIdleTimeMs = 1000;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    private const cCameraBorder = 150;

    public void doFrame() {
        if (!control)
            return;

        long curTimeMs = timeCurrentTime.msecs;
        long lastAction = control.lastMouseScroll().msecs;

        //check for camera
        if (mCameraFollowObject && mCameraFollowObject.isCameraAlive &&
            (curTimeMs - lastAction > cScrollIdleTimeMs || mCameraFollowLock))
        {
            auto pos = mCameraFollowObject.getCameraPosition;
            pos = control.fromClientCoordsScroll(pos);
            switch (mCameraStyle) {
                case CameraStyle.Normal:
                    auto border = Vector2i(cCameraBorder);
                    Rect2i clip = Rect2i(border, control.size - border);
                    if (!clip.isInsideB(pos)) {
                        auto npos = clip.clip(pos);
                        control.scrollDeltaSmooth(pos-npos);
                        //xxx: needed or not? both behaves stupid
                        //control.noticeAction();
                    }
                    break;
                case CameraStyle.Center:
                    auto posCenter = control.size/2;
                    control.scrollDeltaSmooth(pos-posCenter);
                    control.noticeAction();
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
         = CameraStyle.Normal, bool lock = false)
    {
        if (!obj)
            cs = CameraStyle.Dead;
        mCameraFollowObject = obj;
        mCameraStyle = cs;
        mCameraFollowLock = lock;
    }
}
