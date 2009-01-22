//this module contains net stuff, that's used by both client and server
//probably should be merged with gamepublic
//(by throwing out the stupid interfaces)
module game.netshared;

public import game.gamepublic;

import game.levelgen.level;
import game.gfxset;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.mybox;

//values set by the server, replicated by the client
class GameState {
    //this is practically the timestamp for a network frame
    Time servertime;

    GameEngineGraphics graphics;
    int water_offset;
    float wind_speed;
    float earth_quake_strength;
    Level level;
    Vector2i world_size, world_center;
    bool paused;
    float slow_down;
    char[] gamemode;
    int gamestate;
    MyBox gamemodestatus;
    int msgcounter;
    char[] msgid;
    char[][] msg;
    uint msg_rnd;
    int weaponlistcc;
    TeamState[] teams; //indexed by TeamState.index
    TeamState[] activeteams;
    //xxx: immutable, doesn't need to be synced over net all the time
    //     use an init-packet?
    WeaponHandle[] weaponlist;

    this () {
    }
    this (ReflectCtor c) {
    }
}

class TeamState {
    GameState gamestate;
    int index;
    char[] name;
    TeamTheme color;
    bool active;
    WeaponList weapons;
    MemberState[] members; //indexed by MemberState.index
    MemberState active_member;
    bool allowselect;

    this () {
    }
    this (ReflectCtor c) {
    }
}

class MemberState {
    int index;
    char[] name;
    TeamState team;
    bool alive;
    bool active;
    int current_health;
    Time last_action;
    WeaponHandle current_weapon;
    bool display_weapon_icon;
    Graphic graphic;

    this () {
    }
    this (ReflectCtor c) {
    }
}

class ClientState {
    MemberState controlledMember;

    this () {
    }
    this (ReflectCtor c) {
    }
}

//special class as item for NetEventQueue
class NetEvent {
    this () {
    }
    this (ReflectCtor c) {
    }
}

//this is specially handled by the network code (by checking the object type)
//the events array will be cleared...
// 1. on the server, after the network frame has been handled
// 2. on the client, as soon as the event has been sent into network (reliably)
class NetEventQueue {
    private {
        NetEvent[] for_receive;
    }

    //return all events and mark as read
    //xxx: memory of returned array will be reused
    NetEvent[] receive() {
        auto res = for_receive;
        for_receive.length = 0;
        return res;
    }

    void add(NetEvent e) {
        for_receive ~= e;
    }

    this () {
    }
    this (ReflectCtor c) {
    }
}

//used for client -> server communication
class ClientEvent : NetEvent {
    char[][] commands;

    this () {
    }
    this (ReflectCtor c) {
        super(c);
    }
}

class InitPacket {
    //serialized GameConfig
    char[] config;

    this () {
    }
    this (ReflectCtor c) {
    }
}

//completely locally shared
class PseudoNetwork {
    GameState shared_state;
    ClientState client_state;
    NetEventQueue client_to_server; //item type is ClientEvent
    InitPacket client_init;
}
