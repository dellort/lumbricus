module net.cmdserver_gui;

import common.task;
import gui.label;
import gui.button;
import gui.widget;
import gui.window;
import utils.path;
import utils.vector2;

import array = utils.array;

import tango.sys.Process;

private Process[] gAllProcesses;

static ~this() {
    //kill all still running child processes at exit
    foreach (p; gAllProcesses)
        p.kill();
    gAllProcesses = null;
}

//as GUI
//NOTE: now just starts a separate dedicated server process
//the GUI is a bit boring (just a start/kill button), but the server should be
//  remote-controlled by a client anyway
class CmdNetServerTask {
    private {
        Button mButton;
        WindowWidget mWindow;
        Process mProcess;
        int mPrevState = -1; // "None | bool", I wish
    }

    this() {
        string[] args;
        args ~= getExePath();
        args ~= "--server";
        mProcess = new Process(true, args);
        mProcess.setRedirect(Redirect.None);

        mButton = new Button();
        mButton.onClick = &onClick;
        mWindow = gWindowFrame.createWindow(mButton, "Server", Vector2i(0));

        addTask(&onFrame);

        checkState();
    }

    private void onClick(Button sender) {
        if (!mProcess.isRunning) {
            start();
        } else {
            stop();
        }
    }

    private void checkState() {
        int state = mProcess.isRunning();
        if (state == mPrevState)
            return;
        mPrevState = state;
        if (mProcess.isRunning) {
            mButton.textMarkup = "\\t(server.stop)";
        } else {
            mButton.textMarkup = "\\t(server.start)";
        }
    }

    private void stop() {
        //this _waits_ for the process and may freeze the GUI for a while
        //although the OS (at least Linux) wouldn't force us to wait just to
        //  kill the process, the implementation specifically contains calls to
        //  blocking syscalls *sigh*
        mProcess.kill();
        array.arrayRemoveUnordered(gAllProcesses, mProcess, true);
    }

    private void start() {
        mProcess.execute();
        gAllProcesses ~= mProcess;
    }

    private bool onFrame() {
        if (mWindow.wasClosed()) {
            stop();
            mProcess.close();
            mProcess = null;
            return false;
        }
        checkState();
        return true;
    }

    static this() {
        registerTaskClass!(typeof(this))("cmdserver");
    }
}
