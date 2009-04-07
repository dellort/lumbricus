module net.enet_test;

import common.common;
import common.task;
import framework.commandline;
import framework.framework;
import gui.console;
import gui.widget;
import gui.wm;
import gui.loader;
import gui.list;
import gui.button;
import net.netlayer;
import net.broadcast;
import utils.array;
import utils.output;
import utils.vector2;
import utils.misc;
import utils.configfile;
import utils.time;

class TestEnet : Task {
    private {
        NetBase mBase;
        NetHost mHost;
        NetPeer[] mPeers;
        Output mOut;

        static uint mInstance;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);
        auto c = new GuiConsole();
        mOut = c.console;
        init_cmds(c.cmdline);
        mInstance++;
        auto w = gWindowManager.createWindow(this, c, myformat("enet test {}",
            mInstance), Vector2i(500,300));

        mBase = new NetBase();

        c.cmdline.execute("help server");
        c.cmdline.execute("help client");
    }

private:

    void init_cmds(CommandLine cmdline) {
        auto c = cmdline;
        c.registerCommand("new", &cmdNew, "spawn new test-task", null);
        c.registerCommand("exit", &cmdExit, "goodbye cruel world", null);
        c.registerCommand("server", &cmdServ, "create as server",
            ["int:port", "int?=10:max connections"]);
        c.registerCommand("client", &cmdClient, "create as client",
            ["int?=1:max connections"]);
        c.registerCommand("connect", &cmdConnect, "create a peer",
            ["text:address", "int?=10:channel count"]);
        c.registerCommand("status", &cmdStatus, "peer/host status",
            ["int?:#peer"]);
        c.registerCommand("disconnect", &cmdDisconnect, "disconnect a peer",
            ["int:#peer"]);
        c.registerCommand("send", &cmdSend, "send data to peer",
            ["int:#peer", "int:channel", "text:data", "bool?=true:reliable",
             "bool?=true:sequenced"]);
        c.registerCommand("broadcast", &cmdSendBroadcast, "broadcast data",
            ["int:channel", "text:data", "bool?=true:reliable",
             "bool?=true:sequenced"]);
    }

    void cmdNew(MyBox[], Output) {
        auto pid = (new typeof(this)(manager)).taskID();
        mOut.writefln("created {}", pid);
    }
    void cmdExit(MyBox[], Output) {
        terminate();
    }

    void cmdServ(MyBox[] args, Output) {
        if (mHost) {
            mOut.writefln("already created");
        } else {
            try {
                mHost = mBase.createServer(args[0].unbox!(int)(),
                    args[1].unbox!(int)());
                mHost.onConnect = &onConnect;
            } catch (NetException e) {
                mOut.writefln("exception '{}'", e);
            }
        }
    }
    void cmdClient(MyBox[] args, Output) {
        if (mHost) {
            mOut.writefln("already created");
        } else {
            try {
                mHost = mBase.createClient(args[0].unbox!(int)());
                mHost.onConnect = &onConnect;
            } catch (NetException e) {
                mOut.writefln("exception '{}'", e);
            }
        }
    }

    void cmdConnect(MyBox[] args, Output) {
        if (!mHost) {
            mOut.writefln("no host");
            return;
        }
        try {
            mHost.connect(NetAddress(args[0].unbox!(char[])),
                args[1].unbox!(int));
        } catch (NetException e) {
            mOut.writefln("exception '{}'", e);
        }
    }

    NetPeer getPeer(int index) {
        if (index < 0 || index >= mPeers.length || mPeers[index] is null) {
            mOut.writefln("peer {} not found.", index);
            return null;
        }
        return mPeers[index];
    }

    void cmdStatus(MyBox[] args, Output) {
        if (!mHost) {
            mOut.writefln("no host");
            return;
        }

        NetPeer peer;
        if (!args[0].empty) {
            auto num = args[0].unbox!(int);
            peer = getPeer(num);
        }

        void dopeer(NetPeer p) {
            mOut.writefln("peer {}: address={}, connected={}, channelcount={}",
                arraySearch(mPeers, p), p.address, p.connected, p.channelCount);
        }

        if (peer) {
            dopeer(peer);
        } else {
            mOut.writefln("host: bound to {}", mHost.boundPort);
            foreach (p; mPeers) {
                if (p)
                    dopeer(p);
            }
        }
    }

    void cmdDisconnect(MyBox[] args, Output) {
        if (!mHost) {
            mOut.writefln("no host");
            return;
        }
        auto peer = getPeer(args[0].unbox!(int));
        if (!peer)
            return;
        peer.disconnect();
    }

    void cmdSend(MyBox[] args, Output) {
        auto peer = getPeer(args[0].unbox!(int));
        auto channel = args[1].unbox!(int);
        auto data = args[2].unbox!(char[]);
        auto reliable = args[3].unbox!(bool);
        auto sequenced = args[4].unbox!(bool);
        if (!peer)
            return;
        peer.send(data.ptr, data.length, channel, false, reliable, sequenced);
    }

    void cmdSendBroadcast(MyBox[] args, Output) {
        auto channel = args[0].unbox!(int);
        auto data = args[1].unbox!(char[]);
        auto reliable = args[2].unbox!(bool);
        auto sequenced = args[3].unbox!(bool);
        if (!mHost) {
            mOut.writefln("no host");
            return;
        }
        mHost.sendBroadcast(data.ptr, data.length, false, reliable, sequenced);
    }

    //from host
    void onConnect(NetHost sender, NetPeer peer) {
        assert(sender is mHost);
        mPeers ~= peer;
        int n = mPeers.length - 1;
        peer.onDisconnect = &onDisconnect;
        peer.onReceive = &onReceive;
        mOut.writefln("Connected peer {} from {}, connected={}, "
            "channelcount={}", n, peer.address, peer.connected,
            peer.channelCount);
    }

    void onReceive(NetPeer sender, ubyte channelId, ubyte* data, size_t dataLen)
    {
        mOut.writefln("* Receive from peer {}/{}: {}",
            arraySearch(mPeers, sender), channelId, data[0..dataLen]);
    }

    void onDisconnect(NetPeer sender, uint code) {
        mOut.writefln("* Peer {} disconnected.", arraySearch(mPeers, sender));
    }

    override protected void onFrame() {
        if (mHost) {
            mHost.serviceAll();
        }
    }

    override protected void onKill() {
        //??
        delete mHost;
        mHost = null;
        delete mBase;
        mBase = null;
    }

    static this() {
        TaskFactory.register!(typeof(this))("enet_test");
    }
}

