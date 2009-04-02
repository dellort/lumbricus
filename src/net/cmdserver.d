module net.cmdnet;

import common.common;
import common.task;
import gui.label;
import gui.widget;
import gui.wm;
import game.gamepublic;
import game.setup;
import net.cmdprotocol;
import net.netlayer;
import utils.configfile;
import utils.time;
import utils.list2;

import tango.core.Thread;
import tango.io.Stdout;

class CmdNetServer : Thread {
    private {
        GameConfig mConfig;
        ushort mPort;
        int mMaxPlayers, mPlayerCount;
        char[] mServerName;
        List2!(CmdNetClientConnection) mClients;
        bool mClose;

        NetBase mBase;
        NetHost mHost;
    }

    //create the server thread object
    //to actually run the server, call CmdNetServer.start()
    this(GameConfig cfg, ConfigNode serverConfig) {
        super(&run);
        mConfig = cfg;
        mConfig.teams = null;

        mClients = new typeof(mClients);

        mPort = serverConfig.getValue("port", 12499);
        mServerName = serverConfig["name"];
        if (mServerName.length == 0)
            mServerName = "Unnamed server";
        mMaxPlayers = serverConfig.getValue("max_players", 4);
    }

    //shutdown the server (delayed)
    void close() {
        mClose = true;
    }

    int playerCount() {
        return mPlayerCount;
    }

    //main thread function
    private void run() {
        //create and open server
        mBase = new NetBase();
        mHost = mBase.createServer(mPort, mMaxPlayers);
        mHost.onConnect = &onConnect;

        try {

        while (!mClose) {
            //check for messages
            mHost.serviceAll();
            foreach (cl; mClients) {
                cl.tick();
            }
            yield();
        }

        } catch (Exception e) {
            //seems this is the only way to be notified about thread errors
            Stdout(e.toString()).newline;
        }

        //shutdown
        foreach (cl; mClients) {
            cl.closeWithReason("server_shutdown");
        }
        delete mHost;
        delete mBase;
    }

    //new client is trying to connect
    private void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        auto cl = new CmdNetClientConnection(this, peer);
        cl.client_node = mClients.add(cl);
        mPlayerCount++;
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientDisconnect(CmdNetClientConnection client) {
        mClients.remove(client.client_node);
        mPlayerCount--;
    }
}

//peer connection state for CmdNetClientConnection
private enum ClientState {
    waitForHello,
    authenticate,
    lobby,
    loading,
    playing,
}

//Represents a connected client, also accepts/rejects connection attempts
private class CmdNetClientConnection {
    private {
        ListNode client_node;
        CmdNetServer mOwner;
        NetPeer mPeer;
        ClientState mState;
        Time mStateEnter;
    }

    this(CmdNetServer owner, NetPeer peer) {
        assert(!!peer);
        mOwner = owner;
        mPeer = peer;
        mPeer.onDisconnect = &onDisconnect;
        mPeer.onReceive = &onReceive;
        state(ClientState.waitForHello);
    }

    void close() {
        mPeer.disconnect();
    }

    void closeWithReason(char[] error) {
        send(ServerPacket.error, error, 0, true);
        close();
    }

    //enter a new state, and reset timer
    private void state(ClientState newState) {
        mState = newState;
        mStateEnter = timeCurrentTime();
    }

    private void send(ServerPacket pid, void[] data, ubyte channelId = 0,
        bool now = false)
    {
        ubyte[] buf = new ubyte[data.length + 4];
        *(cast(uint*)buf.ptr) = ServerPacket.error;
        buf[4..$] = cast(ubyte[])data;
        mPeer.send(buf.ptr, buf.length, channelId, now);
        delete buf;
    }

    void tick() {
        Time t = timeCurrentTime();
        switch (mState) {
            case ClientState.authenticate:
            case ClientState.waitForHello:
                //only allow clients to stay 5secs in wait/auth states
                if (t - mStateEnter > timeSecs(5)) {
                    closeWithReason("error_timeout");
                }
                break;
            default:
        }
    }

    private void receive(ubyte channelId, ClientPacket pid, void[] data) {
    }

    //NetPeer.onReceive
    private void onReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        //packet structure: 4 bytes message id + data
        if (dataLen < 4)
            return;
        ClientPacket pid = *(cast(ClientPacket*)data);
        data += 4;
        void[] d;
        if (dataLen > 4)
            d = data[0..dataLen-4];
        receive(channelId, pid, d);
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender) {
        assert(sender is mPeer);
        mOwner.clientDisconnect(this);
    }
}


class CmdNetServerTask : Task {
    private {
        CmdNetServer mServer;
        Label mLabel;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        ConfigNode node = gConf.loadConfig("newgame");
        auto srvConf = gConf.loadConfigDef("server");
        mServer = new CmdNetServer(loadGameConfig(node), srvConf);

        mLabel = new Label();
        gWindowManager.createWindow(this, mLabel, "Server");

        mServer.start();
    }

    override protected void onKill() {
        mServer.close();
    }

    override protected void onFrame() {
        mLabel.text = myformat("Clients: {}", mServer.playerCount);
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdserver");
    }
}
