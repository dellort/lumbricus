module physics.collide;

import physics.contact;
import physics.plane;
import utils.misc;
import utils.rect2;
import utils.vector2;

import std.math;

//this may be handy:
//  http://www.realtimerendering.com/intersections.html

//collision functions for use with the physics engine
//this simulates multimethods (dispatching on 2 object types, instead of 1 like
//  in normal OOP languages like D)
//they use the function signature for dispatchers CollideFn, and can just call
//  the actual collision functions
//s1 and s2 both point to the shape data (what the shape data is is collision
//  function specific, and will be mostly a pointer to a struct)
//ct.obj is initialized with the colliding objects, regrouped such that obj[0]
//  refers to s1 and obj[1] to s2; but any item in ct.obj can be null as well
//  (this is needed for "independend" queries like PhysicWorld.objectsAt, and
//  the reason why s1 and s2 are still needed)
//all other fields of ct are uninitialized
//fields other than ct.normal and ct.depth shouldn't be written (not sure, may
//  want to change that if needed)
alias bool function(void* s1, void* s2, ref Contact c) CollideFn;

bool collide_circle2circle(void* s1, void* s2, ref Contact ct) {
    auto c1 = cast(Circle*)s1;
    auto c2 = cast(Circle*)s2;

    Vector2f d = c1.pos - c2.pos;
    float dist = sqrt(d.quad_length);
    float mindist = c1.radius + c2.radius;

    //check if they collide at all
    if (dist >= mindist)
        return false;

    if (dist <= 0) {
        //objects are exactly at the same pos, move aside anyway
        dist = mindist/2;
        d = Vector2f(0, dist);
    }

    ct.depth = mindist - dist;
    ct.normal = d/dist;

    return true;
}

bool collide_circle2plane(void* s1, void* s2, ref Contact ct) {
    auto c = cast(Circle*)s1;
    auto p = cast(Plane*)s2;
    return p.collide(c.pos, c.radius, ct.normal, ct.depth);
}

bool collide_circle2line(void* s1, void* s2, ref Contact ct) {
    auto c = cast(Circle*)s1;
    auto l = cast(Line*)s2;
    return l.collide(c.pos, c.radius, ct.normal, ct.depth);
}

uint Circle_ID, Plane_ID, Line_ID;

//xxx static this
void init_collide() {
    Circle_ID = getShapeID!(Circle)();
    Plane_ID = getShapeID!(Plane)();
    Line_ID = getShapeID!(Line)();
    collidefn!(Circle, Circle)(&collide_circle2circle);
    collidefn!(Circle, Plane)(&collide_circle2plane);
    collidefn!(Circle, Line)(&collide_circle2line);
}

//return whether shapes collided
//contact.obj should be filled with objects to collide (xxx: never needed?)
//contact may contain garbage if false is returned
bool doCollide(uint shape1_id, void* shape1_ptr, uint shape2_id,
    void* shape2_ptr, ref Contact contact)
{
    bool swapped = false;
    CollideFn fn = *getCollideFnPtr(shape1_id, shape2_id);

    if (!fn) {
        //try other way around; the matrix isn't symmetric
        fn = *getCollideFnPtr(shape2_id, shape1_id);
        //if no collision function, can't do anything and let it pass
        if (!fn)
            return false;
        //fn expects its arguments in correct order
        swap(contact.obj[0], contact.obj[1]);
        swap(shape1_ptr, shape2_ptr);
        swapped = true;
    }

    //actually collide
    if (!fn(shape1_ptr, shape2_ptr, contact))
        return false;

    //swap back, sigh (to get original order in contact.obj)
    if (swapped)
        swap(contact.obj[0], contact.obj[1]);

    return true;
}

//all this crap because one wants to add shape types from other independend
//  parts of the program (LandscapeGeometry)

private {
    TypeInfo[] mShapeIDs;
    struct CollideEntry {
        uint t1, t2;
        CollideFn fn;
    }
    CollideEntry[] mCollideFns;
    CollideFn[] mCollideFnMatrix;
}

CollideFn* getCollideFnPtr(uint t1, uint t2) {
    assert(t1 < mShapeIDs.length && t2 < mShapeIDs.length);
    return &mCollideFnMatrix[t1*mShapeIDs.length + t2];
}

private void rebuildCollide() {
    mCollideFnMatrix.length = mShapeIDs.length * mShapeIDs.length;
    mCollideFnMatrix[] = null;
    foreach (e; mCollideFns) {
        *getCollideFnPtr(e.t1, e.t2) = e.fn;
    }
}

//declare that types T1 and T2 can be collided with fn
//fn will be called like this:
//  T1 s1; T2 s2; Contact c; fn(&s1, &s2, c);
void collidefn(T1, T2)(CollideFn fn) {
    mCollideFns ~= CollideEntry(getShapeID!(T1)(), getShapeID!(T2)(), fn);
    rebuildCollide();
}

//find/create an unique low integer ID for the passed type
//also possibly resize the collision array to include it
//should be considered to be relatively slow (cache when using in inner loops)
uint getShapeID(T)() {
    TypeInfo t = typeid(T);
    foreach (size_t i, TypeInfo ti; mShapeIDs) {
        if (ti is t)
            return cast(uint)i;
    }
    mShapeIDs ~= t;
    rebuildCollide();
    return cast(uint)mShapeIDs.length - 1;
}


