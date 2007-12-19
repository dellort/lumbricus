module framework.restypes.frames;

import framework.drawing;
import framework.framework;
import framework.resources;
import utils.configfile;
import utils.rect2;
import utils.vector2;

//holds multiple frame sequences referenced by id
//should do most loading work on creation
//xxx intentionally no "reverse" method because its no more than
//    setting frameIdx to frameCount-frameIdx-1
abstract class FrameProvider {
    //draw frame frameIdx of animation animId to canvas, pos is the center
    //(additional position information provided by frames file)
    void draw(Canvas c, int animId, int frameIdx, Vector2i pos,
        bool mirrored = false);

    //xxx should this be seen as a request to "prepare" the animation animId?
    //    (e.g. for on-demand loading/boxpacking of big anim repositories)
    int frameCount(int animId);

    //xxx not my idea, whoever needs this...
    Rect2i bounds(int animId);
}

//supports one animation whose frames are aligned horizontally on one bitmap
//animId will be ignored
//xxx currently, no optimized mirroring support, as this would need
//     - FW support for mirrored drawing
//     - method to query FW if acceleration is available
//     - (already possible) registering a cache releaser with FW, think
//       of switching from GL to SDL driver mid-game, which would suddenly
//       require a cached mirror surface
//    or put surface mirroring support into FW
class FrameProviderStrip : FrameProvider {
    private {
        Surface mSurface;
        int mFrameCount;
        Vector2i mFrameSize, mCenterOffset;
        Rect2i mBounds;
    }

    //frameWidth is the x size (in pixels) of one animation frame,
    //and needs to be a factor of the total image width
    //if frameWidth == -1, frames will be square (height x height)
    this(char[] filename, int frameWidth) {
        mSurface = gFramework.loadImage(filename);
        if (frameWidth < 0)
            frameWidth = mSurface.size.y;
        mFrameSize = Vector2i(frameWidth, mSurface.size.y);
        mFrameCount = mSurface.size.x / mFrameSize.y;
        mCenterOffset = -mFrameSize / 2;
        mBounds = Rect2i(mCenterOffset, mCenterOffset+mFrameSize);
    }

    override void draw(Canvas c, int animId, int frameIdx, Vector2i pos,
        bool mirrored = false)
    {
        //no wrap-around
        assert(frameIdx < mFrameCount);
        c.draw(mSurface, pos+mCenterOffset,
            Vector2i(mFrameSize.x*frameIdx, 0), mFrameSize, mirrored);
    }

    override int frameCount(int animId) {
        return mFrameCount;
    }

    override Rect2i bounds(int animId) {
        return mBounds;
    }
}

//resource for animation frames
//will load the anim file on get()
//config item   type = "xxx"   chooses FrameProvider implementation
class FramesResource : ResourceBase!(FrameProvider) {
    this(Resources parent, char[] id, ConfigItem item) {
        super(parent, id, item);
    }

    protected void load() {
        ConfigNode node = cast(ConfigNode)mConfig;
        assert(node !is null);
        char[] type = node.getStringValue("type", "strip");
        switch (type) {
            case "strip":
                char[] fn = node.getPathValue("file");
                int frameWidth = node.getIntValue("frame_width", -1);
                mContents = new FrameProviderStrip(fn, frameWidth);
                break;
            default:
                assert(false, "Invalid frame resource type");
        }
    }

    override protected void doUnload() {
        mContents = null; //let the GC do the work
        super.doUnload();
    }

    static this() {
        ResFactory.register!(typeof(this))("frames");
        setResourceNamespace!(typeof(this))("frames");
    }
}
