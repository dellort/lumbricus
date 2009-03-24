module derelict.enet.enettypes;

extern(C):

// ---------------------------- types.h ------------------------------

alias ubyte enet_uint8;
alias ushort enet_uint16;
alias uint enet_uint32;


// ----------------------- win32.h / unix.h --------------------------

version(Windows) {
    alias uint SOCKET;
    alias SOCKET ENetSocket;

    enum
    {
        ENET_SOCKET_NULL = cast(SOCKET)(~0),
    }
} else {
    alias int ENetSocket;

    enum
    {
        ENET_SOCKET_NULL = -1,
    }
}

version(Windows) {
    struct ENetBuffer
    {
        size_t dataLength;
        void *data;
    }
} else {
    struct ENetBuffer
    {
        void *data;
        size_t dataLength;
    }
}


// -------------------------- protocol.h --------------------------------

enum
{
   ENET_PROTOCOL_MINIMUM_MTU             = 576,
   ENET_PROTOCOL_MAXIMUM_MTU             = 4096,
   ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS = 32,
   ENET_PROTOCOL_MINIMUM_WINDOW_SIZE     = 4096,
   ENET_PROTOCOL_MAXIMUM_WINDOW_SIZE     = 32768,
   ENET_PROTOCOL_MINIMUM_CHANNEL_COUNT   = 1,
   ENET_PROTOCOL_MAXIMUM_CHANNEL_COUNT   = 255,
   ENET_PROTOCOL_MAXIMUM_PEER_ID         = 0x7FFF
}

typedef int ENetProtocolCommand;
enum : ENetProtocolCommand
{
   ENET_PROTOCOL_COMMAND_NONE               = 0,
   ENET_PROTOCOL_COMMAND_ACKNOWLEDGE        = 1,
   ENET_PROTOCOL_COMMAND_CONNECT            = 2,
   ENET_PROTOCOL_COMMAND_VERIFY_CONNECT     = 3,
   ENET_PROTOCOL_COMMAND_DISCONNECT         = 4,
   ENET_PROTOCOL_COMMAND_PING               = 5,
   ENET_PROTOCOL_COMMAND_SEND_RELIABLE      = 6,
   ENET_PROTOCOL_COMMAND_SEND_UNRELIABLE    = 7,
   ENET_PROTOCOL_COMMAND_SEND_FRAGMENT      = 8,
   ENET_PROTOCOL_COMMAND_SEND_UNSEQUENCED   = 9,
   ENET_PROTOCOL_COMMAND_BANDWIDTH_LIMIT    = 10,
   ENET_PROTOCOL_COMMAND_THROTTLE_CONFIGURE = 11,
   ENET_PROTOCOL_COMMAND_COUNT              = 12,

   ENET_PROTOCOL_COMMAND_MASK               = 0x0F
}

typedef int ENetProtocolFlag;
enum : ENetProtocolFlag
{
   ENET_PROTOCOL_COMMAND_FLAG_ACKNOWLEDGE = (1 << 7),
   ENET_PROTOCOL_COMMAND_FLAG_UNSEQUENCED = (1 << 6),

   ENET_PROTOCOL_HEADER_FLAG_SENT_TIME = (1 << 15),
   ENET_PROTOCOL_HEADER_FLAG_MASK      = 0x8000
}

struct ENetProtocolHeader
{
    enet_uint32 checksum;
    enet_uint16 peerID;
    enet_uint16 sentTime;
}

struct ENetProtocolCommandHeader
{
    enet_uint8 command;
    enet_uint8 channelID;
    enet_uint16 reliableSequenceNumber;
}

struct ENetProtocolAcknowledge
{
    ENetProtocolCommandHeader header;
    enet_uint16 receivedReliableSequenceNumber;
    enet_uint16 receivedSentTime;
}

struct ENetProtocolConnect
{
    ENetProtocolCommandHeader header;
    enet_uint16 outgoingPeerID;
    enet_uint16 mtu;
    enet_uint32 windowSize;
    enet_uint32 channelCount;
    enet_uint32 incomingBandwidth;
    enet_uint32 outgoingBandwidth;
    enet_uint32 packetThrottleInterval;
    enet_uint32 packetThrottleAcceleration;
    enet_uint32 packetThrottleDeceleration;
    enet_uint32 sessionID;
}

