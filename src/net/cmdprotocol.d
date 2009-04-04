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
    cmdResult,
}

//Client-to-server packet IDs
enum ClientPacket : ushort {
    error,
    hello,
    lobbyCmd,
}


//-------------------- Server-to-client protocol --------------------

struct SPError {
    char[] errMsg;
    char[][] args;
}

struct SPCmdResult {
    bool success;
    char[] msg;
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
