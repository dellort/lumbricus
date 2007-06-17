module enet.enet;

import derelict.enet.enet;
import str = std.string;

pragma(lib,"DerelictUtil");

struct NetAddress {
    char[] hostName;
    ushort port;
    bool broadcast = false;

    ///create standard address (connection to peer)
    static NetAddress opCall(char[] hostName, ushort port) {
        NetAddress ret;
        ret.hostName = hostName;
        ret.port = port;
        ret.broadcast = false;
        return ret;
    }

    ///create broadcast address
    static NetAddress opCall(ushort port) {
        NetAddress ret;
        ret.port = port;
        ret.broadcast = true;
        return ret;
    }
}

///base class for network library, make sure to manually delete it before
///the app ends or you may get an AV
class NetBase {
    this() {
        DerelictENet.load();
        if (enet_initialize() != 0)
            throw new NetException("Initialization of network lib failed");
    }

    ~this() {
        enet_deinitialize();
        DerelictENet.unload();
    }

    ///create a server host and bind to port
    NetHost createServer(ushort port, int maxConnections) {
        ENetAddress addr;
        ENetHost* server;

        addr.port = port;
        addr.host = ENET_HOST_ANY;

        //create host and bind to port
        server = enet_host_create(&addr, maxConnections, 0, 0);
        if (!server)
            throw new NetException("Failed to create server host");

        return new NetHost(port, maxConnections, server);
    }

    ///create an unbound client host, not yet connected
    NetHost createClient(int maxConnections = 1) {
        ENetHost* client;
        //create unbound host
        client = enet_host_create(null, maxConnections, 0, 0);
        if (!client)
            throw new NetException("Failed to create client host");

        return new NetHost(0, maxConnections, client);
    }
}

///an unconnected network host, representing either server or client
///make sure to call serviceAll() regularly to handle events
class NetHost {
    private int mMaxConnections;
    private ushort mBoundPort;
    private ENetHost* mHost;

    ///called whenever a new connection is established
    void delegate(NetHost sender, NetPeer peer) onConnect;

    private this(ushort port, int maxConnections, ENetHost* host) {
        mMaxConnections = maxConnections;
        mBoundPort = port;
        mHost = host;
    }

    ~this()  {
        enet_host_destroy(mHost);
    }

    ///is this host bound to a port (i.e. accepting incoming connections),
    ///or is it just a client
    bool isBound() {
        return mBoundPort > 0;
    }

    ///port to which this host is bound, 0 if not bound
    ushort boundPort() {
        return mBoundPort;
    }

    ///initiate outgoing connection, onConnect is called when the connection
    ///is established
    ///if this is a 1-connection client host, use serviceOne with a timeout
    ///to wait for the connection
    void connect(NetAddress addr, ubyte channelCount) {
        //convert address to ENetAddress
        ENetAddress enaddr;
        enaddr.port = addr.port;
        if (addr.broadcast)
            enaddr.host = ENET_HOST_BROADCAST;
        else
            enet_address_set_host(&enaddr, str.toStringz(addr.hostName));

        //initiate connection (will not connect until next service() call
        ENetPeer* peer = enet_host_connect(mHost, &enaddr, channelCount);
        if (!peer)
            throw new NetException(
                "Connection attempt failed: No available peers");
        //no need to store peer, as it is passed with the connect event
    }

    ///process all waiting events and return immediately
    void serviceAll() {
        ENetEvent event;
        while (enet_host_service(mHost, &event, 0) > 0) {
            handleEvent(event);
        }
    }

    ///wait timeoutMs for an event and return true if one occured
    bool serviceOne(int timeoutMs) {
        ENetEvent event;
        if (enet_host_service(mHost, &event, timeoutMs) > 0) {
            //got event
            if (handleEvent(event))
                return true;
        }
        return false;
    }

