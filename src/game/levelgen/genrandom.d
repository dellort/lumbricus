module game.levelgen.genrandom;

import game.levelgen.level : Lexel, parseMarker, writeMarker;
import utils.array : arrayMap;
import utils.vector2;
import utils.mylist;
import utils.math : lineIntersect;
import framework = framework.framework : Color;
import tango.math.Math : PI;
import utils.random : rngShared;
import utils.configfile : ConfigNode;
import utils.misc : myformat;
import str = stdx.string;
import utils.serialize : floatToHex; //right function from wrong module

//about textures: currently marker implies texture

/// unrenderer level, generated by LevelTemplate.genRandomLevelGeometry()
//maybe I also use this for the leveleditor hehe
public class LandscapeGeometry {
    struct Polygon {
        Vector2i[] points;
        uint[] nochange;
        Lexel marker;
        bool changeable = true;
        bool visible = true;
        //x/y offsets of fill-texture, in range 0-1
        Vector2f texoffset;
    }

    Polygon[] polygons;
    Vector2i size;
    Lexel fill;  //if Null, no cave; else cave fillings
    //GeneratorConfig config; //overcomplicated tuning params

    LandscapeGeometry clone() {
        LandscapeGeometry n = new LandscapeGeometry();
        n.polygons = polygons.dup;
        n.size = size;
        n.fill = fill;

        foreach (inout Polygon p; n.polygons) {
            p.points = p.points.dup;
            p.nochange = p.nochange.dup;
        }

        return n;
    }

    void loadFrom(ConfigNode node) {
        size = node.getValue("size", Vector2i(1200,700));

        char[] markerId = node.getStringValue("fill_marker", "free");
        fill = parseMarker(markerId);

        ConfigNode polys = node.getSubNode("polygons");
        polygons = null;
        foreach(char[] name, ConfigNode polygon; polys) {
            LandscapeGeometry.Polygon p;
            p.points = polygon.getValue!(Vector2i[])("points");

            p.nochange = polygon.getValue!(uint[])("nochange");
            p.marker = parseMarker(polygon.getStringValue("marker"));
            p.visible = polygon.getBoolValue("visible", true);
            p.changeable = polygon.getBoolValue("changeable", true);
            //xxx: read texoffset

            polygons ~= p;
        }
    }

    void saveTo(ConfigNode node) {
        node["size"] = myformat("{} {}", size.x, size.y);
        bool is_cave = fill != Lexel.Null;
        node.setBoolValue("is_cave", is_cave);
        if (is_cave) {
            node.setStringValue("fill_marker", writeMarker(fill));
        }

        ConfigNode polys = node.getSubNode("polygons");
        polys.clear();
        foreach (Polygon p; polygons) {
            ConfigNode sub = polys.add();
            sub.setValue("points", p.points);
            sub.setValue("nochange", p.nochange);
            sub.setBoolValue("visible", p.visible);
            sub.setBoolValue("changeable", p.changeable);
            //sub.setStringValue("texoffset", myformat("%a %s",
                //p.texoffset.x, p.texoffset.y));
            sub.setStringValue("texoffset", floatToHex(p.texoffset.x) ~ " " ~
                floatToHex(p.texoffset.y));
            sub.setStringValue("marker", writeMarker(p.marker));
        }
    }
}

//this is just bloat hehe
struct GeneratorConfig {
    float pix_epsilon = 2.0f; //in pixels, see probe_shapozoid
    float pix_filter = 5.0f; //Group.filter
    uint subdivision_steps = 6;
    float removal_aggresiveness = 1.0f;
    float min_subdiv_length = 5.0f; //refuse to subdivide below that
    float front_len_ratio_add = 0.2f;
    float len_ratio_add = 1.0f;
    float front_len_ratio_remove = 0.2f;
    float len_ratio_remove = 1.0f;
    float remove_or_add = 0.5f; //0: only remove, 1: only add

