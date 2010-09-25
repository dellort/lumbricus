module net.broadcast;

import tango.net.device.Socket;
import tango.net.device.Berkeley; //????!!! lol tango
import net.iflist;

///broadcast server or client; can also be "misused" as a generic nonblocking
///  udp server/client
///maximum message size is 1kb
class NetBroadcast {
    private {
        const cBufSize = 1024;
        ubyte[cBufSize] mBuffer;

        ushort mPort;
        bool mServer;
        Socket mSocket;
        IPv4Address[] mAddresses;
        IPv4Address mFrom;
    }

    //from address will be reused, copy it out if you need it after this call
    void delegate(NetBroadcast sender, ubyte[] data,
        IPv4Address from) onReceive;

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
            mSocket.native.addressReuse = true;
            mSocket.bind(new IPv4Address(port));
        }
        mSocket.native.blocking = false;

        //activate broadcasting (doesn't hurt to do this for the server)
        int[1] i = 1;
        mSocket.native.setOption(SocketOptionLevel.SOCKET,
            SocketOption.BROADCAST, i);

        mFrom = new IPv4Address(666); //?!?!?!?214ghosevgtyi3hi8
    }

    //check for messages (non-blocking); calls onReceive
    void service() {
        if (!mSocket)
            return;
        int len;
        while ((len = mSocket.native.receiveFrom(mBuffer, mFrom)) > 0) {
            onReceive(this, mBuffer[0..len], mFrom);
        }
    }

    //send message (in reply to onReceive)
    void send(ubyte[] data, IPv4Address dest) {
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

    void close() {
        mSocket.detach();
        mSocket = null;
    }
}
