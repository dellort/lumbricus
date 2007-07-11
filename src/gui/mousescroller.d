module gui.mousescroller;

/// The child for MouseScroller can implement this; then scrolling will can be
/// enabled.
interface ScrollClient {
    //Get the maximal scroll value
    Vector2f getScrollSize();
    //Set the scroll position (i.e. actually scroll)
    //guaranteed to be between 0..getScrollSize for each component
    void setScrollPositions(Vector2f pos);
}

/// This frame always sizes its child to its requested size, and enables
/// scrolling within it.
//(this is what the SceneObjectViewer was)
class MouseScroller : Container {
    ...
}
