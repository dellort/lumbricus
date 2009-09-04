module net.broadcast;

version = BCTango;
//version = BCEnet;

version(BCTango) {

import tango.net.device.Socket;
import tango.net.device.Berkeley; //????!!! lol tango
import net.iflist;

//fix for tango svn... sorry, I have no fucking idea
version(Win32) {
    import tango.sys.win32.WsaSock : timeval;
}
version(linux) {
    import tango.stdc.posix.sys.time;
}

//sorry for that (->no converting the address to string and back just for reply)
alias IPv4Address BCAddress;

class NetBroadcast {
    private {
        const cBufSize = 1024;
        ubyte[cBufSize] mBuffer;

        ushort mPort;
        bool mServer;
        Socket mSocket;
        IPv4Address[] mAddresses;
    }

    void delegate(NetBroadcast sender, ubyte[] data, BCAddress from) onReceive;

    package this(ushort port, bool server = false) {
        mServer = server;
        mPort = port;
        //setup broadcast addresses for all network interfaces
        //see comment in sendBC() for explanation
        char[][] interfaces = getBroadcastInterfaces();
        foreach (addr; interfaces) {
            mAddresses ~= new IPv4Address(addr, mPort);
        }
        mSocket = new Socket(AddressFamily.INET, SocketType.DGRAM,
            ProtocolType.UDP);
        if (server) {
            //multiple servers on same port
            mSocket.native.setAddressReuse(true);
            mSocket.bind(new IPv4Address(port));
        } //else {
            int[1] i = 1;
            mSocket.native.setOption(SocketOptionLevel.SOCKET,
                SocketOption.BROADCAST, i);
        //}
    }

    void service() {
        if (!mSocket)
            return;
        //xxx: SocketSet allocates some memory, but it's left to the GC...
        //     this causes about 10 GC cycles per second when broadcasting
        scope ssread = new SocketSet();
        ssread.add(mSocket.native);
        //no blocking
        timeval tv = timeval(0, 0);
        int sl = SocketSet.select(ssread, null, null, &tv);
        if (sl > 0 && ssread.isSet(mSocket.native)) {
            serviceOne();
        }
    }

    //get one message (blocking)
    void serviceOne() {
        if (!mSocket)
            return;
        auto from = new IPv4Address(666); //?!?!?!?214ghosevgtyi3hi8
        int len = mSocket.native.receiveFrom(mBuffer, from);
        if (len > 0 && len < cBufSize && onReceive)
            onReceive(this, mBuffer[0..len], from);
    }

    //send message (in reply to onReceive)
    void send(ubyte[] data, BCAddress dest) {
        if (!mSocket)
            return;
        mSocket.native.sendTo(data, dest);
    }

    //broadcast message
    void sendBC(ubyte[] data) {
        if (!mSocket)
            return;
        assert(data.length <= cBufSize);
        //hope you don't mind -- assert(!mServer, "Client only");
        //Broadcast the message on all available interface
        //This mess is only needed because broadcasting on 255.255.255.255 will
        //  set the sender address to the first interface, and packets on other
        //  interfaces will contain the wrong sender address
        foreach (addr; mAddresses) {
            mSocket.native.sendTo(data, addr);
        }
    }

    char[] getIP(BCAddress addr) {
        return addr.toAddrString();
    }

    void close() {
        mSocket.detach();
        mSocket = null;
    }
}

}

version(BCEnet) {

import derelict.enet.enet;
import tango.stdc.stringz;

alias ENetAddress BCAddress;

class NetBroadcast {
    private {
        //fixed buffer size (larger values could cause errors because of split
        //  messages)
        const cBufSize = 1024;

        ENetSocket mSock;
        ubyte[cBufSize] mBuffer;
        ushort mPort;
        bool mServer;
    }

    void delegate(NetBroadcast sender, ubyte[] data, BCAddress from) onReceive;

    package this(ushort port, bool server = false) {
        mServer = server;
        mPort = port;
        ENetAddress addr;
        addr.host = ENET_HOST_ANY;
        addr.port = port;
        if (server) {
            //create server
            //xxx set SO_REUSEADDR socket option, to allow multiple servers
            //    on one machine
            mSock = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM, &addr);
        } else {
            //create client
            //xxx should be unbound socket (not possible with enet afaik)
            mSock = enet_socket_create(ENET_SOCKET_TYPE_DATAGRAM, null);
            enet_socket_set_option(mSock, ENET_SOCKOPT_BROADCAST, 1);
        }
        if (mSock == ENET_SOCKET_NULL)
            throw new Exception("CreateSocket failed.");
        //Nonblocking mode? well, not for now
        //enet_socket_set_option(mSock, ENET_SOCKOPT_NONBLOCK, 1);
    }

    ///Check for messages (will not block if none available)
    void service() {
        uint cond = ENET_SOCKET_WAIT_RECEIVE;
        int ret = enet_socket_wait(mSock, &cond, 0);
        while (ret >= 0 && (cond & ENET_SOCKET_WAIT_RECEIVE)) {
            serviceOne();
            cond = ENET_SOCKET_WAIT_RECEIVE;
            ret = enet_socket_wait(mSock, &cond, 0);
        }
    }

    ///Wait for a message
    void serviceOne() {
        ENetAddress addr;
        ENetBuffer buf;
        buf.data = mBuffer.ptr;
        buf.dataLength = mBuffer.length;
        int len = enet_socket_receive(mSock, &addr, &buf, 1);
        if (len > 0 && len < cBufSize && onReceive)
            onReceive(this, mBuffer[0..len], addr);
    }

    ///Send message to a fixed address
    ///Normally used server-side as reply to onReceive event
    void send(ubyte[] data, BCAddress dest) {
        assert(data.length <= cBufSize);
        ENetBuffer buf;
        buf.data = data.ptr;
        buf.dataLength = data.length;
        enet_socket_send(mSock, &dest, &buf, 1);
    }

    ///Client only: Broadcast a message in LAN
    void sendBC(ubyte[] data) {
        assert(data.length <= cBufSize);
        assert(!mServer, "Client only");
        ENetAddress dest;
        dest.host = ENET_HOST_BROADCAST;
        dest.port = mPort;
        ENetBuffer buf;
        buf.data = data.ptr;
        buf.dataLength = data.length;
        enet_socket_send(mSock, &dest, &buf, 1);
    }

    ///Decode internal address to string IP (x.x.x.x)
    char[] getIP(BCAddress addr) {
        char[] addrBuf = new char[16];
        enet_address_get_host_ip(&addr, addrBuf.ptr, 16);
        return fromStringz(addrBuf.ptr);
    }

    ///Close socket
    void close() {
        enet_socket_destroy(mSock);
    }
}

}
