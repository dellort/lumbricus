module net.cmdserver_gui;

import common.common;
import common.task;
import framework.commandline;
import framework.timesource;
import gui.label;
import gui.widget;
import gui.wm;
import net.cmdserver;
import net.netlayer;
import utils.configfile;
import utils.time;
import utils.list2;
import utils.output;
import utils.log;
debug import utils.random;

import tango.core.Thread;
import tango.stdc.stdlib : abort;

//as GUI
class CmdNetServerTask : Task {
    private {
        CmdNetServer mServer;
        Label mLabel;
        ConfigNode mSrvConf;
        Thread mServerThread;
        bool mClose;
        int mPlayerCount;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mSrvConf = gConf.loadConfigDef("server");

        mLabel = new Label();
        gWindowManager.createWindow(this, mLabel, "Server");

        mServerThread = new Thread(&thread_run);
        mServerThread.start();
    }

    private void thread_run() {
        try {
            mServer = new CmdNetServer(mSrvConf);
            while (true) {
                synchronized (this) {
                    if (mClose)
                        break;
                    mPlayerCount = mServer.playerCount;
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
        mLabel.text = myformat("Clients: {}", mPlayerCount);
    }

    static this() {
        TaskFactory.register!(typeof(this))("cmdserver");
    }
}
