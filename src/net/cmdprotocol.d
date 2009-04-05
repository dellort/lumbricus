module net.cmdprotocol;

///Contains details about the protocol for simple command-based networking
///protocol writes a 2-byte id (ServerPacket/ClientPacket), followed by a struct
///  of user data
///all reading/writing is done by classes in net.marshal, so for byte-exact
///  encoding take a look there

//anytime you change some detail about the protocol, increment this
//  (including encoding/marshalling changes)
//only clients with the same version will be accepted
const ushort cProtocolVersion = 1;


//---------------------- Packet IDs ------------------------

//Server-to-client packet IDs
enum ServerPacket : ushort {
    error,
    conAccept,
    cmdResult,
    gameInfo,
    loadStatus,
    startLoading,
    gameStart,
    gameCommands,
}

//Client-to-server packet IDs
enum ClientPacket : ushort {
    error,
    hello,
    lobbyCmd,
    deployTeam,
    loadDone,
    gameCommand,
}


//-------------------- Server-to-client protocol --------------------

struct SPError {
    char[] errMsg;
    char[][] args;
}

struct SPConAccept {
    char[] playerName;
}

struct SPCmdResult {
    bool success;
    char[] msg;
}

struct SPGameInfo {
    //players and teams, always same length
    char[][] players;
    char[][] teams;
}

struct SPStartLoading {
    ubyte[] gameConfig;
}

//status information while clients are loading
struct SPLoadStatus {
    //players and flags if done loading, always same length
    char[][] players;
    bool[] done;
}

struct SPGameStart {
    char[][] players;
    char[][] teamIds;
}

struct GameCommandEntry {
    char[] player;
    char[] cmd;
}

struct SPGameCommands {
    uint timestamp;
    GameCommandEntry[] commands;
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

struct CPDeployTeam {
    char[] teamName;
    ubyte[] teamConf;
}

struct CPGameCommand {
    char[] cmd;
}
