module physics.broadphase;

public import physics.physobj;

alias void delegate(PhysicObject obj1, PhysicObject obj2, float deltaT)
    CollideFineDg;

///Base class for broadphase collision detector
abstract class BroadPhase {
    CollideFineDg collideFine;

    this(CollideFineDg col) {
        collideFine = col;
    }

    abstract void collide(ref PhysicObject[] shapes, float deltaT);
}

///O(n^2), iterates over all objects
class BPIterate : BroadPhase {
    this(CollideFineDg col) {
        super(col);
    }

    void collide(ref PhysicObject[] shapes, float deltaT) {
        for (int i = 0; i < shapes.length; i++) {
            for (int j = i+1; j < shapes.length; j++) {
                collideFine(shapes[i], shapes[j], deltaT);
            }
        }
    }
}
