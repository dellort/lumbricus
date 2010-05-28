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

        //see comment on thread_run()
        gLog.warn("lol starting unsafe thread in {}", __FILE__);

        mServerThread = new Thread(&thread_run);
        mServerThread.start();

        addTask(&onFrame);
    }

    //xxx running this in a separate thread is highly unsafe; at least because
    //  the thread accesses the log thing, which may call even into the GUI;
    //  there may be other subtle problems as well
    //possible solutions:
    //  1. try to make it safe (e.g. remove all log calls) => lots of PAIN
    //  2. put the network handling into a separate thread (a simple interface,
    //     which makes it easy to correctly do multithreading) => also pain
    //  3. start a new process, which runs the server => why not?
    //  4. decide that we don't need it (actually, I have no clue why we run the
    //     server in a separate thread)
    //  5. make Log threadsafe (transport LogEvent to the main thread) => meh
    //  6. make the GUI part of Log threadsafe
    //for 3., one could add an extra command line option, that starts the server
    //  as separate program
    //for 6., one could easily change the stuff at the end of gui/window.d: just
    //  always use the log buffer and add some synchronized blocks; the rest of
    //  the logging seems to be mostly thread-safe already
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
