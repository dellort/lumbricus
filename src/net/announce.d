module net.announce;

import utils.misc;
import utils.configfile;
import utils.factory;
import utils.time;

import tango.util.Convert;

///Filled by the server, will be transmitted to clients via announcer
struct AnnounceInfo {
    char[] serverName;
    ushort port;
    int curPlayers;
    int maxPlayers;
}

///Interface for servers to announce over various methods
class NetAnnounce {
    private {
        NetAnnouncer[] mAnnouncers;
        bool mActive;
        bool mInternet;
    }

    ///cfg contains multiple announcer configurations, e.g.
    ///  irc { ... }  php { ... }  lan { ... }
    this(ConfigNode cfg) {
        foreach (ConfigNode sub; cfg) {
            mAnnouncers ~= AnnouncerFactory.instantiate(sub.name, sub);
        }
    }

    ~this() {
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
    void tick();

    void update(AnnounceInfo info);

    void active(bool act);

    bool isInternet();

    void close();
}

alias StaticFactory!("Announcers", NetAnnouncer, ConfigNode) AnnouncerFactory;



struct ServerInfo {
    char[] address;
    AnnounceInfo info;
}

///Client part of announcer
abstract class NetAnnounceClient {
    void tick();

    ///loop over internal server list
    ///behavior is implementation-specific, but it should be implemented to
    ///block as short as possible (best not at all)
    int opApply(int delegate(ref ServerInfo) del);

    ///Client starts inactive
    void active(bool act);
    bool active();

    void close();
}

//Abstract base class for announcer clients that receive updates about
//single servers periodically
abstract class NACPeriodically : NetAnnounceClient {
    private {
        Time mServerTimeout = timeSecs(45);
        MyServerInfo[char[]] mServers;
        struct MyServerInfo {
            Time lastSeen;
            ServerInfo info;
        }
    }

    //Returns the current internal server list, and also checks if server
    //entries have timed out
    int opApply(int delegate(ref ServerInfo) del) {
        Time t = timeCurrentTime();
        char[][] invalid;
        foreach (char[] key, ref MyServerInfo srv; mServers) {
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
        foreach (char[] i; invalid) {
            mServers.remove(i);
        }
        return 0;
    }

    protected void refreshServer(char[] addr, ref AnnounceInfo info,
        char[] id = null)
    {
        if (id.length == 0)
            id = addr ~ to!(char[])(info.port);
        //Servers are identified by hostname and port
        MyServerInfo* srv = id in mServers;
        if (!srv) {
            mServers[id] = MyServerInfo();
            srv = id in mServers;
        }
        srv.lastSeen = timeCurrentTime();
        srv.info.address = addr;
        srv.info.info = info;
    }
}

alias StaticFactory!("AnnounceClients", NetAnnounceClient,
    ConfigNode) AnnounceClientFactory;
