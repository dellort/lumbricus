//maybe rename to physics.shapes
module physics.plane;

import std.math;
import utils.rect2;
import utils.vector2;
import utils.misc;

struct Plane {
    Vector2f mNormal = {1,0};
    float mDistance = 0; //distance of the plane from origin

    //for a line that actually has a start and an end, use Line, not Plane
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

    bool intersectLine(Vector2f start, Vector2f dir, out Vector2f p) {
        //put the equation for the line into the equation for the plane
        // p = start + dir*x;  with x=0...1
        // mNormal * p = mDistance
        //mNormal*(start + dir*x) = mDistance;
        //mNormal*start + (mNormal*dir)*x = mDistance;
        auto div = mNormal*dir;
        if (abs(div) < float.epsilon)
            return false;
        auto x = (mDistance - mNormal*start) / div;
        if (x >= 0f && x <= 1f) {
            p = start + dir*x;
            return true;
        }
        return false;
    }

    bool intersectRect(Rect2f rc, Vector2f[2] p_out) {
        uint c = 0;
        Vector2f[4] p;
        for (uint i = 0; i < 4; i++) {
            Vector2f p1 = rc.edge(i);
            Vector2f p2 = rc.edge(i+1);
            Vector2f op;
            if (intersectLine(p1, p2 - p1, op)) {
                p[c++] = op;
            }
        }
        if (c < 2)
            return false;
        //lame attempt at not trying to pick a "double" intersection point
        //  (very similar coordinates, but from different line segment)
        //fortunately doesn't get executed if there are 2 points (common case)
        Vector2f second = p[1];
        for (uint i = 2; i < c; i++) {
            if ((p[i] - p[0]).quad_length > (second - p[0]).quad_length)
                second = p[i];
        }
        p_out[0] = p[0];
        p_out[1] = second;
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
        radius += width;
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
