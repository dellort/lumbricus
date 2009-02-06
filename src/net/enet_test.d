module net.enet_test;

import common.common;
import common.task;
import framework.commandline;
import framework.framework;
import gui.console;
import gui.widget;
import gui.wm;
import net.netlayer;
import utils.array;
import utils.output;
import utils.vector2;
import utils.misc;

class TestEnet : Task {
    private {
        NetBase mBase;
        NetHost mHost;
        NetPeer[] mPeers;
        Output mOut;

        static uint mInstance;
    }

    this(TaskManager tm) {
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

    void onDisconnect(NetPeer sender) {
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
