module net.announce_lan;

import net.announce;
import net.broadcast;
import net.marshal;
import utils.random;
import utils.time;
import utils.configfile;

import tango.net.device.Berkeley : IPv4Address;
import tango.util.Convert;

//How this works:
//  Servers will broadcast an update packet with their info every
//  cBroadcastInterval. Clients listen for those packets and assemble a
//  list of servers active within some time
//Note that there's no 'remove' packet, server's automatically timeout after 3s

//Broadcast traffic: One packet per second is broadcasted by the server
//   --> (marshalled AnnounceInfo + 4) bytes/sec + udp overhead

//default broadcast port, can be changed by configfile
enum cDefBroadcastPort = 20610;
//how often servers send updates
//Note that this also sets how up-to-date the client's information about the
//   server (e.g. current player count) is
enum cBroadcastInterval = timeSecs(1);

class LanAnnouncer : NetAnnouncer {
    private {
        bool mActive;
        NetBroadcast mBroadcast;
        Time mLastTime;
        AnnounceInfo mInfo;
        ushort mPort;
        uint mId;
    }

    this(ConfigNode cfg) {
        mPort = cfg.getValue("port", cDefBroadcastPort);
        //the (game) server creates a broadcast client (for sending updates)
        mBroadcast = new NetBroadcast(mPort, false);
        mLastTime = timeCurrentTime() - cBroadcastInterval;
        mId = rngShared.next();
    }

    bool isInternet() {
        return false;
    }

    void tick() {
        Time t = timeCurrentTime();
        if (mActive && t - mLastTime > cBroadcastInterval && mInfo.port > 0) {
            scope m = new MarshalBuffer();
            //bc packets may be reaching the client over multiple routes,
            //  so add an id to identify the server
            m.write(mId);
            m.write(mInfo.port);
            //broadcast an info packet
            mBroadcast.sendBC(m.data());
            mLastTime = t;
        }
        mBroadcast.service();
    }

    void update(AnnounceInfo info) {
        mInfo = info;
    }

    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
    }

    void close() {
        mBroadcast.close();
    }

    static this() {
        AnnouncerFactory.register!(typeof(this))("lan");
    }
}

//The LAN announce client listens for the server's broadcast packets,
//  and will recognize all servers as active that send one packet atleast
//  every 3 seconds

class LanAnnounceClient : NACPeriodically {
    private {
        bool mActive;
        NetBroadcast mBroadcast;
        ushort mPort;
    }

    this(ConfigNode cfg) {
        mPort = cfg.getValue("port", cDefBroadcastPort);
        //client announcer creates a server to listen for broadcast packets
        mBroadcast = new NetBroadcast(mPort, true);
        mBroadcast.onReceive = &bcReceive;
        mServerTimeout = timeSecs(3);
    }

    void tick() {
        if (mActive)
            mBroadcast.service();
    }

    ///Client starts inactive
    void active(bool act) {
        mActive = act;
    }
    bool active() {
        return mActive;
    }

    void close() {
        mBroadcast.close();
    }

    private void bcReceive(NetBroadcast sender, ubyte[] data,
        IPv4Address from)
    {
        //server announce packet incoming
        scope um = new UnmarshalBuffer(data);
        try {
            uint id = um.read!(uint)();
            ushort port = um.read!(ushort)();

            //make id even more unique
            refreshServer(from.addr, port, ((cast(ulong)id) << 16) | port);
        } catch (UnmarshalException e) {
            //invalid packet, ignore
        }
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("lan");
    }
}
