module lumbricus;

//enable tango backtracing (on exceptions)
debug import tango.core.tools.TraceExceptions;

//version = Emerald;
version(Emerald) {
    import utils.emerald;
} else {
    extern(C) void show_stuff() {
    }
}

import framework.framework;
import framework.config;
import common.init;
import common.common : globals;
//import common.settings;
import toplevel = common.toplevel;
import utils.configfile;
import utils.misc;
import tango.io.Stdout;

version = Game;
version = LogExceptions;  //set to write exceptions into logfile, too

//drivers etc.
import framework.stuff;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code

version (Game) {
    import game.gametask; //the game itself
    import game.gui.welcome;
    import game.gui.teamedit;
    import game.gui.setup_local;
    import game.gui.levelpaint;
    import net.cmdserver_gui;
    import net.lobby;
}

import game.wtris; //lol
import game.bomberworm; //?
import common.resview; //debugging
import common.localeswitch;


//Also see parseCmdLine() for how parsing works.

void lmain(char[][] args) {
    init(args[1..$]);

    auto fw = new Framework();
    fw.setCaption("Lumbricus");

    globals.initGUIStuff();

    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    toplevel.gTopLevel.deinitialize();
    fw.deinitialize();

    Stdout.formatln("Bye!");
}

int main(char[][] args) {
    version(LogExceptions) {
        //catch all exceptions, write them to logfile and console and exit
        try {
            lmain(args);
        } catch (ExitApp e) {
        } catch (Exception e) {
            if (gLogFileSink) {
                //logfile output
                e.writeOut((char[] s) {
                    gLogFileSink(s);
                });
            }
            //console output
            e.writeOut((char[] s) {
                Trace.format("{}", s);
            });
            return 1;
        }
    } else {
        //using default exception handler (outputs to console)
        try {
            lmain(args);
        } catch (ExitApp e) {
        }
    }
    return 0;
}
