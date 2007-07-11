module gui.camframe;

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
    ...
}
