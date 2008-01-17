module physics.plane;

import utils.vector2;

struct Plane {
    Vector2f mNormal = {1,0};
    float mDistance = 0; //distance of the plane from origin

    void define(Vector2f from, Vector2f to) {
        mNormal = (to - from).orthogonal.normal;
        mDistance = mNormal * from;
    }

    bool collide(inout Vector2f pos, float radius) {
        Vector2f out_pt = pos - mNormal * radius;
        float dist = mNormal * out_pt;
        if (dist >= mDistance)
            return false;
        float gap = mDistance - dist;
        pos += mNormal * gap;
        return true;
    }
}

