module net.announce_lan;

import net.announce;
import net.broadcast;
import net.netlayer;
import net.marshal;
import utils.random;
import utils.time;
import utils.configfile;
import utils.misc;

import tango.util.Convert;

//How this works:
//  Servers will broadcast an update packet with their info every
//  cBroadcastInterval. Clients listen for those packets and assemble a
//  list of servers active within some time

//default broadcast port, can be changed by configfile
const cDefBroadcastPort = 20610;
//how often servers send updates
const cBroadcastInterval = timeSecs(15);

enum BroadcastMessage : ubyte {
    announceServer,     //a server is announcing itself
    requestAnnounces,   //a client asks for announceServer messages
}

class LanAnnouncer : NetAnnouncer {
    private {
        bool mActive;
        NetBase mBase;
        NetBroadcast mBroadcast;
        Time mLastTime;
        AnnounceInfo mInfo;
        ushort mPort;
        uint mId;
    }

    this(ConfigNode cfg) {
        mPort = cfg.getValue("port", cDefBroadcastPort);
        mBase = new NetBase();
        //strangely, the server creates a broadcast client (for sending updates)
        //...and listens to requestAnnounces broadcast packets
        mBroadcast = mBase.createBroadcast(mPort, true);
        mBroadcast.onReceive = &bcReceive;
        mLastTime = timeCurrentTime() - cBroadcastInterval;
        mId = rngShared.next();
    }

    bool isInternet() {
        return false;
    }

    void tick() {
        Time t = timeCurrentTime();
        if (t - mLastTime > cBroadcastInterval) {
            do_update();
        }
        mBroadcast.service();
    }

    void do_update() {
        mLastTime = timeCurrentTime();

        if (!(mActive && mInfo.port > 0))
            return;

        scope m = new MarshalBuffer();
        m.write!(BroadcastMessage)(BroadcastMessage.announceServer);
        //bc packets may be reaching the client over multiple routes,
        //  so add an id to identify the server
        m.write(mId);
        m.write(mInfo);
        //broadcast an info packet
        mBroadcast.sendBC(m.data());
        mBroadcast.service();
    }

    void update(AnnounceInfo info) {
        if (mInfo == info)
            return;
        mInfo = info;
        do_update();
    }

    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;
        do_update();
    }

    void close() {
        mBroadcast.close();
        delete mBase;
    }

    private void bcReceive(NetBroadcast sender, ubyte[] data, BCAddress from) {
        scope um = new UnmarshalBuffer(data);
        if (um.read!(BroadcastMessage)() == BroadcastMessage.requestAnnounces) {
            do_update();
        }
    }

    static this() {
        AnnouncerFactory.register!(typeof(this))("lan");
    }
}

class LanAnnounceClient : NACPeriodically {
    private {
        bool mActive;
        NetBase mBase;
        NetBroadcast mBroadcast;
        ushort mPort;
    }

    this(ConfigNode cfg) {
        mPort = cfg.getValue("port", cDefBroadcastPort);
        mBase = new NetBase();
        //client announcer creates a server to listen for broadcast packets
        mBroadcast = mBase.createBroadcast(mPort, true);
        mBroadcast.onReceive = &bcReceive;
        //--- REALLY THANKS mServerTimeout = timeSecs(3);
    }

    void tick() {
        if (mActive) {
            mBroadcast.service();
        }
    }

    ///Client starts inactive
    void active(bool act) {
        if (act == mActive)
            return;
        mActive = act;

        if (mActive) {
            //broadcast request message to lower latency
            scope m = new MarshalBuffer();
            m.write!(BroadcastMessage)(BroadcastMessage.requestAnnounces);
            mBroadcast.sendBC(m.data());
        }
    }
    bool active() {
        return mActive;
    }

    void close() {
        mBroadcast.close();
        delete mBase;
    }

    private void bcReceive(NetBroadcast sender, ubyte[] data, BCAddress from) {
        //server announce packet incoming
        scope um = new UnmarshalBuffer(data);
        auto msg = um.read!(BroadcastMessage)();
        if (msg != BroadcastMessage.announceServer)
            return;
        uint id = um.read!(uint)();
        auto ai = um.read!(AnnounceInfo)();  //xxx error checking
        char[] addr = mBroadcast.getIP(from);

        refreshServer(addr, ai, to!(char[])(id));
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("lan");
    }
}
