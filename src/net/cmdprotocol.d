module net.cmdprotocol;

///Contains details about the protocol for simple command-based networking
///protocol writes a 2-byte id (ServerPacket/ClientPacket), followed by a struct
///  of user data
///all reading/writing is done by classes in net.marshal, so for byte-exact
///  encoding take a look there

import utils.time;

//anytime you change some detail about the protocol, increment this
//  (including encoding/marshalling changes)
//only clients with the same version will be accepted
const ushort cProtocolVersion = 2;


//---------------------- Packet IDs ------------------------

//Server-to-client packet IDs
enum ServerPacket : ushort {
    error,
    conAccept,
    cmdResult,
    playerList,
    playerInfo,
    loadStatus,
    startLoading,
    gameStart,
    gameCommands,
    ping,
}

//Client-to-server packet IDs
enum ClientPacket : ushort {
    error,
    hello,
    lobbyCmd,
    deployTeam,
    startLoading,
    loadDone,
    gameCommand,
    pong,
}

//reason for disconnection by the server
//if you need more codes, add to the end
enum DiscReason : uint {
    none,
    internalError,     //something unexpected went wrong
    protocolError,     //an invalid packet was received
    timeout,           //no response in a specified time
    wrongVersion,      //version mismatch between server and client
    serverShutdown,    //the server is going down
    invalidNick,       //the given nick is invalid or already in use
    gameStarted,       //the game has already started, server is not accepting
                       //  connections any more
    serverFull,
}

const char[][DiscReason.max+1] reasonToString = [
    "",
    "error_internal",
    "error_protocol",
    "error_timeout",
    "error_wrongversion",
    "error_servershutdown",
    "error_invalidnick",
    "error_gamestarted",
    "error_serverfull",
    ];


//-------------------- Server-to-client protocol --------------------

struct SPError {
    char[] errMsg;
    char[][] args;
}

struct SPConAccept {
    uint id;
    char[] playerName;
}

struct SPCmdResult {
    bool success;
    char[] msg;
}

//list of players and their ids, updated on connect/disconnect/nickchange
struct SPPlayerList {
    Player[] players;

    struct Player {
        uint id;
        char[] name;
    }
}

struct PlayerDetails {
    uint id;
    char[] teamName;
    Time ping;
}

//information about connected players, updated periodically
struct SPPlayerInfo {
    PlayerDetails[] players;
}

struct SPStartLoading {
    ubyte[] gameConfig;
}

//status information while clients are loading
struct SPLoadStatus {
    //players and flags if done loading, always same length
    uint[] playerIds;
    bool[] done;
}

struct SPGameStart {
    //each entry lets a player control teams
    Player_Team[] mapping;

    struct Player_Team {
        uint playerId;
        char[][] team;
    }
}

struct GameCommandEntry {
    uint playerId;
    char[] cmd;
}

struct SPGameCommands {
    uint timestamp;
    GameCommandEntry[] commands;
}

struct SPPing {
    Time ts;
}


//--------------------- Client-to-server protocol ------------------

struct CPError {
    char[] errMsg;
}

struct CPHello {
    ushort protocolVersion = cProtocolVersion;
    char[] playerName;
}

struct CPLobbyCmd {
    char[] cmd;
}

//client sends this to server, server adds teams, server sends SPStartLoading to
//all clients (here, it would be simpler to replicate the "lobby logic"
//[like assigning teams] on all clients, and then just let the server broadcast
//this message, without changing the contents... maybe... or maybe not)
struct CPStartLoading {
    ubyte[] gameConfig;
}

struct CPDeployTeam {
    char[] teamName;
    ubyte[] teamConf;
}

struct CPGameCommand {
    char[] cmd;
}

struct CPPong {
    Time ts;
}
