module physics.misc;

import tango.util.Convert;
import utils.configfile : ConfigNode;
import utils.vector2;
import utils.misc : myformat;
import utils.strparser;

//Important: No physics. references in this file!

//moved here because "is forward referenced"...
enum ContactSource {
    object,
    geometry,
    generator,
}

//and another one... renaming file from posp.d to misc.d
//entry in matrix that defines how a collision should be handled
//for other uses than contact generation (like triggers), any value >0
//  means it collides
enum ContactHandling : ubyte {
    none,       //no collision
    normal,     //default (physically correct) handling
    noImpulse,  //no impulses are exchanged (like both objects hit a wall)
                //this may be useful if you want an object to block,
                // but not be moved
    pushBack,   //push object back where it came from (special case for ropes)
}

enum DamageCause {
    death = -1,
    fall,
    explosion,
    special,
}

enum RotateMode {
    velocity,
    distance,
    selfforce,  //calc looking-angle as needed for worms with jetpacks
}

//PhysicalObjectStaticProperties
//challenge: find a better name
//contains all values which are considered not-changing physical properties of
//an object, i.e. they won't be changed by the simulation loop at all
//code to load from ConfigFile at the end of this file
final class POSP {
    float elasticity = 0.99f; //loss of energy when bumping against a surface
    float radius = 10; //pixels
    private float mMass = 10; //in Milli-Worms, 10 Milli-Worms = 1 Worm
    private float mMassInv = 0.1f; //lol, needed for collision processing
    //now make sure mMassInv stays valid
    float mass() {
        return mMass;
    }
    void mass(float m) {
        assert(m > 0, "Invalid mass value");
        mMass = m;
        mMassInv = 1.0f/m;
    }
    float inverseMass() {
        return mMassInv;
    }

    //percent of wind influence
    float windInfluence = 0.0f;
    //explosion influence
    float explosionInfluence = 1.0f;

    //fixate vector: how much an object can be moved in x/y directions
    //i.e. frozen worms will have fixate.x == 0
    //immobile objects will have fixate.length == 0
    //maybe should be 1 or 0, else funny things might happen
    Vector2f fixate = {1.0f,1.0f};
    //set fixate to {1.0f,1.0f} when damaged
    //note that this is one-way: can never get fixated again without
    //setting new posp
    bool damageUnfixate = false;

    //xxx maybe redefine to minimum velocity required to start simulaion again
    float glueForce = 0; //force required to move a glued worm away

    float walkingSpeed = 10; //pixels per seconds, or so
    float walkingClimb = 10; //pixels of height per 1-pixel which worm can climb
    bool walkLimitSlopeSpeed = false;

    RotateMode rotation;
    bool gluedForceLook = false;

    //influence through damage (0 = invincible, 1 = normal)
    float damageable = 0.0f;
    float damageThreshold = 1.0f;

    //amount of impulse to take before taking fall damage
    float sustainableImpulse = 150;
    //impulse multiplier
    float fallDamageFactor = 0.0f;
    //true to ignore horizontal movement for fall damage calculation
    bool fallDamageIgnoreX = false;

    float mediumViscosity = 0.0f;
    //modifier for drag force (think of object shape, 1.0 = full)
    float stokesModifier = 1.0f;

    float airResistance = 0.0f;

    float friction = 0.05f;
    float bounceAbsorb = 0.0f;
    float slideAbsorb = 0.0f;
    //extended normalcheck will test the surface normal in a bigger radius,
    //  without generating a contact in the extended area
    bool extendNormalcheck = false;
    bool zeroGrav = false;

    //maximum absolute value, velocity is cut if over this
    Vector2f velocityConstraint = {float.infinity, float.infinity};
    float speedLimit = float.infinity;

    private char[] mCollisionID = "none";
    char[] collisionID() {
        return mCollisionID;
    }
    void collisionID(char[] id) {
        mCollisionID = id;
        needUpdate = true;
    }

    //has any data changed that needs further processing by POSP owner?
    //(currently only collisionID)
    protected bool needUpdate = true;

    void loadFromConfig(ConfigNode node)
    {
        elasticity = node.getFloatValue("elasticity", elasticity);
        radius = node.getFloatValue("radius", radius);
        mass = node.getFloatValue("mass", mass);
        windInfluence = node.getFloatValue("wind_influence",
            windInfluence);
        explosionInfluence = node.getFloatValue("explosion_influence",
            explosionInfluence);
        fixate = node.getValue("fixate", fixate);
        damageUnfixate = node.getBoolValue("damage_unfixate", damageUnfixate);
        glueForce = node.getFloatValue("glue_force", glueForce);
        walkingSpeed = node.getFloatValue("walking_speed", walkingSpeed);
        walkingClimb = node.getFloatValue("walking_climb", walkingClimb);
        walkLimitSlopeSpeed = node.getBoolValue("walk_limit_slope_speed",
            walkLimitSlopeSpeed);
        damageable = node.getFloatValue("damageable", damageable);
        damageThreshold = node.getFloatValue("damage_threshold",
            damageThreshold);
        mediumViscosity = node.getFloatValue("medium_viscosity",
            mediumViscosity);
        stokesModifier = node.getFloatValue("stokes_modifier", stokesModifier);
        airResistance = node.getFloatValue("air_resistance", airResistance);
        sustainableImpulse = node.getFloatValue("sustainable_impulse",
            sustainableImpulse);
        fallDamageFactor = node.getFloatValue("fall_damage_factor",
            fallDamageFactor);
        fallDamageIgnoreX = node.getBoolValue("fall_damage_ignore_x",
            fallDamageIgnoreX);
        velocityConstraint = node.getValue("velocity_constraint",
            velocityConstraint);
        speedLimit = node.getFloatValue("speed_limit", speedLimit);
        char[] rot = node.getStringValue("rotation", "velocity");
        switch (rot) {
            case "velocity":
                rotation = RotateMode.velocity;
                break;
            case "distance":
                rotation = RotateMode.distance;
                break;
            case "selfforce":
                rotation = RotateMode.selfforce;
                break;
            default:
                assert(false);
        }
        gluedForceLook = node.getValue("glued_forcelook", gluedForceLook);
        friction = node.getFloatValue("friction", friction);
        slideAbsorb = node.getFloatValue("slide_absorb", slideAbsorb);
        bounceAbsorb = node.getFloatValue("bounce_absorb", bounceAbsorb);
        extendNormalcheck = node.getBoolValue("extend_normalcheck",
            extendNormalcheck);
        zeroGrav = node.getBoolValue("zero_gravity", zeroGrav);
        //xxx: passes true for the second parameter, which means the ID
        //     is created if it doesn't exist; this is for forward
        //     referencing... it should be replaced by collision classes
        collisionID = node.getStringValue("collide", collisionID);
    }

    typeof(this) copy() {
        auto other = new typeof(this)();
        foreach (int n, m; this.tupleof) {
            other.tupleof[n] = m;
        }
        return other;
    }

    this() {
    }
}

static this() {
    enumStrings!(RotateMode, "velocity,distance,selfforce");
}