struct ENetProtocolVerifyConnect
{
    ENetProtocolCommandHeader header;
    enet_uint16 outgoingPeerID;
    enet_uint16 mtu;
    enet_uint32 windowSize;
    enet_uint32 channelCount;
    enet_uint32 incomingBandwidth;
    enet_uint32 outgoingBandwidth;
    enet_uint32 packetThrottleInterval;
    enet_uint32 packetThrottleAcceleration;
    enet_uint32 packetThrottleDeceleration;
}

struct ENetProtocolBandwidthLimit
{
    ENetProtocolCommandHeader header;
    enet_uint32 incomingBandwidth;
    enet_uint32 outgoingBandwidth;
}

struct ENetProtocolThrottleConfigure
{
    ENetProtocolCommandHeader header;
    enet_uint32 packetThrottleInterval;
    enet_uint32 packetThrottleAcceleration;
    enet_uint32 packetThrottleDeceleration;
}

struct ENetProtocolDisconnect
{
    ENetProtocolCommandHeader header;
    enet_uint32 data;
}

struct ENetProtocolPing
{
    ENetProtocolCommandHeader header;
}

struct ENetProtocolSendReliable
{
    ENetProtocolCommandHeader header;
    enet_uint16 dataLength;
}

struct ENetProtocolSendUnreliable
{
    ENetProtocolCommandHeader header;
    enet_uint16 unreliableSequenceNumber;
    enet_uint16 dataLength;
}

struct ENetProtocolSendUnsequenced
{
    ENetProtocolCommandHeader header;
    enet_uint16 unsequencedGroup;
    enet_uint16 dataLength;
}

struct ENetProtocolSendFragment
{
    ENetProtocolCommandHeader header;
    enet_uint16 startSequenceNumber;
    enet_uint16 dataLength;
    enet_uint32 fragmentCount;
    enet_uint32 fragmentNumber;
    enet_uint32 totalLength;
    enet_uint32 fragmentOffset;
}

union ENetProtocol
{
    ENetProtocolCommandHeader header;
    ENetProtocolAcknowledge acknowledge;
    ENetProtocolConnect connect;
    ENetProtocolVerifyConnect verifyConnect;
    ENetProtocolDisconnect disconnect;
    ENetProtocolPing ping;
    ENetProtocolSendReliable sendReliable;
    ENetProtocolSendUnreliable sendUnreliable;
    ENetProtocolSendUnsequenced sendUnsequenced;
    ENetProtocolSendFragment sendFragment;
    ENetProtocolBandwidthLimit bandwidthLimit;
    ENetProtocolThrottleConfigure throttleConfigure;
}


// ---------------------------- list.h ------------------------------

struct _ENetListNode
{
    _ENetListNode *next;
    _ENetListNode *previous;
}
alias _ENetListNode ENetListNode;

alias ENetListNode *ENetListIterator;

struct _ENetList
{
    ENetListNode sentinel;
}
alias _ENetList ENetList;


// ---------------------------- callbacks.h ---------------------------

struct ENetCallbacks
{
    void * function(size_t size)malloc;
    void  function(void *memory)free;
    int  function()rand;
}


// ----------------------------enet.h -----------------------------------

typedef int ENetVersion;
enum : ENetVersion
{
    ENET_VERSION = 1,
}

typedef int ENetSocketType;
enum : ENetSocketType
{
    ENET_SOCKET_TYPE_STREAM = 1,
    ENET_SOCKET_TYPE_DATAGRAM,
}

typedef int ENetSocketWait;
enum : ENetSocketWait
{
    ENET_SOCKET_WAIT_NONE,
    ENET_SOCKET_WAIT_SEND,
    ENET_SOCKET_WAIT_RECEIVE,
}

typedef int ENetSocketOption;
enum : ENetSocketOption
{
   ENET_SOCKOPT_NONBLOCK  = 1,
   ENET_SOCKOPT_BROADCAST = 2,
   ENET_SOCKOPT_RCVBUF    = 3,
   ENET_SOCKOPT_SNDBUF    = 4
}

enum
{
    ENET_HOST_ANY = 0,
    ENET_HOST_BROADCAST = 0xFFFFFFFF,

    ENET_PORT_ANY = 0,
}

typedef int ENetEventType;
enum : ENetEventType
{
    ENET_EVENT_TYPE_NONE,
    ENET_EVENT_TYPE_CONNECT,
    ENET_EVENT_TYPE_DISCONNECT,
    ENET_EVENT_TYPE_RECEIVE,
}