//lol...
const cBCTestWnd = `
elements {
    {
        class = "boxcontainer"
        name = "root"
        cell_spacing = "15"
        direction = "x"
        homogeneous = "false"
        layout {
            pad = "6"
        }
        cells {
            {
                class = "string_list"
                name = "list"
                draw_border = "true"
                min_size = "200 200"
            }
            {
                class = "button"
                name = "is_server"
                check_box = "true"
                text = "Act as server"
            }
        }
    }
}
`;

class BroadcastTest : Task {
    private {
        NetBase mBase;
        NetBroadcast mServer, mClient;
        Widget mRoot;
        static uint mInstance;
        char[] mName;
        Time mLastTime;
        StringListWidget mList;
        Button mIsServer;

        //ASCII codes of "Lumbricus Terrestris" added up :D
        const cPort = 2061;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);
        mInstance++;
        mName = myformat("Broadcast {}", mInstance);
        mBase = new NetBase();

        auto conf = (new ConfigFile(cBCTestWnd, "cBCTestWnd", null)).rootnode;
        auto loader = new LoadGui(conf);
        loader.load();
        mRoot = loader.lookup("root");
        mList = loader.lookup!(StringListWidget)("list");
        mIsServer = loader.lookup!(Button)("is_server");
        mIsServer.onClick = &toggleServer;

        auto w = gWindowManager.createWindow(this, mRoot, mName);

        mClient = mBase.createBroadcast(cPort, false);
        mClient.onReceive = &clientReceive;

        mLastTime = timeCurrentTime();
    }

    private void toggleServer(Button sender) {
        if (sender.checked && !mServer) {
            mServer = mBase.createBroadcast(cPort, true);
            mServer.onReceive = &serverReceive;
        } else if (!sender.checked && mServer) {
            mServer.close();
            mServer = null;
        }
    }

    private void clientReceive(NetBroadcast sender, ubyte[] data,
        BCAddress from)
    {
        //got a server, add to list
        char[] id = mClient.getIP(from) ~ ": " ~ cast(char[])data;
        char[][] cur = mList.contents();
        foreach (char[] item; cur) {
            if (item == id)
                return;
        }
        cur ~= id;
        mList.setContents(cur);
        //xxx remove servers when they didn't answer for some time
    }

    private void serverReceive(NetBroadcast sender, ubyte[] data,
        BCAddress from)
    {
        //reply to lookup request
        sender.send(cast(ubyte[])mName, from);
    }

    override protected void onKill() {
        mClient.close();
        if (mServer)
            mServer.close();
        delete mBase;
        mBase = null;
    }

    override protected void onFrame() {
        Time t = timeCurrentTime();
        if (t - mLastTime > timeMsecs(500)) {
            mLastTime = t;
            mClient.sendBC(cast(ubyte[])"Lookup");
        }

        if (mServer)
            mServer.service();
        if (mClient)
            mClient.service();
    }

    static this() {
        TaskFactory.register!(typeof(this))("broadcast_test");
    }
}
