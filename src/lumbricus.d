module lumbricus;

import framework.filesystem;
import framework.globalsettings;
import framework.imgread;
import framework.main;
import common.init;
import common.gui_init;
import toplevel = common.toplevel;
import utils.misc;

import std.stdio;

version = Game;
//version = Net;

debug {
    //version = EnableDBacktrace;
}

version (EnableDBacktrace) {
    import dbacktrace.autoinit;
} else {
    import core.runtime;
    static this() {
        //disable backtrace - why the fuck is this enabled by default
        Runtime.traceHandler = null;
    }
}

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

//drivers etc.
import framework.stuff;

import gui.test;

version (Game) {
    import game.gametask; //the game itself
    import game.gui.welcome;
    import game.gui.teamedit;
    import game.gui.setup_local;
    import game.gui.levelpaint;

    version (Net) {
        import net.cmdserver;
        import net.cmdserver_gui;
        import net.lobby;
    }

    //support for directly loading WWP data without running extractdata
    //all that can be removed from the final binary by commenting this line (if
    //  there ever should be a problem with lowlife scum, i.e. lawyers)
    import wwptools.load;
}

import game.wtris; //lol
import game.bomberworm; //?
import common.localeswitch;

void lmain(string[] args) {
    args = args[1..$];
    bool is_server = getarg(args, "server");

    init(args);

    version (Game) {
        if (is_server) {
            version (Net) {
                runCmdServer();
            } else {
                writefln("networking not compiled in");
                exit(1);
            }
            return;
        }
    }

    gFramework.initialize();
    gFramework.setCaption("Lumbricus");

    try {
        gFramework.setIcon(loadImage("lumbricus-icon.png"), "MAINICON");
    } catch (CustomException e) {
    }

    initGUI();

    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    gFramework.run();

    saveSettings();

    gFramework.deinitialize();
}

int main(string[] args) {
    return wrapMain(args, &lmain);
}
