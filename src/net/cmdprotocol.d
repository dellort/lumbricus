module net.cmdprotocol;

///Contains details about the protocol for simple command-based networking
///protocol writes a 2-byte id (ServerPacket/ClientPacket), followed by a struct
///  of user data
///all reading/writing is done by classes in net.marshal, so for byte-exact
///  encoding take a look there

import utils.time;

//xxx still hacky, but game.temp is an isolated module (will not import engine)
import game.temp : EngineHash;

//anytime you change some detail about the protocol, increment this
//  (including encoding/marshalling changes)
//only clients with the same version will be accepted
enum ushort cProtocolVersion = 4;


//-------------------- Query protocol ----------------------
//Request: cQueryIdent
//Response: cQueryIdent + marshal(cProtocolVersion ~ QueryResponse)
//query port is the same as gameport, so no port in response

//Note: enet header is 8 bytes, so no danger of mixup
enum cQueryIdent = "LQ";

//contents of this may depend on server version
//so check version before reading response data
struct QueryResponse {
    string serverName;
    ushort curPlayers;
    ushort maxPlayers;
    string[] players;
}


//---------------------- Packet IDs ------------------------

//Server-to-client packet IDs
//packet structs prefixed with SP
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
    clientBroadcast,
    grantCreateGame,
    acceptCreateGame,
    gameAsync,
}

//Client-to-server packet IDs
//packet structs prefixed with CP
enum ClientPacket : ushort {
    error,
    hello,
    lobbyCmd,
    deployTeam,
    requestCreateGame,
    prepareCreateGame,
    createGame,
    loadDone,
    gameCommand,
    pong,
    ack,
    clientBroadcast,
    gameTerminated,
}

//Client-to-client packet IDs
//packet structs prefixed with CC
enum Client2ClientPacket : ushort {
    chatMessage,
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

enum string[DiscReason.max+1] reasonToString = [
    "none",
    "internal_error",
    "protocol_error",
    "timeout",
    "wrong_version",
    "server_shutdown",
    "invalid_nick",
    "game_started",
    "server_full",
    ];


//-------------------- Server-to-client protocol --------------------

struct SPError {
    string errMsg;
    string[] args;
}

struct SPConAccept {
    uint id;
    string playerName;
}

struct SPCmdResult {
    bool success;
    string msg;
}

//list of players and their ids, updated on connect/disconnect/nickchange
//contains info that does not change to often
struct SPPlayerList {
    Player[] players;

    struct Player {
        uint id;
        string name;
        string teamName;
    }
}

//information about connected players, updated periodically
struct SPPlayerInfo {
    //a flag is set for all fields that have changed
    ushort updateFlags;
    Details[] players;

    enum Flags : ushort {
        ping = 1,
    }

    struct Details {
        uint id;
        Time ping;
    }
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
    //lol, nothing left
}

struct GameCommandEntry {
    uint playerId;
    string cmd;
}

struct SPGameCommands {
    uint timestamp;
    //players that disconnected since last frame
    uint[] disconnectIds;
    //all game commands since last frame
    GameCommandEntry[] commands;
}

struct SPPing {
    Time ts;
}

//a client sends all other clients (and itself) a message
//the actual message data follows after this struct
struct SPClientBroadcast {
    //player that sent the message
    int senderPlayerId;
}

struct SPGrantCreateGame {
    enum State {
        granted,
        revoked,
        starting,
    }

    uint playerId;
    State state;
}

struct SPAcceptCreateGame {
    Team[] teams;

    struct Team {
        uint playerId;
        string teamName;
        ubyte[] teamConf;
    }
}

//game is async (will only be sent once per round)
struct SPGameAsync {
    uint timestamp;
    EngineHash hash, expected;
}


//--------------------- Client-to-server protocol ------------------

struct CPError {
    string errMsg;
}

struct CPHello {
    ushort protocolVersion = cProtocolVersion;
    string playerName;
}

struct CPLobbyCmd {
    string cmd;
}

struct CPRequestCreateGame {
    bool request;  //false to revoke
}

//client sends this to server, server adds teams, server sends SPStartLoading to
//all clients (here, it would be simpler to replicate the "lobby logic"
//[like assigning teams] on all clients, and then just let the server broadcast
//this message, without changing the contents... maybe... or maybe not)
struct CPCreateGame {
    ubyte[] gameConfig;
}

struct CPDeployTeam {
    string teamName;
    ubyte[] teamConf;
}

struct CPGameCommand {
    string cmd;
}

struct CPPong {
    Time ts;
}

//ack that frame timestamp was executed and send hash for comparison
struct CPAck {
    uint timestamp;
    EngineHash hash;
}

//-------- Client-to-client

struct CCChatMessage {
    string witty_comment;
}
