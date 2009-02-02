module physics.plane;

import tango.math.Math: sqrt;
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
