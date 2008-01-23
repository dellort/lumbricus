module physics.plane;

import utils.vector2;

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

