module gui.camframe;

/+
enum CameraStyle {
    Dead,     //not applicable
    Inactive, //disable camera temporarely
    Normal,   //camera follows in a non-confusing way
    Center,   //follows always centered, cf. super sheep
}

///The CameraFrame can manage several CameraObjects, which want to control the
///camera in any way; the CameraFrame picks one.
interface CameraObject {
    ///CameraStyle while this object is focused
    ///returns CameraStyle.Dead if this CameraObject should be removed
    CameraStyle getStyle();
    Vector2i getPosition();
}

///A special key event can activate scrolling with the mouse
class CameraFrame : MouseScroller {
    //...
}
+/


/+ Old code from scene.d
    private CameraStyle mCameraStyle;
    private SceneObjectPositioned mCameraFollowObject;
    private bool mCameraFollowLock;
    //last time the scene was scrolled by i.e. the mouse
    private long mLastUserScroll;

    //if the scene was scrolled by the mouse, scroll back to the camera focus
    //after this time
    private const cScrollIdleTimeMs = 1000;
    //in pixels the width of the border in which a follower camera becomes
    //active and scrolls towards the followed object again
    private const cCameraBorder = 150;

    private void scrollUpdate(Time curTime) {
        long curTimeMs = curTime.msecs;

        if ((mScrollDest-mScrollOffset).quad_length > 0.1f) {
            while (mTimeLast + cScrollStepMs < curTimeMs) {
                mScrollOffset +=
                    (mScrollDest - mScrollOffset)*K_SCROLL*cScrollStepMs;
                mTimeLast += cScrollStepMs;
            }
            clientoffset = toVector2i(mScrollOffset);
        } else {
            mTimeLast = timeCurrentTime().msecs;
        }

        //check for camera
        if (mCameraFollowObject && mCameraFollowObject.active &&
            (curTimeMs - mLastUserScroll > cScrollIdleTimeMs || mCameraFollowLock)) {
            auto pos = mCameraFollowObject.pos + mCameraFollowObject.size/2;
            pos = fromClientCoordsScroll(pos);
            switch (mCameraStyle) {
                case CameraStyle.Normal:
                    auto border = Vector2i(cCameraBorder);
                    Rect2i clip = Rect2i(border, size - border);
                    if (!clip.isInsideB(pos)) {
                        auto npos = clip.clip(pos);
                        scrollDoMove(pos-npos);
                    }
                    break;
                case CameraStyle.Center:
                    auto posCenter = size/2;
                    scrollDoMove(pos-posCenter);
                    break;
                case CameraStyle.Reset:
                    //nop
                    break;
            }
        }
    }

    ///One-time center the camera on obj
    public void scrollCenterOn(SceneObjectPositioned obj,
        bool instantly = false)
    {
        scrollCenterOn(obj.pos, instantly);
    }

    ///Set the active object the camera should follow
    ///Params:
    ///  lock = set to true to prevent user scrolling
    ///  resetIdleTime = set to true to start the cam movement immediately
    ///                  without waiting for user idle
    public void setCameraFocus(SceneObjectPositioned obj, CameraStyle cs
         = CameraStyle.Normal, bool lock = false, bool resetIdleTime = false)
    {
        if (!obj)
            cs = CameraStyle.Reset;
        mCameraFollowObject = obj;
        mCameraStyle = cs;
        mCameraFollowLock = lock;
        if (resetIdleTime)
            mLastUserScroll = 0;
    }

    ///call this when the user moves the mouse to scroll by delta
    ///idle time will be reset
    public void scrollMove(Vector2i delta) {
        mLastUserScroll = timeCurrentTime().msecs;
        scrollDoMove(delta);
    }
+/