    void loadFrom(ConfigNode node) {
        //tedious, maybe should replaced by an associative array or so
        float tmp = node.getFloatValue("pix_epsilon");
        if (tmp == tmp) {
            pix_epsilon = tmp;
        }
        tmp = node.getFloatValue("pix_filter");
        if (tmp == tmp)
            pix_filter = tmp;
        int tmpint = node.getIntValue("subdivision_steps", -1);
        if (tmpint >= 0)
            subdivision_steps = tmpint;
        tmp = node.getFloatValue("removal_aggresiveness");
        if (tmp == tmp)
            removal_aggresiveness = tmp;
        tmp = node.getFloatValue("min_subdiv_length");
        if (tmp == tmp)
            min_subdiv_length = tmp;
        tmp = node.getFloatValue("front_len_ratio_add");
        if (tmp == tmp)
            front_len_ratio_add = tmp;
        tmp = node.getFloatValue("len_ratio_add");
        if (tmp == tmp)
            len_ratio_add = tmp;
        tmp = node.getFloatValue("front_len_ratio_remove");
        if (tmp == tmp)
            front_len_ratio_remove = tmp;
        tmp = node.getFloatValue("len_ratio_remove");
        if (tmp == tmp)
            len_ratio_remove = tmp;
        tmp = node.getFloatValue("remove_or_add");
        if (tmp == tmp)
            remove_or_add = tmp;
    }
}


//debugging: dump polygon outlines into the levle image
//version = dump_polygons;

alias Vector2f Point;

//line segment
private class Segment {
    //one of these points is redundant
    Point a, b;
    Group group;
    bool changeable = true; //if false, means _both_ points must not be changed
    mixin ListNodeMixin node;

    this(Group group, Point a, Point b) {
        this.group = group; this.a = a; this.b = b;
    }
}

private alias List!(Segment) SegmentList;

//range define by [start, last]
//a range is empty when start and last are null
//the list where start and last are contained is treated as ring list, so
//last might be unreachable by using next(), and ring_next() must be used
private struct SegmentRange {
    Segment start = null;
    Segment last = null;
    Group group = null;

    bool isEmpty() {
        return (start is null);
    }
    static SegmentRange opCall(Group g, Segment start, Segment last) {
        SegmentRange r;
        r.start = start; r.last = last; r.group = g;
        //either both are null, or both are non-null, mixing is not allowed
        assert((start is null) == (last is null));
        if (start !is null) {
            assert(g is start.group && g is last.group);
        }
        return r;
    }
    static SegmentRange opCall(Group g) {
        SegmentRange r;
        r.group = g;
        return r;
    }
    //return the intersection of all items in to_group to this range
    SegmentRange complement(Group to_group) {
        if (group !is to_group || isEmpty())
            return to_group.fullRange;
        auto b = to_group.segments.ring_prev(start);
        auto a = to_group.segments.ring_next(last);
        //does the range cover the whole list
        if (a is start)
            return SegmentRange(to_group);
        return SegmentRange(to_group, a, b);
    }

    bool changeable() {
        if (isEmpty() || !group.changeable)
            return false;
        for (auto cur = start; ; cur = group.segments.ring_next(cur)) {
            if (!(cur.changeable))
                return false;
            if (cur is last)
                return true;
        }
        //unreachable
    }
}

//a Group is a single polygon
private final class Group {
    SegmentList segments;
    mixin ListNodeMixin node;
    Lexel meaning;
    bool visible;
    bool changeable;
    float mTolerance = 1.0f;

    this() {
        Segment s; //indirection through s to work around to a compiler bug
        segments = new SegmentList(s.node.getListNodeOffset());
    }

    //see GenRandomLandscape.addPolygon()
    Segment init(Point[] pts, uint[] unchangeable, bool changeable) {
        segments.clear();

        bool isChangeable(uint index) {
            if (!changeable)
                return false;

            //the bad runtime complexity doesn't really matter, since level
            //templates usually are small
            for (uint i = 0; i < unchangeable.length; i++) {
                if (index == unchangeable[i])
                    return false;
            }
            return true;
        }

        this.changeable = changeable;

        if (pts.length < 3)
            return null;

        for (int n = 0; n < pts.length; n++) {
            Segment s = new Segment(this, pts[n], pts[(n+1) % $]);
            s.changeable = isChangeable(n);
            segments.insert_tail(s);
        }

        return segments.tail;
    }

