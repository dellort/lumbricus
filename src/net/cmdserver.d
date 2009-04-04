module net.cmdserver;

import common.common;
import common.task;
import framework.commandline;
import gui.label;
import gui.widget;
import gui.wm;
import game.gamepublic;
import game.setup;
import net.cmdprotocol;
import net.netlayer;
import net.marshal;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;

import tango.core.Thread;
import tango.io.Stdout : Stdout;

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
                if (cl.state == ClientState.closed) {
                    clientRemove(cl);
                } else {
                    cl.tick();
                }
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

    private bool checkNewNick(char[] nick) {
        //no empty nicks, minimum length 3
        if (nick.length < 3)
            return false;
        //xxx check for invalid chars (e.g. space)
        //check for names already in use
        foreach (cl; mClients) {
            if (cl.state != ClientState.establish && cl.playerName == nick) {
                return false;
            }
        }
        return true;
    }

    //new client is trying to connect
    private void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        auto cl = new CmdNetClientConnection(this, peer);
        cl.client_node = mClients.add(cl);
        mPlayerCount++;
    }

    //called from CmdNetClientConnection: peer has been disconnected
    private void clientRemove(CmdNetClientConnection client) {
        Stdout.formatln("Client from {} ({}) disconnected",
            client.address.hostName, client.playerName);
        mClients.remove(client.client_node);
        mPlayerCount--;
    }

    private void ccStartGame(CmdNetClientConnection client) {
        throw new CCError("Not implemented");
    }
}

class CCError : Exception {
    this(char[] msg) { super(msg); }
}

//peer connection state for CmdNetClientConnection
private enum ClientState {
    establish,
    authenticate,
    connected,
    closed,
}

//Represents a connected client, also accepts/rejects connection attempts
private class CmdNetClientConnection {
    private {
        ListNode client_node;
        CmdNetServer mOwner;
        NetPeer mPeer;
        ClientState mState;
        Time mStateEnter;
        char[] mPlayerName;
        CommandBucket mCmds;
        CommandLine mCmd;
        StringOutput mCmdOutBuffer;
    }

    this(CmdNetServer owner, NetPeer peer) {
        assert(!!peer);
        mOwner = owner;
        mPeer = peer;
        mPeer.onDisconnect = &onDisconnect;
        mPeer.onReceive = &onReceive;
        mCmdOutBuffer = new StringOutput();
        state(ClientState.establish);
        Stdout.formatln("New connection from {}", address.hostName);
    }

    private void initCmds() {
        mCmd = new CommandLine(globals.defaultOut);
        mCmds = new CommandBucket();
        mCmds.register(Command("start", &cmdStart, "-"));
        mCmds.bind(mCmd);
    }

    //for now, anyone can type start to run the game
    private void cmdStart(MyBox[] params, Output o) {
        mOwner.ccStartGame(this);
    }

    NetAddress address() {
        return mPeer.address();
    }

    void close() {
        mPeer.disconnect();
    }

    void closeWithReason(char[] errorCode, char[][] args = null) {
        SPError p;
        p.errMsg = errorCode;
        p.args = args;
        send(ServerPacket.error, p, 0, true);
        close();
    }

    //enter a new state, and reset timer
    private void state(ClientState newState) {
        mState = newState;
        mStateEnter = timeCurrentTime();
        switch (newState) {
            case ClientState.connected:
                initCmds();
                break;
            default:
        }
    }

    ClientState state() {
        return mState;
    }

    char[] playerName() {
        return mPlayerName;
    }

    void tick() {
        Time t = timeCurrentTime();
        switch (mState) {
            case ClientState.authenticate:
            case ClientState.establish:
                //only allow clients to stay 5secs in wait/auth states
                if (t - mStateEnter > timeSecs(5)) {
                    closeWithReason("error_timeout");
                }
                break;
            default:
        }
    }

    private void send(T)(ServerPacket pid, T data, ubyte channelId = 0,
        bool now = false)
    {
        scope marshal = new MarshalBuffer();
        marshal.write(pid);
        marshal.write(data);
        ubyte[] buf = marshal.data();
        mPeer.send(buf.ptr, buf.length, channelId, now);
    }

    //incoming client packet, all data (including id) is in unmarshal buffer
    private void receive(ubyte channelId, UnmarshalBuffer unmarshal) {
        auto pid = unmarshal.read!(ClientPacket)();

        switch (pid) {
            case ClientPacket.error:
                auto p = unmarshal.read!(CPError)();
                Stdout.formatln("Client reported error: {}", p.errMsg);
                close();
                break;
            case ClientPacket.hello:
                //this is the first packet a client should send after connecting
                if (mState != ClientState.establish) {
                    closeWithReason("error_protocol");
                    return;
                }
                auto p = unmarshal.read!(CPHello)();
                //check version
                if (p.protocolVersion != cProtocolVersion) {
                    closeWithReason("error_wrongversion");
                    return;
                }
                //verify nickname and connect player
                if (!mOwner.checkNewNick(p.playerName)) {
                    closeWithReason("error_invalidnick");
                    return;
                }
                mPlayerName = p.playerName;
                //xxx no authentication for now
                state(ClientState.connected);
                break;
            case ClientPacket.lobbyCmd:
                //client issued a command into the server console
                if (mState != ClientState.connected) {
                    closeWithReason("error_protocol");
                    return;
                }
                auto p = unmarshal.read!(CPLobbyCmd)();
                SPCmdResult p_res;
                try {
                    //execute and buffer output
                    mCmdOutBuffer.text = "";
                    mCmd.execute(p.cmd);
                    p_res.success = true;
                    p_res.msg = mCmdOutBuffer.text;
                } catch (CCError e) {
                    //on fatal errors (e.g. wrong state), commands will
                    //  throw CCError; all command output is discarded
                    p_res.success = false;
                    p_res.msg = "Error: " ~ e.msg;
                }
                //transmit command result
                send(ServerPacket.cmdResult, p_res);
                break;
            default:
                //we have reliable networking, so the client did something wrong
                closeWithReason("error_protocol");
        }
    }

    //NetPeer.onReceive
    private void onReceive(NetPeer sender, ubyte channelId, ubyte* data,
        size_t dataLen)
    {
        assert(sender is mPeer);
        try {
            //packet structure: 2 bytes message id + data
            if (dataLen < 2) {
                closeWithReason("error_protocol");
                return;
            }
            scope unmarshal = new UnmarshalBuffer(data[0..dataLen]);
            receive(channelId, unmarshal);
        } catch (Exception e) {
            Stdout.formatln("Unhandled exception: {}", e.toString());
            closeWithReason("error_internal", [e.msg]);
        }
    }

    //NetPeer.onDisconnect
    private void onDisconnect(NetPeer sender) {
        assert(sender is mPeer);
        state(ClientState.closed);
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