typedef int ENetPacketFlag;
enum : ENetPacketFlag
{
    ENET_PACKET_FLAG_RELIABLE = 1,
    ENET_PACKET_FLAG_UNSEQUENCED,
    ENET_PACKET_FLAG_NO_ALLOCATE = 4,
}

enum
{
   ENET_HOST_RECEIVE_BUFFER_SIZE          = 256 * 1024,
   ENET_HOST_SEND_BUFFER_SIZE             = 256 * 1024,
   ENET_HOST_BANDWIDTH_THROTTLE_INTERVAL  = 1000,
   ENET_HOST_DEFAULT_MTU                  = 1400,

   ENET_PEER_DEFAULT_ROUND_TRIP_TIME      = 500,
   ENET_PEER_DEFAULT_PACKET_THROTTLE      = 32,
   ENET_PEER_PACKET_THROTTLE_SCALE        = 32,
   ENET_PEER_PACKET_THROTTLE_COUNTER      = 7,
   ENET_PEER_PACKET_THROTTLE_ACCELERATION = 2,
   ENET_PEER_PACKET_THROTTLE_DECELERATION = 2,
   ENET_PEER_PACKET_THROTTLE_INTERVAL     = 5000,
   ENET_PEER_PACKET_LOSS_SCALE            = (1 << 16),
   ENET_PEER_PACKET_LOSS_INTERVAL         = 10000,
   ENET_PEER_WINDOW_SIZE_SCALE            = 64 * 1024,
   ENET_PEER_TIMEOUT_LIMIT                = 32,
   ENET_PEER_TIMEOUT_MINIMUM              = 5000,
   ENET_PEER_TIMEOUT_MAXIMUM              = 30000,
   ENET_PEER_PING_INTERVAL                = 500,
   ENET_PEER_UNSEQUENCED_WINDOWS          = 64,
   ENET_PEER_UNSEQUENCED_WINDOW_SIZE      = 1024,
   ENET_PEER_FREE_UNSEQUENCED_WINDOWS     = 32,
   ENET_PEER_RELIABLE_WINDOWS             = 16,
   ENET_PEER_RELIABLE_WINDOW_SIZE         = 0x1000,
   ENET_PEER_FREE_RELIABLE_WINDOWS        = 8
}


struct _ENetAddress
{
    enet_uint32 host;
    enet_uint16 port;
}
alias _ENetAddress ENetAddress;

alias void  function(_ENetPacket *)ENetPacketFreeCallback;


struct _ENetPacket
{
    size_t referenceCount;
    enet_uint32 flags;
    enet_uint8 *data;
    size_t dataLength;
    ENetPacketFreeCallback freeCallback;
}
alias _ENetPacket ENetPacket;

struct _ENetAcknowledgement
{
    ENetListNode acknowledgementList;
    enet_uint32 sentTime;
    ENetProtocol command;
}
alias _ENetAcknowledgement ENetAcknowledgement;

struct _ENetOutgoingCommand
{
    ENetListNode outgoingCommandList;
    enet_uint16 reliableSequenceNumber;
    enet_uint16 unreliableSequenceNumber;
    enet_uint32 sentTime;
    enet_uint32 roundTripTimeout;
    enet_uint32 roundTripTimeoutLimit;
    enet_uint32 fragmentOffset;
    enet_uint16 fragmentLength;
    enet_uint16 sendAttempts;
    ENetProtocol command;
    ENetPacket *packet;
}
alias _ENetOutgoingCommand ENetOutgoingCommand;

struct _ENetIncomingCommand
{
    ENetListNode incomingCommandList;
    enet_uint16 reliableSequenceNumber;
    enet_uint16 unreliableSequenceNumber;
    ENetProtocol command;
    enet_uint32 fragmentCount;
    enet_uint32 fragmentsRemaining;
    enet_uint32 *fragments;
    ENetPacket *packet;
}
alias _ENetIncomingCommand ENetIncomingCommand;

enum
{
    ENET_PEER_STATE_DISCONNECTED,
    ENET_PEER_STATE_CONNECTING,
    ENET_PEER_STATE_ACKNOWLEDGING_CONNECT,
    ENET_PEER_STATE_CONNECTION_PENDING,
    ENET_PEER_STATE_CONNECTION_SUCCEEDED,
    ENET_PEER_STATE_CONNECTED,
    ENET_PEER_STATE_DISCONNECT_LATER,
    ENET_PEER_STATE_DISCONNECTING,
    ENET_PEER_STATE_ACKNOWLEDGING_DISCONNECT,
    ENET_PEER_STATE_ZOMBIE,
}
alias int ENetPeerState;

