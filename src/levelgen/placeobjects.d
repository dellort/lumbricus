module levelgen.placeobjects;

import levelgen.level;
import levelgen.renderer;
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
    private Surface mTexture;
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
    private LevelBitmap mLevel;
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
        return Vector2i(random(0, mLevel.size.x), random(0, mLevel.size.y));
    }

    public this(Log log, LevelBitmap renderer) {
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

            //bridge segment size now can be less than the size of the bitmap,
            // but disabled it because it looks worse (?)
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
                //possibly partial last part...
                uint trail = (en.x1-st.x1+bridge[0].mSize.x) % bridge[0].mSize.x;
                placeObject(bridge[0], st+count*bridge[0].mSize.X, trail, bridge[0].mSize.y);
                placeObject(bridge[1], st-bridge[1].mSize.X);
                placeObject(bridge[2], en);
            }
        }
        return bridges;
    }

    //tries to place an object using the try-and-error algorithm
    public uint placeObjects(uint retry, uint maxobjs, PlaceableObject obj) {
        uint count = 0;
        Vector2i line = Vector2i(obj.mWidth/6*4, 2);
        outer: for (int n = 0; n < retry; n++) {
            if (count >= maxobjs)
                break;

            //try to find good place position
            auto cpos = randPoint();

            while (!checkCollide(cpos, line, true)) {
                cpos.y += 2;
                if (cpos.y >= mLevel.size.y)
                    continue outer;
            }

            //check if can be placed
            auto dist = 20;
            auto pos = Vector2i(cpos.x + line.x/2 - obj.mWidth/2,
                cpos.y-(obj.mHeight-line.y));

            mLog("try object at %s", pos);

            if (checkCollide(pos, obj.mSize - Vector2i(0, dist))) {
                //yeeha
                mLog("place object at %s", pos);
                placeObject(obj, pos);
                count++;
            }
        }
        return count;
    }

    bool checkCollide(Vector2i at, Vector2i size, bool anti = false,
        bool outside_collides = true)
    {
        Vector2i sp = at;
        for (int y = sp.y; y < sp.y+size.y; y++) {
            for (int x = sp.x; x < sp.x+size.x; x++) {
                bool col = outside_collides;
                if (x >= 0 && x < mLevel.size.x && y >= 0 && y < mLevel.size.y) {
                    col = (mLevel.levelData[y*mLevel.size.x+x]
                        != Lexel.Null) ^ anti;
                }
                if (col) {
                    return false;
                }
            }
        }

        return true;
    }

    //render object _under_ the level and adjust level mask
    public void placeObject(PlaceableObject obj, Vector2i at,
        int w = -1, int h = -1)
    {
        auto pos = at;//at - Vector2i(obj.mWidth, obj.mHeight) / 2;
        if (w < 0)
            w = obj.mWidth;
        if (h < 0)
            h = obj.mHeight;
        mLevel.drawBitmap(pos, obj.mTexture, Vector2i(w, h),
            Lexel.Null, Lexel.SolidSoft);
    }

}