    private bool handleEvent(inout ENetEvent event) {
        switch (event.type) {
            case ENET_EVENT_TYPE_CONNECT:
                auto peer = new NetPeer(this, event.peer);
                event.peer.data = cast(void*)peer;
                if (onConnect)
                    onConnect(this, peer);
                break;
            case ENET_EVENT_TYPE_RECEIVE:
                auto peer = cast(NetPeer)event.peer.data;
                assert(peer !is null);
                //check if peer has no disconnect pending
                if (peer.connected) {
                    peer.handleReceive(event.channelID, event.packet.data,
                        event.packet.dataLength);
                }
                enet_packet_destroy(event.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                auto peer = cast(NetPeer)event.peer.data;
                if (peer) {
                    peer.handleDisconnect();
                    event.peer.data = null;
                } else {
                    //outgoing connection failed
                }
                break;
            default:
                return false;
                break;
        }
        return true;
    }

    ///send all queued packets now (instead of waiting for next service call)
    ///will not handle events
    void flush() {
        enet_host_flush(mHost);
    }

    ///send a packet to all connected clients
    //xxx code duplication from NetPeer.send()
    void sendBroadcast(void* data, size_t dataLen, ubyte channelId,
        bool immediate = false, bool reliable = true, bool sequenced = true)
    {
        uint packetFlags;
        assert(!reliable || sequenced, "NetHost.sendBroadcast: Invalid flags");
        if (reliable)
            packetFlags |= ENET_PACKET_FLAG_RELIABLE;
        if (!sequenced)
            packetFlags |= ENET_PACKET_FLAG_UNSEQUENCED;
        ENetPacket* packet = enet_packet_create(data, dataLen, packetFlags);

        //queue packet for send
        enet_host_broadcast(mHost, channelId, packet);
        if (immediate)
            flush();
        //packet will be deallocated by enet
    }
}

///a connection to a peer, created by NetHost when a connection is established
///will be connected after creation, until you get the onDisconnect event
class NetPeer {
    private ENetPeer* mPeer;
    private bool mConnected;
    private NetAddress mAddress;
    private NetHost mHost;

    ///called when connection has been terminated
    void delegate(NetPeer sender) onDisconnect;
    void delegate(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen) onReceive;

    private this(NetHost parent, ENetPeer* peer) {
        mHost = parent;
        mPeer = peer;
        mConnected = true;
        mAddress.port = mPeer.address.port;
        char[] addrBuf = new char[16];
        enet_address_get_host_ip(&mPeer.address, addrBuf.ptr, 16);
        mAddress.hostName = str.toString(addrBuf.ptr);
    }

    ///associated host
    NetHost host() {
        return mHost;
    }

    private void handleDisconnect() {
        if (onDisconnect)
            onDisconnect(this);
    }

    private void handleReceive(ubyte channelId, ubyte* data, size_t dataLen) {
        if (onReceive)
            onReceive(this, channelId, data, dataLen);
    }

    ///close the connection
    ///you are guaranteed not to receive packets after this call
    void disconnect() {
        enet_peer_disconnect(mPeer, 0);
        mConnected = false;
    }

    ///is this connection active?
    bool connected() {
        return mConnected;
    }

    ///number of assigned channels
    size_t channelCount() {
        return mPeer.channelCount;
    }

    ///address of remote peer connected to (port and ip)
    NetAddress address() {
        return mAddress;
    }

    ///send a packet over this connection
    void send(void* data, size_t dataLen, ubyte channelId,
        bool immediate = false, bool reliable = true, bool sequenced = true)
    {
        uint packetFlags;
        assert(!reliable || sequenced, "NetPeer.send: Invalid flags");
        if (reliable)
            packetFlags |= ENET_PACKET_FLAG_RELIABLE;
        if (!sequenced)
            packetFlags |= ENET_PACKET_FLAG_UNSEQUENCED;
        ENetPacket* packet = enet_packet_create(data, dataLen, packetFlags);

        //queue packet for send
        enet_peer_send(mPeer, channelId, packet);
        if (immediate)
            mHost.flush();
        //packet will be deallocated by enet
    }
}

class NetException : Exception {
    this(char[] msg) {
        super(msg);
    }
}
