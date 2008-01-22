module physics.posp;

import conv = std.conv;
import str = std.string;
import utils.configfile : ConfigNode;
import utils.vector2;

//PhysicalObjectStaticProperties
//challenge: find a better name
//contains all values which are considered not-changing physical properties of
//an object, i.e. they won't be changed by the simulation loop at all
//code to load from ConfigFile at the end of this file
struct POSP {
    float elasticity = 0.99f; //loss of energy when bumping against a surface
    float radius = 10; //pixels
    float mass = 10; //in Milli-Worms, 10 Milli-Worms = 1 Worm

    //percent of wind influence
    float windInfluence = 0.0f;
    //explosion influence
    float explosionInfluence = 1.0f;

    //fixate vector: how much an object can be moved in x/y directions
    //i.e. frozen worms will have fixate.x == 0
    //immobile objects will have fixate.length == 0
    //maybe should be 1 or 0, else funny things might happen
    Vector2f fixate = {1.0f,1.0f};

    //xxx maybe redefine to minimum velocity required to start simulaion again
    float glueForce = 0; //force required to move a glued worm away

    float walkingSpeed = 10; //pixels per seconds, or so
    float walkingClimb = 10; //pixels of height per 1-pixel which worm can climb

    //influence through damage (0 = invincible, 1 = normal)
    float damageable = 0.0f;
    float damageThreshold = 1.0f;

    //amount of force to take before taking fall damage
    float sustainableForce = 150;
    //force multiplier
    float fallDamageFactor = 0.1f;

    float mediumViscosity = 0.0f;

    //maximum absolute value, velocity is cut if over this
    Vector2f velocityConstraint = {float.infinity, float.infinity};
    float speedLimit = 0.0f;

    private char[] mCollisionID;
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

    //xxx sorry, but this avoids another circular reference
    void loadFromConfig(ConfigNode node)
    {
        elasticity = node.getFloatValue("elasticity", elasticity);
        radius = node.getFloatValue("radius", radius);
        mass = node.getFloatValue("mass", mass);
        windInfluence = node.getFloatValue("wind_influence",
            windInfluence);
        explosionInfluence = node.getFloatValue("explosion_influence",
            explosionInfluence);
        fixate = readVector(node.getStringValue("fixate", str.format("%s %s",
            fixate.x, fixate.y)));
        glueForce = node.getFloatValue("glue_force", glueForce);
        walkingSpeed = node.getFloatValue("walking_speed", walkingSpeed);
        walkingClimb = node.getFloatValue("walking_climb", walkingClimb);
        damageable = node.getFloatValue("damageable", damageable);
        damageThreshold = node.getFloatValue("damage_threshold",
            damageThreshold);
        mediumViscosity = node.getFloatValue("medium_viscosity",
            mediumViscosity);
        sustainableForce = node.getFloatValue("sustainable_force",
            sustainableForce);
        fallDamageFactor = node.getFloatValue("fall_damage_factor",
            fallDamageFactor);
        velocityConstraint = readVector(node.getStringValue(
            "velocity_constraint", str.format("%s %s", velocityConstraint.x,
            velocityConstraint.y)));
        speedLimit = node.getFloatValue("speed_limit", speedLimit);
        //xxx: passes true for the second parameter, which means the ID
        //     is created if it doesn't exist; this is for forward
        //     referencing... it should be replaced by collision classes
        collisionID = node.getStringValue("collide");
    }
}

//xxx duplicated from generator.d
private Vector2f readVector(char[] s) {
    char[][] items = str.split(s);
    if (items.length != 2) {
        throw new Exception("invalid point value");
    }
    Vector2f pt;
    pt.x = conv.toFloat(items[0]);
    pt.y = conv.toFloat(items[1]);
    return pt;
}