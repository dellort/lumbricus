module net.netlayer;

import derelict.enet.enet;
import net.broadcast;
import str = utils.string;
import tango.util.Convert;
import tango.stdc.stringz;
import utils.misc;

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

    ///parse a standard address from a string
    ///format: <host> ":" <port>
    ///sets port to 0 if missing or not a number
    ///the hostname "broadcast" is hardwired to set the broadcast flag!
    static NetAddress opCall(char[] name) {
        auto index = str.rfind(name, ":");
        auto host = index > 0 ? name[0..index] : name;
        ushort p = 0;
        if (index >= 0) {
            try {
                p = to!(ushort)(name[index+1..$]);
            } catch (ConversionException e) { //sucks, don't care
            }
        }
        auto addr = opCall(host, p);
        if (host == "broadcast")
            addr.broadcast = true;
        return addr;
    }

    ///create broadcast address
    static NetAddress opCall(ushort port) {
        NetAddress ret;
        ret.port = port;
        ret.broadcast = true;
        return ret;
    }

    char[] toString() {
        return myformat("['{}', {}{}]", hostName, port,
            broadcast ? " (broadcast)" : "");
    }
}

///base class for network library, make sure to manually delete it before
///the app ends or you may get an AV
class NetBase {
    //allow several instances of NetBase without messing things up
    private static int mRefCount;
    this() {
        mRefCount++;
        if (mRefCount != 1)
            return;
        DerelictENet.load();
        if (enet_initialize() != 0)
            throw new NetException("Initialization of network lib failed");
    }

    ~this() {
        mRefCount--;
        if (mRefCount != 0)
            return;
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

        return new NetHost(this, port, maxConnections, server);
    }

    ///create an unbound client host, not yet connected
    NetHost createClient(int maxConnections = 1) {
        ENetHost* client;
        //create unbound host
        client = enet_host_create(null, maxConnections, 0, 0);
        if (!client)
            throw new NetException("Failed to create client host");

        return new NetHost(this, 0, maxConnections, client);
    }
}

private ENetPacket* prepareENetPacket(ubyte[] data, bool reliable = true,
    bool sequenced = true)
{
    uint packetFlags;
    assert(!reliable || sequenced, "prepareENetPacket: Invalid flags");
    if (reliable)
        packetFlags |= ENET_PACKET_FLAG_RELIABLE;
    if (!sequenced)
        packetFlags |= ENET_PACKET_FLAG_UNSEQUENCED;
    return enet_packet_create(data.ptr, data.length, packetFlags);
}

///an unconnected network host, representing either server or client
///make sure to call serviceAll() regularly to handle events
class NetHost {
    private int mMaxConnections;
    private ushort mBoundPort;
    private ENetHost* mHost;
    //references to instantiated peers
    //(ENetPeer.data is not enough, the GC could collect it)
    private NetPeer[ENetPeer*] mPeers;
    //reference to NetBase so its destructor won't unload the library until
    //it's really not needed anymore; apart from that it's unused
    private NetBase mBase;

    ///called whenever a new connection is established
    void delegate(NetHost sender, NetPeer peer) onConnect;

