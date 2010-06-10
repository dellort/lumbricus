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
}

int main(char[][] args) {
    return wrapMain(args, &lmain);
}