    //whether a group needs to test intersection with another
    //i.e. needed when a Groups define non-landscape things
    bool needIntersect(Group other) {
        return true;
    }

    SegmentRange fullRange() {
        return SegmentRange(this, segments.head, segments.tail);
    }

    //filter out points, that could make later subdivision (by renderer.d) less
    //effective, and fortunately this also filters out other artifact-like fuzz
    void filter(float dist) {
        if (!segments.hasAtLeast(3))
                return;
        Segment cur = segments.head;
        do {
        cont:
            Segment next = segments.ring_next(cur);
            Point p = cur.a, np = next.a, onp = next.b;
            //check if np is near enough line between p and onp to kill it
            float d = np.distance_from(p, onp-p);
            if (d < dist && cur.changeable && next.changeable) {
                segments.remove(next);
                cur.b = onp;
                if (segments.isEmpty) //oops, shouldn't really happen
                    return;
                goto cont;
            } else {
                cur = next;
            }
        } while (cur !is segments.head);
    }

    //remove all Segments _within_ the given range, and insert new segments
    //according to points
    //the new outline created is as follows:
    //  start.a - points[0] - ... - points[$-1] - last.b
    //i.e. start.b is modified to be start[0]...
    void splicify(SegmentRange range, Point[] points) {
        if (range.isEmpty) {
            throw new Exception("can't insert into an empty range");
        }

        Segment start = range.start;
        Segment last = range.last;

        assert(range.changeable());
        assert(range.group is this);

        //remove segments after start and before last
        for (;;) {
            Segment cur = segments.ring_next(start);
            if (start is last || cur is last)
                break;
            //debug Trace.formatln("remove {} {}", cur.a.toString, cur.b.toString);
            segments.remove(cur);
        }

        if (points.length < 1)
            return;

        if (start is last) {
            Segment s = new Segment(this, last.a, last.b);
            segments.insert_before(s, start);
            start = s;
        }

        start.b = points[0];

        Segment cur = start;
        foreach(Point p; points[1..$]) {
            Segment s = new Segment(this, cur.b, p);
            segments.insert_after(s, cur);
            cur = s;
        }

        //trailing
        last.a = points[$-1];
    }

    //check if any of the polygon intersects with the given segment range
    //the given polygon is assumed to be closed (i.e. polygon[0]==polygon[$-1])
    bool checkCollide(Point[] polygon, SegmentRange check) {
        if (polygon.length < 1)
            return false;

        assert(check.group is this);

        if (check.isEmpty)
            return false;

        bool checkCollide(Segment s, Point a, Point b) {
            assert(s !is null && s.group is this);
            float tmp1, tmp2;
            return lineIntersect(s.a, s.b-s.a, a, b-a, tmp1, tmp2, mTolerance);
        }


        Point last = polygon[0];

        //xxx: unfortunate runtime complexity: O(|polygons|*|group polygons|)
        foreach(Point cur; polygon[1..$]) {
            bool current_nocheck = false;
            Segment segment = check.start;
            for (;;) {
                if (checkCollide(segment, last, cur))
                    return true;
                if (segment is check.last)
                    break;
                segment = segments.ring_next(segment);
            }
            last = cur;
        }
        return false;
    }
}

private alias List!(Group) GroupList;

//This creates a random level image; the goal was to have levels looking
//similar to the auto generated levels from Worms(tm).
//Actually, the image is drawn in renderer.d, this just creates the outline
//data...
//Note that the algorithm needs "template" shapes to work with, see xxx.
public class GenRandomLandscape {
private:
    GroupList mGroups;
    GeneratorConfig config;

