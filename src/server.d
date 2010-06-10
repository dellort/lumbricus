//the network server as commandline program
//Note: lumbricus network support is very experimental and only useful on LAN
module server;

import xout = tango.io.Stdout;
import tango.core.Thread;

import common.init;
import framework.config;
import framework.filesystem;
import net.cmdserver;

//when this gets true, server will shutdown
bool gTerminate = false;

int main(char[][] args) {
    return wrapMain(args, &lmain);
}

void lmain(char[][] args) {
    setupConsole("Lumbricus Server");
    init(args[1..$]);
    auto server = new CmdNetServer(loadConfigDef("server"));
    scope(exit) server.shutdown();
    while (!gTerminate) {
        server.frame();
        Thread.yield();
    }
}

version(Windows) {
    import tango.sys.win32.UserGdi : SetConsoleTitleA, SetConsoleCtrlHandler;
    import tango.stdc.stringz : toStringz;

    extern(Windows) int CtrlHandler(uint dwCtrlType) {
        gTerminate = true;
        //make Windows not kill us immediately
        return 1;
    }

    void setupConsole(char[] title) {
        //looks nicer
        SetConsoleTitleA(toStringz(title));
        //handle Ctrl-C for graceful termination
        SetConsoleCtrlHandler(&CtrlHandler, 1);
    }
} else {
    import tango.stdc.signal;

    extern(C) void sighandler(int sig) {
        gTerminate = true;
    }

    void setupConsole(char[] title) {
        xout.Stdout.formatln("\033]0;{}\007", title);
        signal(SIGINT, &sighandler);
        signal(SIGTERM, &sighandler);
    }
}
