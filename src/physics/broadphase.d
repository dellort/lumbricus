module physics.broadphase;

public import physics.physobj;
import physics.collide;
import physics.collisionmap;
import physics.contact;
import physics.world;
import utils.misc;
import utils.rect2;

///Base class for broadphase collision detector
//xxx rename? (maybe "ObjectSpace"?)
abstract class BroadPhase {
    private {
        PhysicWorld mWorld;
    }

    //from outside: read only variable & contents, just for iteration
    PhysicObjectList list;

    this(PhysicWorld world) {
        mWorld = world;
        list = new typeof(list)();
    }

    //package access only (actually using package makes methods non-virtual)
    void add(PhysicObject o) {
        list.insert_tail(o);
    }
    void remove(PhysicObject o) {
        list.remove(o);
    }

    //call on potential collision
    final protected void checkObjectCollision(PhysicObject obj1,
        PhysicObject obj2, CollideDelegate contactHandler)
    {
        //no collision if unwanted
        //xxx only place where mWorld is needed
        ContactHandling ch = mWorld.canCollide(obj1, obj2);
        if (ch == ContactHandling.none)
            return;

        //sigh... special cases for glueing; without this, objects get always
        //  unglued and/or never get glued
        //xxx probably not needed anymore?
        //if ((obj1.isStatic || obj1.isGlued) && (obj2.isStatic || obj2.isGlued))
        //    return;

        Contact c;
        c.obj[0] = obj1;
        c.obj[1] = obj2;

        //actually collide
        if (!doCollide(obj1.shape_id, obj1.shape_ptr, obj2.shape_id,
            obj2.shape_ptr, c))
            return;

        //xxx special case, and it fucking sucks
        if (obj1.isStatic || obj2.isStatic) {
            if (obj1.isStatic) {
                //reorder
                swap(c.obj[0], c.obj[1]);
                swap(obj1, obj2);
            }
            c.geomPostprocess(ch);
            obj1.checkGroundAngle(c);
        }

        //add contact(s)
        if (ch != ContactHandling.noImpulse) {
            //normal, pushBack
            c.fromObjInit();
            contactHandler(c);
        } else {
            //lol, generate 2 contacts that behave like the objects hit a wall
            // (avoids special code in contact.d)
            if (obj1.velocity.length > float.epsilon || obj1.isWalking()) {
                Contact c1 = c;
                c1.obj[1] = null;
                c1.depth /= 2;
                c1.fromObjInit();
                contactHandler(c1);
            }
            if (obj2.velocity.length > float.epsilon || obj2.isWalking()) {
                Contact c2 = c;
                c2.obj[0] = c2.obj[1];
                c2.obj[1] = null;
                c2.depth /= 2;
                c2.normal = -c2.normal;
                c2.fromObjInit();
                contactHandler(c2);
            }
        }
    }

    //collide all objects with each other
    //the callee is allowed to permutate the shapes array
    //for each potential overlap, contactHandler is called
    abstract void collide(CollideDelegate contactHandler);

    //the shape_ params are as in PhysicObject
    void collideShape(uint shape_id, void* shape_ptr, CollisionType filter,
        CollideDelegate contactHandler)
    {
        //naive algorithm
        for (PhysicObject o = list.head; o; o = list.next(o)) {
            //xxx duplication of collision logic
            ContactHandling ch = mWorld.collide.canCollide(filter, o.collision);
            if (ch == ContactHandling.none)
                continue;

            Contact c;
            c.obj[0] = o;
            c.obj[1] = null;

            if (doCollide(o.shape_id, o.shape_ptr, shape_id, shape_ptr, c)) {
                assert(!!c.obj[0] && !c.obj[1]);
                contactHandler(c);
            }
        }
    }

    //templated frontend to collideShape()
    //T = Circle, Plane, etc. (see collide.d)
    //may be slightly slower, because it has to find the shape id
    void collideShapeT(T)(ref T shape, CollisionType filter,
        CollideDelegate contactHandler)
    {
        int shape_id = getShapeID!(T)();
        void* shape_ptr = &shape;
        collideShape(shape_id, shape_ptr, filter, contactHandler);
    }

    //collide with all objects from other list
    //used to collide static with non-static objects
    void collideWith(BroadPhase other, CollideDelegate contactHandler) {
        //naive algorithm
        foreach (o1; list) {
            foreach (o2; other.list) {
                if (o1.bb.intersects(o2.bb))
                    checkObjectCollision(o1, o2, contactHandler);
            }
        }
    }
}

///O(n^2), iterates over all objects
class BPIterate : BroadPhase {
    this(PhysicWorld a_world) {
        super(a_world);
    }

    override void collide(CollideDelegate contactHandler) {
        foreach (o1; list) {
            PhysicObject o2 = list.next(o1);
            while (o2) {
                if (o1.bb.intersects(o2.bb))
                    checkObjectCollision(o1, o2, contactHandler);
                o2 = list.next(o2);
            }
        }
    }
}