    uint mWidth, mHeight;

    //completely unsophisticated again-and-again random wormsify
    //of course needs to be fixed
    void naiveRandomWormsify(Group group) {
        if (!group.segments.hasAtLeast(2))
            return;
        for (int i = 0; i < 3; i++) {
            Segment s = group.segments.head;
            assert(s !is null);
            while (s !is null) {
                float d = (s.b-s.a).length;
                auto r = SegmentRange(group, s, s);
                assert(!r.isEmpty);
                if (r.changeable()) {
                    doWormsify(r, 0.1f, 0.9f, rngShared.nextDouble3()*2*PI/2+0.4,
                        rngShared.nextDouble3()*0.5f+PI, d*0.2f, d*2.5f, 2.0f,
                        config.pix_epsilon);
                }
                s = group.segments.next(s);
            }
        }
    }

    //completely utterly pointless mindless fuzzifier
    void fuzzyRandomWormsify(Group group, uint depth) {
        if (!group.segments.hasAtLeast(2))
            return;
        //first, find longest edge and edge count
        Segment s = group.segments.head;
        float longest = 0;
        uint count = 0;
        while (s !is null) {
            float d = (s.b-s.a).length;
            longest = d > longest ? d : longest;
            count++;
            s = group.segments.next(s);
        }

        //random offset into the list (not so important, but try not to treat
        //the segments at the start and end of the list different)
        uint something = rngShared.next(0, count);
        Segment cur = group.segments.head;
        while (something > 0) {
            cur = group.segments.ring_next(cur);
            something--;
        }

        //step through each edge
        Segment start = cur;
        float summed_d = 0;
        uint cur_len = 0;
        uint iterations = 0;
        while (iterations < count) {
            Segment next = group.segments.ring_next(cur);
            float cur_d = (cur.b-cur.a).length;
            summed_d += cur_d;
            float prob = summed_d/longest;
            cur_len++;

            //I use some "heuristics" to create a nice-looking random level
            //but note that if doWormsify always produces good-looking
            //output, so the following code doesn't necessarly make _any_
            //sense!

            bool reset = false;
            auto range = SegmentRange(group, start, cur);
            bool dosubdiv = range.changeable();
            //the longer, the higher the probability to subdivide
            dosubdiv &= prob >= rngShared.nextDouble()*0.5f;
            //condition above could always be true, so fuzzify it a bit
            dosubdiv &= rngShared.nextDouble() > 0.2f;
            //don't be too aggressive with replacing ranges
            dosubdiv &= cur_len-1 <= config.removal_aggresiveness * depth;
            //also, respect pixel size
            dosubdiv &= summed_d >= config.min_subdiv_length;

            if (dosubdiv) {
                //muh

                float ratio_front_len, ratio_len, rotsign;
                if (config.remove_or_add > rngShared.nextDouble()) {
                    //add
                    rotsign = 1;
                    ratio_front_len = config.front_len_ratio_add;
                    ratio_len = config.len_ratio_add;
                } else {
                    //remove
                    rotsign = -1;
                    ratio_front_len = config.front_len_ratio_remove;
                    ratio_len = config.len_ratio_remove;
                }

                doWormsify(range, 0.1f, 0.9f,
                    rotsign*rngShared.nextDouble()*PI/2,
                    PI + rngShared.nextDouble3()*0.4f, cur_d*ratio_front_len,
                    cur_d*ratio_len, 2.0f, config.pix_epsilon);

                reset = true;
            }

            if (!cur.changeable)
                reset = true;
            reset |= (rngShared.nextDouble() > 0.3f);
            reset |= cur_len-1 > depth;

            if (reset) {
                start = next;
                summed_d = 0;
                cur_len = 0;
            }

            iterations++;
            cur = next;
        }
    }

