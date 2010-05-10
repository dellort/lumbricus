//maybe rename to physics.shapes
module physics.plane;

import tango.math.Math: sqrt;
import utils.rect2;
import utils.vector2;
import utils.misc;

struct Plane {
    Vector2f mNormal = {1,0};
    float mDistance = 0; //distance of the plane from origin

    void define(Vector2f from, Vector2f to) {
        mNormal = (to - from).orthogonal.normal;
        mDistance = mNormal * from;
    }

    bool collide(Vector2f pos, float radius, out Vector2f normal,
        out float depth)
    {
        float dist = pos * mNormal - radius - mDistance;
        if (dist >= 0)
            return false;
        normal = mNormal;
        depth = -dist;
        return true;
    }
}

struct Ray {
    Vector2f start, dir;

    void define(Vector2f start, Vector2f dir) {
        this.start = start;
        this.dir = dir.normal;
    }

    //damn, I thought this would be simpler...
    //xxx there's also Vector2.distance_from_clipped(), doesn't it do the same?
    //  then the worse implementation should be replaced by the better one
    //  - see struct Line below
    bool intersect(Vector2f pos, float radius, out float t) {
        Vector2f diff = start-pos;
        float b = 2*diff*dir;
        float c = diff*diff - radius*radius;

        float disc = b*b - 4*c;
        if (disc < 0)
            return false;

        float q;
        if (b < 0)
            q = (-b - sqrt(disc))/2.0f;
        else
            q = (-b + sqrt(disc))/2.0f;

        float t0 = q;
        float t1 = c/q;

        if (t0 > t1)
            swap(t0, t1);

        if (t1 < 0)
            return false;
        if (t0 < 0) {
            t = t1;
            return true;
        } else {
            t = t0;
            return true;
        }
    }
}

//only collides on the line between start and end point
//the caps are rounded
struct Line {
    //dir not normalized (defines end point)
    Vector2f start, dir;
    float width = 0;

    void defineStartEnd(Vector2f start, Vector2f end, float width) {
        this.start = start;
        this.dir = end - start;
        this.width = width;
    }

    bool collide(Vector2f pos, float radius, out Vector2f normal,
        out float depth)
    {
        radius += width/2;
        //prj is the point on the line
        auto prj = pos.project_on_clipped(start, dir);
        auto to_obj = pos - prj;
        auto qlen = to_obj.quad_length;
        if (qlen >= radius*radius)
            return false;
        auto len = sqrt(qlen);
        //stuck, same hack as in glevel.d
        if (len != len || len < float.epsilon) {
            depth = float.infinity;
            return true;
        }
        normal = to_obj/len;
        depth = radius - len;
        return true;
    }

    Rect2f calcBB() {
        auto bb = Rect2f.Abnormal();
        bb.extend(start);
        bb.extend(start + dir);
        bb.extendBorder(Vector2f(width));
        return bb;
    }
}

struct Circle {
    Vector2f pos;
    float radius;
}
