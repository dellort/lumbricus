//This module just exists to fight some stupid compiler errors
//with dmd+Tango
module game.weapon.types;

import utils.configfile;
import utils.randval;
import utils.time;
import utils.vector2;

enum PointMode {
    none,
    target,
    targetTracking,
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
    float throwStrengthFrom = 0;   //1?? wtf?!
    float throwStrengthTo = 0;
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

        //abusing RandomValue as tange type
        RandomValue!(Time) vals;
        vals = node.getValue("timerrange", vals);
        timerFrom = vals.min;
        timerTo = vals.max;
        //some kind of post-validation?
        if (vals.min == vals.max) {
            assert(!hasTimer, "user error in .conf file");
        }

        relaxtime = node.getValue("relaxtime", relaxtime);
        char[] pm = node.getStringValue("point");
        switch (pm) {
            case "target":
                point = PointMode.target;
                break;
            case "target_tracking":
                point = PointMode.targetTracking;
                break;
            case "instant":
                point = PointMode.instant;
                break;
            case "instant_free":
                point = PointMode.instantFree;
                break;
            case "":
                break;
            default:
                //no more ignore errors silently
                assert(false, "user error in .conf file");
        }
    }
}
