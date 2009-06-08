//This module just exists to fight some stupid compiler errors
//with dmd+Tango
module game.weapon.types;

import utils.configfile;
import utils.time;
import utils.vector2;

enum WeaponWormAnimations {
    Arm,  //worm gets armed (or unarmed: animation played backwards)
    Hold, //worm holds the weapon
    Fire, //animation played while worm is shooting
}
//WeaponWormAnimations -> string
const char[][] cWWA2Str = ["arm", "hold", "fire"];

enum PointMode {
    none,
    target,
    instant,
    instantFree,    //like instant, but not inside objects/geometry
                    //(will be moved out by controller)
}

///directions the user is allowed to set (not necessarily real fire direction)
enum ThrowDirection {
    fixed,      //no user direction setting (you still have worm orientation)
    any,       //full 360 freedom
    threeway,  //sloping-up, straight, sloping-down (think of blowtorch)
    limit90,    //90deg freedom only (up/down limited)
}

struct FireMode {
    //needed by both client and server (server should verify with this data)
    ThrowDirection direction; //what directions the user can choose
    bool variableThrowStrength; //chooseable throw strength
    //if variableThrowStrength is true, FireInfo.strength is interpolated
    //between From and To by a player chosen value (that fire strength thing)
    float throwStrengthFrom = 1;
    float throwStrengthTo = 1;
    PointMode point = PointMode.none; //by mouse, i.e. target-searching weapon
    bool hasTimer; //user can select a timer
    Time timerFrom; //minimal time chooseable, only used if hasTimer==true
    Time timerTo;   //maximal time
    Time relaxtime;


    void loadFromConfig(ConfigNode node) {
        switch (node.getStringValue("direction", "fixed")) {
            case "any":
                direction = ThrowDirection.any;
                break;
            case "threeway":
                direction = ThrowDirection.threeway;
                break;
            case "limit90":
                direction = ThrowDirection.limit90;
                break;
            default:
                direction = ThrowDirection.fixed;
        }
        variableThrowStrength = node["strength_mode"] == "variable";
        if (node.hasValue("strength_value")) {
            //for "compatibility" only
            throwStrengthFrom = throwStrengthTo =
                node.getFloatValue("strength_value");
        } else {
            throwStrengthFrom = node.getFloatValue("strength_from",
                throwStrengthFrom);
            throwStrengthTo = node.getFloatValue("strength_to",
                throwStrengthTo);
        }
        hasTimer = node.getBoolValue("timer");
        if (hasTimer) {
            //if you need finer values than seconds, hack this
            //abusing Vector2f as "range" type xD
            Vector2f vals = node.getValue("timerrange", Vector2f(0, 0));
            if (vals[0] != vals[1] && !vals.isNaN()) {
                timerFrom = timeSecs(vals[0]);
                timerTo = timeSecs(vals[1]);
            } else {
                //xxx what about some kind of error reporting?
                hasTimer = false;
            }
        }
        relaxtime = timeSecs(node.getIntValue("relaxtime", 0));
        char[] pm = node.getStringValue("point");
        switch (pm) {
            case "target":
                point = PointMode.target;
                break;
            case "instant":
                point = PointMode.instant;
                break;
            case "instant_free":
                point = PointMode.instantFree;
                break;
            default:
        }
    }
}
