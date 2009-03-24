module net.broadcast;

import derelict.enet.enet;
import tango.stdc.stringz;

//sorry for that (->no converting the address to string and back just for reply)
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
