module physics.broadphase;

public import physics.physobj;
import physics.contact;

alias void delegate(PhysicObject obj1, PhysicObject obj2,
    CollideDelegate contactHandler) CollideFineDg;

///Base class for broadphase collision detector
abstract class BroadPhase {
    CollideFineDg collideFine;

    this(CollideFineDg col) {
        collideFine = col;
    }

    abstract void collide(ref PhysicObject[] shapes,
        CollideDelegate contactHandler);
}

///O(n^2), iterates over all objects
class BPIterate : BroadPhase {
    this(CollideFineDg col) {
        super(col);
    }

    void collide(ref PhysicObject[] shapes, CollideDelegate contactHandler) {
        for (int i = 0; i < shapes.length; i++) {
            for (int j = i+1; j < shapes.length; j++) {
                collideFine(shapes[i], shapes[j], contactHandler);
            }
        }
    }
}
