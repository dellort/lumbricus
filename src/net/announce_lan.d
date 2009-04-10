module net.announce_lan;

import net.announce;
import net.broadcast;
import net.netlayer;
import net.marshal;
import utils.random;
import utils.time;
import utils.configfile;

import tango.util.Convert;

//How this works:
//  Servers will broadcast an update packet with their info every
//  cBroadcastInterval. Clients listen for those packets and assemble a
//  list of servers active within some time

//default broadcast port, can be changed by configfile
const cDefBroadcastPort = 20610;
//how often servers send updates
const cBroadcastInterval = timeSecs(1);

class LanAnnouncer : NetAnnouncer {
    private {
        bool mActive;
        NetBase mBase;
        NetBroadcast mBroadcast;
        Time mLastTime;
        AnnounceInfo mInfo;
        ushort mPort;
    }

    this(ConfigNode cfg) {
        mPort = cfg.getValue("port", cDefBroadcastPort);
        mBase = new NetBase();
        //strangely, the server creates a broadcast client (for sending updates)
        mBroadcast = mBase.createBroadcast(mPort, false);
        mLastTime = timeCurrentTime() - cBroadcastInterval;
    }

    void tick() {
        Time t = timeCurrentTime();
        if (mActive && t - mLastTime > cBroadcastInterval && mInfo.port > 0) {
            scope m = new MarshalBuffer();
            m.write(mInfo);
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
        delete mBase;
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
        delete mBase;
    }

    private void bcReceive(NetBroadcast sender, ubyte[] data, BCAddress from) {
        //server announce packet incoming
        scope um = new UnmarshalBuffer(data);
        auto ai = um.read!(AnnounceInfo)();  //xxx error checking
        char[] addr = mBroadcast.getIP(from);

        refreshServer(addr, ai);
    }

    static this() {
        AnnounceClientFactory.register!(typeof(this))("lan");
    }
}
