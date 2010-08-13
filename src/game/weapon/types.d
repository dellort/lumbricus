//This module just exists to fight some stupid compiler errors
//with dmd+Tango
module game.weapon.types;

import utils.randval;
import utils.strparser;
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

static this() {
    enumStrings!(PointMode, "none,target,targetTracking,instant,instantFree")();
    enumStrings!(ThrowDirection, "fixed,any,threeway,limit90")();
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
    //the param is either a time in seconds (e.g. banana bomb), or the count of
    //  things to spawn (e.g. mad cow)
    int paramFrom; //minimal param chooseable
    int paramTo;   //maximal param

    //return default value for weapon param
    int getParamDefault() {
        //xxx should this be configurable?
        return (paramFrom + paramTo)/2;
    }
}
