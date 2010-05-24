module game.lua.physics;

import game.lua.base;
import physics.all;
import utils.vector2;

static this() {
    gScripting.setClassPrefix!(PhysicWorld)("World");

    gScripting.methods!(PhysicWorld, "add", "objectsAt");
    /+
    gScripting.method!(PhysicWorld, "collideGeometryScript")("collideGeometry");
    gScripting.method!(PhysicWorld, "collideObjectWithGeometryScript")(
        "collideObjectWithGeometry");
    +/
    gScripting.method!(PhysicWorld, "shootRayScript")("shootRay");
    gScripting.method!(PhysicWorld, "thickLineScript")("thickLine");
    gScripting.method!(PhysicWorld, "thickRayScript")("thickRay");
    gScripting.method!(PhysicWorld, "freePointScript")("freePoint");

    gScripting.setClassPrefix!(PhysicObject)("Phys");
    gScripting.methods!(PhysicObject, "isGlued", "pos", "velocity",
        "setInitialVelocity", "addForce", "addImpulse", "onSurface",
        "setPos", "move", "forceLook", "resetLook", "lookey", "applyDamage",
        "setWalking", "isWalkingMode", "isWalking");
    gScripting.properties!(PhysicObject, "selfForce", "acceleration", "posp");
    gScripting.properties_ro!(PhysicObject, "surface_normal", "lifepower");
    gScripting.setClassPrefix!(PhysicBase)("Phys");
    gScripting.property_ro!(PhysicBase, "backlink");
    gScripting.property!(PhysicBase, "collision");
    gScripting.method!(PhysicBase, "kill");

    gScripting.ctor!(PhysicZoneCircle, PhysicObject, float)();
    gScripting.ctor!(ZoneTrigger, PhysicZone)();
    gScripting.properties!(PhysicTrigger, "inverse", "onTrigger");
    gScripting.property!(ZoneTrigger, "zone");

    gScripting.ctor!(GravityCenter, PhysicObject, float, float)();

    gScripting.ctor!(HomingForce, PhysicObject, float, float)();
    gScripting.properties!(HomingForce, "mover", "forceA", "forceT",
        "targetPos", "targetObj");

    gScripting.method!(CollisionMap, "find");

    gScripting.ctor!(PhysicObjectsRod, PhysicObject, PhysicObject)();
    gScripting.ctor!(PhysicObjectsRod, PhysicObject, Vector2f)("ctor2");
    gScripting.properties!(PhysicObjectsRod, "length", "springConstant",
        "dampingCoeff")();

    //oh my
    //NOTE: we could handle classes just like structs and use tupleof on them
    //  (you have to instantiate the object; no problem in POSP's case)
    gScripting.properties!(POSP, "elasticity", "radius", "mass",
        "windInfluence", "explosionInfluence", "fixate", "damageUnfixate",
        "glueForce", "walkingSpeed", "walkingClimb", "walkLimitSlopeSpeed",
        "rotation", "gluedForceLook", "damageable", "damageThreshold",
        "sustainableImpulse", "fallDamageFactor", "fallDamageIgnoreX",
        "mediumViscosity", "stokesModifier", "airResistance", "friction",
        "bounceAbsorb", "slideAbsorb", "zeroGrav",
        "velocityConstraint", "speedLimit", "collisionID");
    gScripting.properties_ro!(POSP, "inverseMass");
    gScripting.methods!(POSP, "copy");
    gScripting.ctor!(POSP);
}