    private this(NetBase b, ushort port, int maxConnections, ENetHost* host) {
        mMaxConnections = maxConnections;
        mBoundPort = port;
        mHost = host;
        mBase = b;
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
    NetPeer connect(NetAddress addr, ubyte channelCount) {
        //convert address to ENetAddress
        ENetAddress enaddr;
        enaddr.port = addr.port;
        if (addr.broadcast)
            enaddr.host = ENET_HOST_BROADCAST;
        else
            enet_address_set_host(&enaddr, toStringz(addr.hostName));

        //initiate connection (will not connect until next service() call
        ENetPeer* peer = enet_host_connect(mHost, &enaddr, channelCount);
        if (!peer)
            throw new NetException(
                "Connection attempt failed: No available peers");
        //create the peer class now, to allow to abort connection request
        return getNetPeer(peer);
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

    private NetPeer getNetPeer(ENetPeer* peer) {
        auto ret = cast(NetPeer)peer.data;
        if (!ret) {
            ret = new NetPeer(this, peer);
            peer.data = cast(void*)ret;
            mPeers[peer] = ret;
        }
        return ret;
    }

    private bool handleEvent(inout ENetEvent event) {
        switch (event.type) {
            case ENET_EVENT_TYPE_CONNECT:
                auto peer = getNetPeer(event.peer);
                assert(peer.state != ConnectionState.connected);
                //not sure if possible: don't connect if a disconnect is pending
                if (peer.state == ConnectionState.establish) {
                    peer.handleConnect();
                    if (onConnect)
                        onConnect(this, peer);
                }
                break;
            case ENET_EVENT_TYPE_RECEIVE:
                auto peer = cast(NetPeer)event.peer.data;
                assert(peer !is null);
                //check if peer has no disconnect pending
                if (peer.connected) {
                    ubyte* pdata = event.packet.data;
                    peer.handleReceive(event.channelID,
                        pdata[0..event.packet.dataLength]);
                }
                enet_packet_destroy(event.packet);
                break;
            case ENET_EVENT_TYPE_DISCONNECT:
                auto peer = cast(NetPeer)event.peer.data;
                if (peer) {
                    peer.handleDisconnect(event.data);
                    event.peer.data = null;
                    if (event.peer in mPeers)
                        mPeers.remove(event.peer);
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
    void sendBroadcast(ubyte[] data, ubyte channelId, bool immediate = false,
        bool reliable = true, bool sequenced = true)
    {
        ENetPacket* packet = prepareENetPacket(data, reliable, sequenced);
        //queue packet for send
        enet_host_broadcast(mHost, channelId, packet);
        if (immediate)
            flush();
        //packet will be deallocated by enet
    }
}

enum ConnectionState {
    establish, //connection has been requested, but is not ready to transmit
    connected, //connection is active
    closed,  //connection is closed or has been requested to close
}

///a connection to a peer, created by NetHost when a connection is established
///will be connected after creation, until you get the onDisconnect event
class NetPeer {
    private ENetPeer* mPeer;
    private ConnectionState mState;
    private NetAddress mAddress;
    private NetHost mHost;

    ///called when this peer finishes connecting
    void delegate(NetPeer sender) onConnect;
    ///called when connection has been terminated
    void delegate(NetPeer sender, uint code) onDisconnect;
    void delegate(NetPeer sender, ubyte channelId, ubyte[] data) onReceive;

    private this(NetHost parent, ENetPeer* peer) {
        mHost = parent;
        mPeer = peer;
        mAddress.port = mPeer.address.port;
        char[] addrBuf = new char[16];
        enet_address_get_host_ip(&mPeer.address, addrBuf.ptr, 16);
        mAddress.hostName = fromStringz(addrBuf.ptr);
    }

    ///associated host
    NetHost host() {
        return mHost;
    }

    private void handleConnect() {
        mState = ConnectionState.connected;
        if (onConnect)
            onConnect(this);
    }

    private void handleDisconnect(uint code) {
        mState = ConnectionState.closed;
        if (onDisconnect)
            onDisconnect(this, code);
    }

    private void handleReceive(ubyte channelId, ubyte[] data) {
        if (onReceive)
            onReceive(this, channelId, data);
    }

    ///close the connection
    ///you are guaranteed not to receive packets after this call
    void disconnect(uint code = 0) {
        if (mState == ConnectionState.establish)
            reset();
        else
            enet_peer_disconnect(mPeer, code);
        mState = ConnectionState.closed;
    }

    void reset() {
        enet_peer_reset(mPeer);
        if (mPeer in mHost.mPeers) {
            mHost.mPeers.remove(mPeer);
        }
    }

    ///is this connection active?
    bool connected() {
        return mState == ConnectionState.connected;
    }

    ConnectionState state() {
        return mState;
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
    void send(ubyte[] data, ubyte channelId, bool immediate = false,
        bool reliable = true, bool sequenced = true)
    {
        ENetPacket* packet = prepareENetPacket(data, reliable, sequenced);
        //queue packet for send
        enet_peer_send(mPeer, channelId, packet);
        if (immediate)
            mHost.flush();
        //packet will be deallocated by enet
    }
}

class NetException : CustomException {
    this(char[] msg) {
        super(msg);
    }
}
