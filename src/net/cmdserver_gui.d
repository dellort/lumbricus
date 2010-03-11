module net.cmdserver_gui;

import common.common;
import common.task;
import framework.commandline;
import utils.timesource;
import gui.label;
import gui.button;
import gui.widget;
import gui.window;
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
import utils.misc;
debug import utils.random;

import tango.core.Thread;
import tango.stdc.stdlib : abort;
import tango.core.Runtime;

//as GUI
class CmdNetServerTask {
    private {
        CmdNetServer mServer;
        Label mLabel;
        CheckBox mInternetToggle;
        StringListWidget mPlayerList;
        ConfigNode mSrvConf;
        Thread mServerThread;
        bool mClose;
        int mPlayerCount;
        char[][] mPlayerDetails;
        bool mInternet; //Internet!
        WindowWidget mWindow;
    }

    this() {
        mSrvConf = loadConfigDef("server");

        mLabel = new Label();
        mInternetToggle = new CheckBox();
        mInternetToggle.text = "announce on internet";
        mPlayerList = new StringListWidget();
        auto box = new BoxContainer(false);
        box.add(mLabel);
        box.add(mInternetToggle);
        box.add(mPlayerList);
        mWindow = gWindowFrame.createWindow(box, "Server", Vector2i(350, 0));

        mServerThread = new Thread(&thread_run);
        mServerThread.start();

        addTask(&onFrame);
    }

    private void thread_run() {
        try {
            mServer = new CmdNetServer(mSrvConf);
            Time tlast;
            while (true) {
                if (Runtime.isHalting())
                    break;
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
                    mServer.announceInternet = mInternet;
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

    private bool onFrame() {
        if (mWindow.wasClosed()) {
            synchronized (this) { mClose = true; }
            return false;
        }
        synchronized(this) {
            mLabel.text = myformat("Clients: {}", mPlayerCount);
            mPlayerList.setContents(mPlayerDetails);
            mInternet = mInternetToggle.checked();
        }
        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("cmdserver");
    }
}
