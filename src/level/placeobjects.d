module level.placeobjects;

import level.level;
import level.renderer;
import framework.framework;
import rand = std.random;
import utils.log;
debug import std.stdio;

/// Number of border where the object should be rooted into the landscape
/// Side.None means the object is placed within the landscape
public enum Side {
    North, West, South, East, None
}

public class PlaceableObject {
    //private ubyte[] mCollide;
    private Surface mTexture;
    private void* mPixelData; //RGBA32
    private uint mPDPitch;
    private Side mSide;
    private uint mWidth;
    private uint mHeight;
    private Vector2i mSize; //same as above
    private uint mDepth;
    private Vector2i mDir;

    void release() {
        //delete mCollide;
    }
}

public class PlaceObjects {
    private LevelRenderer mLevel;
    private Log mLog;

    //[0.0f, 1.0f]
    float random() {
        //xxx don't know RAND_MAX, this is numerically stupid anyway
        return cast(float)(rand.rand()) / typeof(rand.rand()).max;
    }

    //-1.0f..1.0f
    float random2() {
        return (random()-0.5f)*2.0f;
    }

    //[from, to)
    int random(int from, int to) {
        return rand.rand() % (to-from) + from;
    }

    //point inside level
    Vector2i randPoint() {
        return Vector2i(random(0, mLevel.mWidth), random(0, mLevel.mHeight));
    }

    public this(Log log, LevelRenderer renderer) {
        mLevel = renderer;
        mLog = log;
    }

    /// Load an object, that should be placed into the object
    /// depth is the amount of pixels, that should be hidden into the land
    /// note that depth is only "approximate"!
    public PlaceableObject createObject(Surface texture, Side side = Side.None,
        uint depth = 0)
    {
        PlaceableObject o = new PlaceableObject();
        //o.mCollide = texture.getSurface().convertToMask();
        o.mTexture = texture;
        o.mWidth = texture.size.x;
        o.mHeight = texture.size.y;
        o.mSize = texture.size;
        o.mSide = side;
        o.mDepth = depth;
        switch (side) {
            case Side.North: o.mDir = Vector2i(0,-1); break;
            case Side.South: o.mDir = Vector2i(0,1); break;
            case Side.East: o.mDir = Vector2i(1,0); break;
            case Side.West: o.mDir = Vector2i(1,0); break;
            default:
                o.mDir = Vector2i(0,0);
        }
        bool res = texture.convertToData(
            getFramework.findPixelFormat(DisplayFormat.RGBA32),
            o.mPDPitch, o.mPixelData);
        assert(res);
        return o;
    }

    public bool tryPlaceBridge(Vector2i start, Vector2i segsize,
        out Vector2i bridge_start, out Vector2i bridge_end)
    {
        //bridge_start = start;
        //bridge_end = start;
        //return true;
        uint fits = 0;

        bool canPlace(Vector2i pos) {
            Vector2i tmp_dir;
            uint tmp_collisions;
            return checkCollide(pos, segsize);
        }

        void doTryPlace(Vector2i dir, out Vector2i endpos) {
            Vector2i pos = start;
            endpos = start;

            for (;;) {
                pos += dir.mulEntries(segsize);
                if (!canPlace(pos)) {
                    return;
                }
                fits++;
                endpos = pos;
            }
        }

        if (!canPlace(start))
            return false;

        //first check the left direction, then the right :)
        doTryPlace(Vector2i(1, 0), bridge_end);
        doTryPlace(Vector2i(-1, 0), bridge_start);
        bridge_end.x1 += segsize.x;
        //bridge_start.x1 -= segsize.x;
        //2 is a deliberately chosen value
        return (fits >= 2);
    }

    //try to put bridges at any position (which is stupid...)
    public uint placeBridges(uint retry, uint maxbridges,
        PlaceableObject[3] bridge)
    {
        uint bridges = 0;
        for (int n = 0; n < retry; n++) {
            if (bridges >= maxbridges)
                break;

            Vector2i pos, st, en;
            pos = randPoint();

            mLog("bridge at %s? %s", pos, bridge[1].mSize/3);

            if (tryPlaceBridge(pos, bridge[0].mSize, st, en)) {
                //only accept if end parts of bridge is inside earth
                if (!checkCollide(st-bridge[1].mSize.X+bridge[1].mSize.Y/3*2,bridge[1].mSize/3,true))
                    continue;
                if (!checkCollide(en+bridge[2].mSize/3*2,bridge[2].mSize/3,true))
                    continue;
                mLog("yay bridge!");
                bridges++;
                uint count = (en.x1-st.x1)/bridge[0].mSize.x;
                for (int i = 0; i < count; i++) {
                    placeObject(bridge[0], st+i*bridge[0].mSize.X);
                }
                placeObject(bridge[1], st-bridge[1].mSize.X);
                placeObject(bridge[2], en);
            }
        }
        return bridges;
    }

    /*bool checkCollide(PlaceableObject obj, Vector2i at, out Vector2i dir,
        out uint collisions)
    {
        Vector2i sp = at;// - Vector2i(obj.mWidth, obj.mHeight) / 2;
        for (int y = sp.y; y < sp.y+cast(int)obj.mHeight; y++) {
            for (int x = sp.x; x < sp.x+cast(int)obj.mWidth; x++) {
                bool col = true;
                if (x >= 0 && x < mLevel.mWidth && y >= 0 && y < mLevel.mHeight) {
                    col = (obj.mCollide[(y-sp.y)*obj.mWidth+(x-sp.x)] != 0)
                        && (mLevel.mLevelData[y*mLevel.mWidth+x] != Lexel.FREE);
                }
                if (col) {
                    collisions++;
                    dir = dir + Vector2i(x, y) - at;
                }
            }
        }

        return (collisions == 0);
    }*/
    bool checkCollide(Vector2i at, Vector2i size, bool anti = false, bool outside_collides = true)
    {
        Vector2i sp = at;// - size / 2;
        for (int y = sp.y; y < sp.y+size.y; y++) {
            for (int x = sp.x; x < sp.x+size.x; x++) {
                bool col = outside_collides;
                if (x >= 0 && x < mLevel.mWidth && y >= 0 && y < mLevel.mHeight) {
                    col = (mLevel.mLevelData[y*mLevel.mWidth+x] != Lexel.FREE) ^ anti;
                }
                if (col) {
                    return false;
                }
            }
        }

        return true;
    }

    //render object _under_ the level and adjust level mask
    public void placeObject(PlaceableObject obj, Vector2i at) {
        auto pos = at;//at - Vector2i(obj.mWidth, obj.mHeight) / 2;
        mLevel.drawBitmap(pos.x, pos.y, obj.mPixelData, obj.mPDPitch,
            obj.mWidth, obj.mHeight, Lexel.FREE, Lexel.LAND);
    }

}
