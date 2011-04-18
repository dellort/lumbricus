module net.serverlist;

import net.announce;
import net.broadcast;
import net.cmdprotocol;
import net.marshal;
import tango.net.device.Datagram;
import utils.array;
import utils.misc;
import utils.time;
import utils.log;

private LogStruct!("serverlist") log;

//ServerList uses one announcer to maintain an internal list of available
//  servers and query them regularly for ping time and more information
class ServerList {
    //time for query retry
    const cQueryTimeout = timeSecs(8);
    //re-query interval (must be > cQueryTimeout)
    const cSeenTimeout = timeSecs(60);
    //announcer refresh interval (sync announcer's server list with ours)
    //Note: announcers use custom internal refresh times
    const cRefreshInterval = timeSecs(1);
    //don't kill the router and try to get good ping values
    //xxx not sure about a good value (it's only 1 udp packet per server)
    const cMaxQueriesPerSec = 50;

    struct ServerInfo {
        ServerAddress addr;
        Time ping;
        ushort serverVersion;
        QueryResponse info;
        //last time we got a response
        Time lastSeen;
        //time the last query was sent
        private Time lastQuery;
        //update generation number; used to check if servers in ServerList's
        //  internal list are still reported by the announcer
        private uint genNo;

        //xxx considered debug code; it would be much better to display the
        //    servers in some multicolumn-list control, but we don't have that
        string toString() {
            if (lastSeen > Time.Null) {
                if (unsupportedVersion()) {
                    return myformat("{} (version mismatch) [{} ms]",
                        addr.toString(), ping.msecs());
                } else {
                    return myformat("{} ({}/{}) {} [{} ms]", addr.toString(),
                        info.curPlayers, info.maxPlayers,
                        info.serverName, ping.msecs());
                }
            } else {
                //server didn't respond
                return myformat("{} [9999 ms]", addr.toString());
            }
        }

        //true if server's version is different than ours
        bool unsupportedVersion() {
            return serverVersion != cProtocolVersion;
        }

        //send out a query to ask for server details
        private void query(NetBroadcast socket) {
            assert(addr.valid());
            scope dest = new IPv4Address(addr.address, addr.port);
            socket.send(cQueryIdent, dest);
            //store query time (to calculate ping and prevent multiple queries)
            lastQuery = timeCurrentTime();
            log.trace("{} : Query sent at {} ms", addr.toString(),
                lastQuery.msecs);
        }

        //response from server query incoming; returns true if the response
        //  could be successfully parsed
        private bool parseResponse(ubyte[] data) {
            //check ident
            if (data.length > cQueryIdent.length
                && data[0..cQueryIdent.length] == cast(ubyte[])cQueryIdent)
            {
                //unmarshal version and extra information
                scope um = new UnmarshalBuffer(data[2..$]);
                QueryResponse resp;
                try {
                    serverVersion = um.read!(ushort)();
                    //check if server runs a different version of the game
                    //(the query response will still be considered valid though)
                    if (!unsupportedVersion()) {
                        //don't parse QueryResponse if server version is
                        //  different (the contents of the struct may have
                        //  changed)
                        info = um.read!(QueryResponse)();
                    }
                } catch (UnmarshalException e) {
                    return false;
                }
                lastSeen = timeCurrentTime();
                //xxx ping time is a bit off, as we only check for responses
                //    every frame (at 100fps every 10ms)
                ping = lastSeen - lastQuery;
                log.trace("{} : Response at {} ms", addr.toString(),
                    lastSeen.msecs);
                return true;
            }
            return false;
        }

        //mark as seen in current update loop
        private void update(uint genNo) {
            this.genNo = genNo;
        }
        //check if server is still up-to-date
        private bool isUpdated(uint genNo) {
            return this.genNo == genNo;
        }
    }

    //called when servers are added, deleted or updated
    //also called when active is changed
    void delegate(ServerList sender) onChange;