    void wormsifyAll() {
        for (uint depth = 0; depth < config.subdivision_steps; depth++) {
            foreach(Group group; mGroups) {
                if (!group.changeable)
                    continue;
                //naiveRandomWormsify(group);
                fuzzyRandomWormsify(group, depth);
            }
        }

        //run filter separately to fix all the stupid things I did in wormsify
        foreach(Group group; mGroups) {
            if (!group.changeable)
                continue;
            group.filter(config.pix_filter);
        }
    }

    //the polygon defined by points never must to be closed, it will be closed
    //automatically by connecting the last and the first point; but if
    //line started by points which index is in the "unchangeable" array, will
    //never be changed (to disable all, changeable can be set to false and this
    //array can be left empty)
    //if texture" is null, paint it transparent
    //"marker" can be Lexel.INVALID to not paint anything into the final Level
    //formerly a "public" member
    private void addPolygon(Point[] points, uint[] unchangeable,
        /+TextureID texture,+/ Lexel marker, bool changeable = true,
        bool visible = true)
    {
        Group g = new Group();
        mGroups.insert_tail(g);
        g.init(points, unchangeable, changeable);
        g.meaning = marker;
        g.visible = visible;
    }

    private Point[] getRect(float margin) {
        Point[] pts = new Point[4];
        pts[0] = Point(margin, margin);
        pts[1] = Point(margin, mHeight-margin);
        pts[2] = Point(mWidth-margin, mHeight-margin);
        pts[3] = Point(mWidth-margin, margin);
        return pts;
    }

    //formerly a "public" member
    private void setAsCave(Lexel marker) {
        addPolygon(getRect(0), null, marker, false, true);
    }

    //formerly a "public" constructor, or so
    private void reinit(uint width, uint height) {
        mWidth = width; mHeight = height;
        mGroups = new GroupList(Group.node.getListNodeOffset());

        //init border
        addPolygon(getRect(10), null, Lexel.INVALID, false, false);
    }

    LandscapeGeometry mData;

    public this() {
    }

    //read data from LevelGeometry object (but actually doesn't, lol)
    public void readFrom(LandscapeGeometry data) {
        mData = data;
    }

    public void setConfig(GeneratorConfig aconfig) {
        config = aconfig;
    }

    //generate a new LandscapeGeometry instance from the set one
    //  data = contains init data, aka level template
    public LandscapeGeometry generate() {
        assert(mData !is null);

        //read
        reinit(mData.size.x, mData.size.y);
        if (mData.fill != Lexel.Null) {
            setAsCave(mData.fill);
        }
        foreach (LandscapeGeometry.Polygon p; mData.polygons) {
            addPolygon(arrayMap(p.points, (Vector2i p) {return toVector2f(p);}),
                p.nochange, p.marker, p.changeable, p.visible);
        }

        //generate
        wormsifyAll();

        auto newdata = new LandscapeGeometry;
        newdata.size = mData.size;
        newdata.fill = mData.fill;

        foreach(Group group; mGroups) {
            if (group.meaning == Lexel.INVALID)
                continue;
            newdata.polygons ~= render_points(group);
        }

        return newdata;
    }

    LandscapeGeometry.Polygon render_points(Group group) {
        //collect points...
        //(used to be Vector2f, now Vector2i)
        auto pts = new Vector2i[group.segments.count];
        uint[] nosubdiv;
        uint cur = 0;
        foreach(Segment s; group.segments) {
            pts[cur] = toVector2i(s.a);
            if (!s.changeable) {
                nosubdiv ~= cur;
            }
            cur++;
        }

        //randomize the texture offset, looks better sometimes
        auto texoffset = Vector2f(rngShared.nextDouble(),
            rngShared.nextDouble());

        LandscapeGeometry.Polygon res;
        res.points = pts;
        res.nochange = nosubdiv;
        res.marker = group.meaning;
        res.changeable = group.changeable;
        res.visible = group.visible;
        res.texoffset = texoffset;
        return res;
    }

    //intersect the polygon in points with all groups
    //the polygon array is assumed to be closed (cf. Group.checkCollide)
    bool globPolygonCollide(Point[] points, SegmentRange exclude) {
        foreach(Group group; mGroups) {
            if (!exclude.group.needIntersect(group))
                continue;
            SegmentRange check = exclude.complement(group);
            if (group.checkCollide(points, check))
                return true;
        }
        return false;
    }