enum
{
    ENET_BUFFER_MAXIMUM = (1 + 2 * ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS)
}

struct _ENetChannel
{
    enet_uint16 outgoingReliableSequenceNumber;
    enet_uint16 outgoingUnreliableSequenceNumber;
    enet_uint16 usedReliableWindows;
    enet_uint16[ENET_PEER_RELIABLE_WINDOWS] reliableWindows ;
    enet_uint16 incomingReliableSequenceNumber;
    ENetList incomingReliableCommands;
    ENetList incomingUnreliableCommands;
}
alias _ENetChannel ENetChannel;

struct _ENetPeer
{
    _ENetHost *host;
    enet_uint16 outgoingPeerID;
    enet_uint16 incomingPeerID;
    enet_uint32 sessionID;
    ENetAddress address;
    void *data;
    ENetPeerState state;
    ENetChannel *channels;
    size_t channelCount;
    enet_uint32 incomingBandwidth;
    enet_uint32 outgoingBandwidth;
    enet_uint32 incomingBandwidthThrottleEpoch;
    enet_uint32 outgoingBandwidthThrottleEpoch;
    enet_uint32 incomingDataTotal;
    enet_uint32 outgoingDataTotal;
    enet_uint32 lastSendTime;
    enet_uint32 lastReceiveTime;
    enet_uint32 nextTimeout;
    enet_uint32 earliestTimeout;
    enet_uint32 packetLossEpoch;
    enet_uint32 packetsSent;
    enet_uint32 packetsLost;
    enet_uint32 packetLoss;
    enet_uint32 packetLossVariance;
    enet_uint32 packetThrottle;
    enet_uint32 packetThrottleLimit;
    enet_uint32 packetThrottleCounter;
    enet_uint32 packetThrottleEpoch;
    enet_uint32 packetThrottleAcceleration;
    enet_uint32 packetThrottleDeceleration;
    enet_uint32 packetThrottleInterval;
    enet_uint32 lastRoundTripTime;
    enet_uint32 lowestRoundTripTime;
    enet_uint32 lastRoundTripTimeVariance;
    enet_uint32 highestRoundTripTimeVariance;
    enet_uint32 roundTripTime;
    enet_uint32 roundTripTimeVariance;
    enet_uint16 mtu;
    enet_uint32 windowSize;
    enet_uint32 reliableDataInTransit;
    enet_uint16 outgoingReliableSequenceNumber;
    ENetList acknowledgements;
    ENetList sentReliableCommands;
    ENetList sentUnreliableCommands;
    ENetList outgoingReliableCommands;
    ENetList outgoingUnreliableCommands;
    enet_uint16 incomingUnsequencedGroup;
    enet_uint16 outgoingUnsequencedGroup;
    enet_uint32[ENET_PEER_UNSEQUENCED_WINDOW_SIZE / 32] unsequencedWindow;
    enet_uint32 disconnectData;
}
alias _ENetPeer ENetPeer;

struct _ENetHost
{
    ENetSocket socket;
    ENetAddress address;
    enet_uint32 incomingBandwidth;
    enet_uint32 outgoingBandwidth;
    enet_uint32 bandwidthThrottleEpoch;
    enet_uint32 mtu;
    int recalculateBandwidthLimits;
    ENetPeer *peers;
    size_t peerCount;
    enet_uint32 serviceTime;
    ENetPeer *lastServicedPeer;
    int continueSending;
    size_t packetSize;
    enet_uint16 headerFlags;
    ENetProtocol[ENET_PROTOCOL_MAXIMUM_PACKET_COMMANDS] commands;
    size_t commandCount;
    ENetBuffer[ENET_BUFFER_MAXIMUM] buffers;
    size_t bufferCount;
    ENetAddress receivedAddress;
    enet_uint8[ENET_PROTOCOL_MAXIMUM_MTU] receivedData;
    size_t receivedDataLength;
}
alias _ENetHost ENetHost;

struct _ENetEvent
{
    ENetEventType type;
    ENetPeer *peer;
    enet_uint8 channelID;
    enet_uint32 data;
    ENetPacket *packet;
}
alias _ENetEvent ENetEvent;