    private {
        NetAnnounceClient mAnnounce;
        NetBroadcast mSocket;
        bool mActive;
        ServerInfo[] mServers;
        Time mLastRefresh, mLastQuery;
        uint mGenNo;
        bool mChanged;
    }

    this(NetAnnounceClient announce) {
        assert(!!announce);
        mAnnounce = announce;
        mSocket = new NetBroadcast(0);
        mSocket.onReceive = &onUdpReceive;
    }

    void close() {
        mAnnounce.close();
        mSocket.close();
        mServers = null;
    }

    ServerInfo[] list() {
        return mServers;
    }

    //find a server in the list by ip+port; returns index or -1 if not found
    //xxx maybe optimize
    private int find(ServerAddress addr) {
        foreach (int idx, ref ServerInfo cur; mServers) {
            if (cur.addr == addr)
                return idx;
        }
        return -1;
    }

    void tick() {
        if (!mActive)
            return;
        mChanged = false;
        updateAnnounce();
        queryServers();
        mSocket.service();
        if (mChanged && onChange) {
            onChange(this);
        }
    }

    private void updateAnnounce() {
        mAnnounce.tick();
        //check announcer list every cRefreshInterval
        if (timeCurrentTime() - mLastRefresh > cRefreshInterval) {
            mLastRefresh = timeCurrentTime();
            foreach (s; mAnnounce) {
                //for every server the announcer gives us, make sure it is
                //in the internal list and set its update generation to current
                int curIdx = find(s);
                if (curIdx < 0) {
                    //it is a new server, append it
                    mServers ~= ServerInfo(s);
                    curIdx = mServers.length - 1;
                    mChanged = true;
                    log.trace("New server {} found", s.toString());
                }
                //mark as updated
                mServers[curIdx].update(mGenNo);
            }
            //check all servers and remove the ones no longer reported by the
            //announcer (announcer controls what servers are available)
            foreach_reverse (int idx, ref s; mServers) {
                if (!s.isUpdated(mGenNo)) {
                    log.trace("Server {} no longer available",
                        s.addr.toString());
                    //keep it ordered (new servers at bottom)
                    arrayRemoveN(mServers, idx);
                    mChanged = true;
                }
            }
            //increase update generation number
            mGenNo++;
        }
    }

    //send query to all servers that have no updated information yet
    private void queryServers() {
        Time t = timeCurrentTime();
        //max queries in current loop
        int maxQueries = cast(int)((t - mLastQuery).secsf * cMaxQueriesPerSec);
        if (maxQueries > 0)
            mLastQuery = t;

        foreach (ref si; mServers) {
            if (maxQueries <= 0)
                break;
            //did not just send a query, and no updated information available
            //hm wtf ulong overflow
            if (si.lastQuery == Time.Null || (t - si.lastQuery > cQueryTimeout
                && (si.lastSeen == Time.Null || t - si.lastSeen > cSeenTimeout)))
            {
                si.query(mSocket);
                maxQueries--;
            }
        }
    }

    private void onUdpReceive(NetBroadcast sender, ubyte[] data,
        IPv4Address from)
    {
        //got udp packet, see if it came from a server in the list
        int idx = find(ServerAddress(from.addr, from.port));
        if (idx >= 0) {
            if (mServers[idx].parseResponse(data))
                mChanged = true;
        }
    }

    //active flag will be passed to announcer
    void active(bool act) {
        mActive = act;
        mLastQuery = timeCurrentTime();
        mAnnounce.active = act;
        mServers = null;
        if (onChange) {
            onChange(this);
        }
    }
    bool active() {
        return mActive;
    }

    //refresh announcer and query info
    //does not clear internal server list (no point in doing that, would only
    //  annoy the user)
    void refreshAll() {
        //update announcer
        mAnnounce.active = false;
        mAnnounce.active = mActive;
        refreshInfo();
    }

    //refresh query info of available servers
    void refreshInfo() {
        foreach (ref s; mServers) {
            //schedule re-query (will send on next tick)
            s.lastQuery = Time.Null;
        }
    }
}
