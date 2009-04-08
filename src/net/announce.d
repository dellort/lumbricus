module net.announce;

import utils.misc;
import utils.configfile;
import utils.factory;

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

    ///NetAnnounce starts inactive; true to announce, false to stop
    void active(bool act) {
        if (mActive != act) {
            mActive = act;
            foreach (a; mAnnouncers) {
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

alias StaticFactory!("AnnounceClients", NetAnnounceClient,
    ConfigNode) AnnounceClientFactory;
