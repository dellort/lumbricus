module net.cmdserver_gui;

import common.common;
import common.task;
import framework.commandline;
import framework.timesource;
import gui.label;
import gui.widget;
import gui.wm;
import gui.list;
import gui.boxcontainer;
import net.cmdserver;
import net.netlayer;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;
import utils.log;
import utils.vector2;
debug import utils.random;

import tango.core.Thread;
import tango.stdc.stdlib : abort;

//as GUI
class CmdNetServerTask : Task {
    private {
        CmdNetServer mServer;
        Label mLabel;
        StringListWidget mPlayerList;
        ConfigNode mSrvConf;
        Thread mServerThread;
        bool mClose;
        int mPlayerCount;
        char[][] mPlayerDetails;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mSrvConf = gConf.loadConfigDef("server");

        mLabel = new Label();
        mPlayerList = new StringListWidget();
        auto box = new BoxContainer(false);
        box.add(mLabel);
        box.add(mPlayerList);
        gWindowManager.createWindow(this, box, "Server", Vector2i(350, 0));

        mServerThread = new Thread(&thread_run);
        mServerThread.start();
    }

    private void thread_run() {
        try {
            mServer = new CmdNetServer(mSrvConf);
            Time tlast;
            while (true) {
                Time t = timeCurrentTime();
                synchronized (this) {
                    if (mClose)
                        break;
                    if (t - tlast > timeMsecs(500)) {
                        mPlayerCount = mServer.playerCount;
                        mPlayerDetails = null;
                        foreach (ref cl; mServer) {
                            mPlayerDetails ~= myformat("{}: {} ({}), ping {}",
                                cl.id, cl.address, cl.playerName, cl.ping);
                        }
                        tlast = t;
                    }
                }
                mServer.frame();
                mServerThread.yield();
            }
            mServer.shutdown();
            mServer = null;
        } catch (Exception e) {
            //seems this is the only way to be notified about thread errors
            //NOTE: Tango people are saying the exception gets catched by the
            //      runtime and rethrown on Thread.join
            Trace.formatln("Exception {} at {}({})", e.toString(),
                e.file, e.line);
            abort(); //I hope this is ok to terminate the process
        }
    }

    override protected void onKill() {
        synchronized (this) {
            mClose = true;
        }
        //xxx blocks
        //mServerThread.join();
    }

    override protected void onFrame() {
        synchronized(this) {
            mLabel.text = myformat("Clients: {}", mPlayerCount);
            mPlayerList.setContents(mPlayerDetails);
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdserver");
    }
}
