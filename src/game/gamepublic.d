///This module contains everything the ClientEngine should see of the
///GameEngine, to make the client-server-link weaker
module game.gamepublic;

import framework.framework;
import game.animation;
import game.glevel;
import levelgen.level;
import utils.configfile;
import utils.vector2;
import utils.time;

///Initial game configuration
struct GameConfig {
    Level level;
    ConfigNode teams;
    ConfigNode weapons;
    ConfigNode gamemode;
}

enum GraphicEventType {
    None,
    Add,
    Change,
    Remove,
}

struct GraphicEvent {
    GraphicEvent* next; //ad-hoc linked list

    GraphicEventType type;
    long uid;
    GraphicSetEvent setevent;
}

struct GraphicSetEvent {
    Vector2i pos;
    Vector2f dir; //direction + velocity
    int p1, p2;
    bool do_set_ani;
    AnimationResource set_animation; //network had to transfer animation id
    bool set_force;
}

///GameEngine public interface
interface GameEnginePublic {
    ///get an administrator interface (xxx add some sort of protection)
    GameEngineAdmin requestAdmin();

    ///current water offset
    int waterOffset();

    ///current wind speed
    float windSpeed();

    ///list of graphics events for the client to process
    GraphicEvent* currentEvents();

    ///clear list of currently pending events
    void clearEvents();

    ///get controller interface
    ControllerPublic controller();

    ///level being played
    Level level();

    ///another level (xxx maybe join those?)
    GameLevel gamelevel();

    ///total size of game world
    Vector2i worldSize();

    ///is the game time paused?
    bool paused();

    ///time flow multiplier
    float slowDown();
}

///administrator interface to game
///contains functions to change game/world state
interface GameEngineAdmin {
    ///raise water level
    void raiseWater(int by);

    ///change wind speed
    void setWindSpeed(float speed);

    ///pause game
    void setPaused(bool paused);

    ///slow down game time
    void setSlowDown(float slow);
}

enum RoundState {
    prepare,    //player ready
    playing,    //round running
    cleaningUp, //worms losing hp etc, may occur during round
    nextOnHold, //next round about to start (drop crates, ...)
    end,        //everything ended!
}

///public interface to game controller
interface ControllerPublic {
    RoundState currentRoundState();

    Time currentRoundTime();

    ///set this callback to receive messages
    void delegate(char[]) messageCb();
    void messageCb(void delegate(char[]) cb);

    ///pass an event to the controller
    bool onKeyDown(char[] bind, KeyInfo info, Vector2i mousePos);
    bool onKeyUp(char[] bind, KeyInfo info, Vector2i mousePos);

    void selectWeapon(char[] weaponId);
}

//Hint: there's a limited number of predefined colors; that's because sometimes
//colors are hardcoded in animations, etc.
//so, these are not just color names, but also linked to these animations
static const char[][] cTeamColors = [
    "red",
    "blue",
    "green",
    "yellow",
    "magenta",
    "cyan",
];