    //shapozoid = polygon with points: (warning, mixed D and Python syntax)
    //    [b1] ~ [(b1+b2)/2+dir*x+p for p in shape_edge] ~ [b2]
    //where the function tries to maximize x to 1.0f without having collisions
    //tmp is used for temporary storage
    //the tmp array can hopefully be killed, but currently, D doesn't allow
    //variable arrays on the stack *sigh* (note: I converted this from C code)
    //tmp.length >= shape_edge.length+3
    float probe_shapozoid(Point b1, Point b2, Point dir, Point[] shape_edge,
        Point[] tmp, SegmentRange exclude)
    {
        assert(tmp.length >= shape_edge.length+3);
        tmp = tmp[0..shape_edge.length+3];

        float sdiv = 1.0f;
        float lenepsilon = config.pix_epsilon / dir.length();

        if (lenepsilon != lenepsilon || lenepsilon <= float.epsilon)
            return float.nan;

        Point base = b1 + (b2 - b1)*0.5f;

        tmp[0] = b1;
        tmp[$-2] = b2;
        tmp[$-1] = b1; //xxx this last line is not really necessary, is it?

        for (;;) {
            Point curbase = base + dir*sdiv;

            Point last = b1;
            for (uint i = 0; i < shape_edge.length; i++) {
                tmp[i+1] = shape_edge[i]+curbase;
            }

            if (globPolygonCollide(tmp, exclude)) {
                //intersection => search in lower half
                sdiv *= 0.75f;
                if (sdiv != sdiv || sdiv <= lenepsilon)
                    return float.nan;
            } else {
                //fine, finished (really??)
                return sdiv;
            }
        }

        //never reached
        return float.nan;
    }

    //wormsify a given line segment range; this means we make it look more like
    //a place where earthworms live
    //the segments within "at" might be destroyed, deleted or completely
    //changed, while the "outer" edge points of at.start and at.end will stay
    //unchanged
    //does not respect Segment.changeable
    //dir: rotation, i.e. -PI/2 points into the landscape and PI/2 outside
    //fdir: rotation of the front side of the shape (0=orthogonal to dir)
    //      xxx now it is relative to the base line
    //frontlen: length of the front side of the shape
    //minlen, maxlen: valid range for the shape's length
    //returns false if failed (shape's length out of range)
    //if not failed, at_start and at_end is set to the segment rang...
    bool doWormsify(inout SegmentRange at, float from_ratio, float to_ratio,
        float dir, float fdir, float frontlen, float maxlen, float minlen,
        float min_baselen)
    {
        Point[4] shape;
        Point[2+3] tmp; //nasty temporary for probe_shapozoid, see there

        if (at.isEmpty())
            return false;

        Point a = at.start.a;
        Point b = at.last.b;

        Point na = a + (b-a) * from_ratio;
        Point nb = a + (b-a) * to_ratio;
        Point base = nb-na;
        float baselen = base.length();

        if (baselen < min_baselen)
            return false;

        Point newdir = base.rotated(dir);
        newdir.length = maxlen;

        //Point newnorm = newdir.orthogonal.normal.rotated(fdir);
        Point newnorm = base.normal.rotated(fdir);
        shape[0] = na;
        shape[1] = newnorm*(frontlen*0.5f);
        shape[2] = newnorm*(-frontlen*0.5f);
        shape[3] = nb;

        float len = probe_shapozoid(na, nb, newdir, shape[1..3], tmp, at);
        if (len != len)
            return false;
        len *= 0.7f;//0.9f;//xxx

        newdir = newdir * len;
        Point start = na+(nb-na)*0.5f;
        shape[1] = shape[1] + start + newdir;
        shape[2] = shape[2] + start + newdir;

        at.group.splicify(at, shape);

        return true;
    }
}
