module game.levelgen.placeobjects;

import game.levelgen.landscape;
import game.levelgen.level : writeMarker, parseMarker;
import game.levelgen.renderer;
import framework.drawing;
import framework.surface;
import utils.random : rngShared;
import utils.log;
import utils.configfile;
import utils.misc;

//how an object is placed
struct PlaceCommand {
    Vector2i at, size;
    Lexel before;
    Lexel after;

    void saveTo(ConfigNode node) {
        node.setValue("at", at);
        node.setValue("size", size);
        node["before"] = writeMarker(before);
        node["after"] = writeMarker(after);
    }

    void loadFrom(ConfigNode node) {
        at = node.getValue!(Vector2i)("at");
        size = node.getValue!(Vector2i)("size");
        before = parseMarker(node["before"]);
        after = parseMarker(node["after"]);
    }
}

void renderPlacedObject(LandscapeBitmap renderer, Surface img,
    in PlaceCommand cmd)
{
    renderer.drawBitmap(cmd.at, img, cmd.size, 255, cmd.before, cmd.after);
}

//store object positions
class LandscapeObjects {
    PlaceItem[] items;

    struct PlaceItem {
        string id;
        PlaceCommand params;
    }

    void place(string id, PlaceCommand p) {
        PlaceItem n;
        n.id = id;
        n.params = p;
        items ~= n;
    }

    void saveTo(ConfigNode node) {
        node.clear();
        foreach (item; items) {
            auto obj = node.add();
            obj.setStringValue("id", item.id);
            item.params.saveTo(obj);
        }
    }

    void loadFrom(ConfigNode node) {
        items = [];
        foreach (ConfigNode obj; node) {
            PlaceItem item;
            item.id = obj.getStringValue("id");
            item.params.loadFrom(obj);
            items ~= item;
        }
    }
}

/// Number of border where the object should be rooted into the landscape
/// Side.None means the object is placed within the landscape
public enum Side {
    North, West, South, East, None
}

public class PlaceableObject {
    //readonly (xxx make private, add accessors)
    string id;
    Surface bitmap;
    bool tryPlace;
    Side side;

    private Vector2i mDir;
    //private

    Vector2i size() {
        return bitmap.size;
    }

    package this(string aid, Surface abitmap, bool tryplace) {
        id = aid;
        bitmap = abitmap;
        tryPlace = tryplace;

        side = Side.South;
        switch (side) {
            case Side.North: mDir = Vector2i(0,-1); break;
            case Side.South: mDir = Vector2i(0,1); break;
            case Side.East: mDir = Vector2i(1,0); break;
            case Side.West: mDir = Vector2i(1,0); break;
            default:
                mDir = Vector2i(0,1);
        }
    }
}

public class PlaceObjects {
    private LandscapeBitmap mLevel;
    private Log mLog;
    //journal of added objects
    private LandscapeObjects mObjects;

    //point inside level
    Vector2i randPoint(int border = 0) {
        return Vector2i(rngShared.next(border, mLevel.size.x - border*2),
            rngShared.next(border, mLevel.size.y - border*2));
    }

    public this(LandscapeBitmap renderer) {
        mLevel = renderer;
        mLog = registerLog("placeobjects");
        mObjects = new LandscapeObjects();
    }

    LandscapeObjects objects() {
        return mObjects;
    }

    public bool tryPlaceBridge(Vector2i start, Vector2i segsize,
        out Vector2i bridge_start, out Vector2i bridge_end)
    {
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

            mLog("bridge at %s? %s", pos, bridge[1].size/3);

            //bridge segment size now can be less than the size of the bitmap,
            // but disabled it because it looks worse (?)
            if (tryPlaceBridge(pos, bridge[0].size, st, en)) {
                //only accept if end parts of bridge is inside earth
                if (!checkCollide(st-bridge[1].size.X+bridge[1].size.Y/3*2,bridge[1].size/3,true))
                    continue;
                if (!checkCollide(en+bridge[2].size/3*2,bridge[2].size/3,true))
                    continue;
                mLog("yay bridge!");
                bridges++;
                uint count = (en.x1-st.x1)/bridge[0].size.x;
                for (int i = 0; i < count; i++) {
                    placeObject(bridge[0], st+i*bridge[0].size.X);
                }
                //possibly partial last part...
                uint trail = (en.x1-st.x1+bridge[0].size.x) % bridge[0].size.x;
                placeObject(bridge[0], st+count*bridge[0].size.X,
                    Vector2i(trail, bridge[0].size.y));
                placeObject(bridge[1], st-bridge[1].size.X);
                placeObject(bridge[2], en);
            }
        }
        return bridges;
    }

    //tries to place an object using the try-and-error (TM) algorithm
    //NOTE about how Hedgewars 0.9.0 does it: it has a list of rectangles per
    //  object which must be inside or outside (only 1 rectangle for inside)
    //  it walks over the whole level in a grid-like way (y with fixed distance,
    //  x with random increments), and enters all possible positions into a list
    //  after that, it randomly selects some entries from that list and adds
    //  the object to the level at this position
    //  the collision testing is done by checking only the 4 lines that make up
    //  a rectangle, which always works correctly if objects are smaller than
    //  connected pieces of visible pieces (no "isles" which could be contained
    //  completely within an object)
    //  also, placing objects on top of others is avoided by explicit checks
    //did I miss anything?
    //my opinion:
    //  - how collision testing is done: good, steal it!
    //    probably even partitionate level objects into collision-rects
    //  - that list-of-possible-positions thing: potentially avoids checking
    //    positions twice, also less random numbers need to be generated, but
    //    I'm not really convinced?
    public uint placeObjects(uint retry, uint maxobjs, PlaceableObject obj) {
        uint count = 0;
        Vector2i line = Vector2i(obj.size.x/6*4, 2);
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
            auto pos = Vector2i(cpos.x + line.x/2 - obj.size.x/2,
                cpos.y-(obj.size.y-line.y));

            mLog("try object at %s", pos);

            if (checkCollide(pos, obj.size - Vector2i(0, dist))) {
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
        Lexel[] d = mLevel.peekLexels();
        for (int y = sp.y; y < sp.y+size.y; y++) {
            for (int x = sp.x; x < sp.x+size.x; x++) {
                bool col = outside_collides;
                if (x >= 0 && x < mLevel.size.x && y >= 0 && y < mLevel.size.y) {
                    col = (d[y*mLevel.size.x+x] != Lexel.Null) ^ anti;
                }
                if (col) {
                    return false;
                }
            }
        }

        return true;
    }

    const Vector2i cBla = {-1, -1};
    //render object _under_ the level and adjust level mask
    public void placeObject(PlaceableObject obj, Vector2i at,
        Vector2i size = cBla)
    {
        auto pos = at;//at - Vector2i(obj.mWidth, obj.mHeight) / 2;
        if (size.x < 0)
            size.x = obj.size.x;
        if (size.y < 0)
            size.y = obj.size.y;
        PlaceCommand cmd;
        cmd.at = at;
        cmd.size = size;
        cmd.before = Lexel.Null;
        cmd.after = Lexel.SolidSoft;

        mObjects.place(obj.id, cmd);
        renderPlacedObject(mLevel, obj.bitmap, cmd);
    }

}
