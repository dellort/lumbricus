module net.announce;

import net.netlayer;
import tango.net.device.Berkeley;
import utils.misc;
import utils.configfile;
import utils.factory;
import utils.time;

import tango.util.Convert;

///Filled by the server, will be transmitted to clients via announcer
struct AnnounceInfo {
    ushort port;
}

///Interface for servers to announce over various methods
class NetAnnounce {
    private {
        NetAnnouncer[] mAnnouncers;
        bool mActive;
        bool mInternet = true;
    }

    ///cfg contains multiple announcer configurations, e.g.
    ///  irc { ... }  php { ... }  lan { ... }
    this(ConfigNode cfg) {
        foreach (ConfigNode sub; cfg) {
            mAnnouncers ~= AnnouncerFactory.instantiate(sub.name, sub);
        }
    }

    void close() {
        active = false;
        foreach (a; mAnnouncers) {
            a.close();
        }
    }

    void announceInternet(bool ann_int) {
        mInternet = ann_int;
        active = mActive;
    }

    ///NetAnnounce starts inactive; true to announce, false to stop
    void active(bool act) {
        mActive = act;
        foreach (a; mAnnouncers) {
            if (act && !mInternet && a.isInternet()) {
                a.active = false;
            } else {
                a.active = act;
            }
        }
    }
    bool active() {
        return mActive;
    }

    void tick() {
        if (!mActive)
            return;
        foreach (a; mAnnouncers) {
            a.tick();
        }
    }

    void update(ref AnnounceInfo info) {
        foreach (a; mAnnouncers) {
            a.update(info);
        }
    }
}

///Server part of announcer
abstract class NetAnnouncer {
abstract:
    void tick();

    void update(AnnounceInfo info);

    void active(bool act);

    bool isInternet();

    void close();
}

alias StaticFactory!("Announcers", NetAnnouncer, ConfigNode) AnnouncerFactory;



struct ServerAddress {
    //ip address, host order
    uint address = IPv4Address.ADDR_NONE;
    ushort port = 0;

    string toString() {
        return myformat("{}.{}.{}.{}:{}", address >> 24 & 0xFF,
            address >> 16 & 0xFF, address >> 8 & 0xFF, address & 0xFF, port);
    }

    bool parse(string addr) {
        auto tmp = NetAddress(addr);
        port = tmp.port;
        address = IPv4Address.parse(tmp.hostName);
        return valid();
    }

    bool valid() {
        return address != IPv4Address.ADDR_NONE && port > 0;
    }
}

///Client part of announcer
abstract class NetAnnounceClient {
abstract:
    void tick();

    ///loop over internal server list
    ///behavior is implementation-specific, but it should be implemented to
    ///block as short as possible (best not at all)
    int opApply(int delegate(ref ServerAddress) del);

    ///Client starts inactive
    ///by definition, setting active from false to true will cause an announce
    ///  query to be sent (if supported and not being flooded)
    ///server list will not be cleared if act == false
    void active(bool act);
    bool active();

    void close();
}

//Abstract base class for announcer clients that receive updates about
//single servers periodically
//(a server not sending an update for mServerTimeout is removed from the list)
abstract class NACPeriodically : NetAnnounceClient {
    private {
        MyServerInfo[ulong] mServers;
        struct MyServerInfo {
            ServerAddress info;
            Time lastSeen;
        }
    }
    //derived classes may change this for custom server timeout
    protected Time mServerTimeout = timeSecs(45);

    //Returns the current internal server list, and also checks if server
    //entries have timed out
    int opApply(int delegate(ref ServerAddress) del) {
        Time t = timeCurrentTime();
        ulong[] invalid;
        foreach (ulong key, ref MyServerInfo srv; mServers) {
            //check for timeout
            //xxx monitor disconnect messages for more accurate info
            if (t - srv.lastSeen > mServerTimeout) {
                invalid ~= key;
            } else {
                auto res = del(srv.info);
                if (res)
                    return res;
            }
        }
        //remove timed-out servers
        foreach (ulong i; invalid) {
            mServers.remove(i);
        }
        return 0;
    }

    protected void refreshServer(uint addr, ushort port, ulong id = 0) {
        if (id == 0)
            id = ((cast(ulong)addr) << 16) | port;
        //Servers are identified by hostname and port
        MyServerInfo* srv = id in mServers;
        if (!srv) {
            mServers[id] = MyServerInfo.init;
            srv = id in mServers;
        }
        srv.lastSeen = timeCurrentTime();
        srv.info.address = addr;
        srv.info.port = port;
    }
}

alias StaticFactory!("AnnounceClients", NetAnnounceClient,
    ConfigNode) AnnounceClientFactory;
