module lumbricus;

//enable tango backtracing (on exceptions)
debug import tango.core.stacktrace.TraceExceptions;

//version = Emerald;
version(Emerald) {
    import utils.emerald;
} else {
    extern(C) void show_stuff() {
    }
}

import framework.framework;
import common.init;
import common.common : globals;
import common.config;
import toplevel = common.toplevel;
import utils.configfile;
import tango.io.Stdout;

version = Game;
version = LogExceptions;  //set to write exceptions into logfile, too

//factory-imports (static ctors register stuff globally)
import framework.drivers.base_sdl;
import framework.drivers.sound_openal;
import framework.drivers.font_freetype;
import framework.imgwrite;
import framework.drivers.draw_opengl;
import framework.drivers.draw_sdl;
version(Windows) {
    import framework.drivers.draw_directx;
}

//--> FMOD is not perfectly GPL compatible, so you may need to comment
//    this line in some scenarios (this is all it needs to disable FMOD)
import framework.drivers.sound_fmod;
//<--


//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code

version (Game) {
    import game.gametask; //the game itself
    import game.gui.leveledit; //aw
    import game.gui.welcome;
    import game.gui.teamedit;
    import game.gui.weaponedit;
    import game.gui.setup_local;
    import game.gui.levelpaint;
    import net.cmdserver_gui;
    import net.lobby;
}

import game.wtris; //lol
import game.bomberworm; //?
import common.resview; //debugging
import common.localeswitch;


//of course it would be nicer to automatically generate the following thing, but
//OTOH, it isn't really worth the fuzz
const cCommandLineHelp =
`Partial documentation of commandline switches:
    --help
        Output this and exit.
    --language_id=ID
        Set language ID (de, en)
    --fw.prop=val
        Set property 'prop' of the fwconfig stuff passed to the Framework to
        'val', e.g. to disable use of OpenGL:
        --fw.sdl.open_gl=false
    --exec.=cmd
        Execute 'cmd' on the commandline, e.g. this starts task1 and task2:
        --exec.="spawn task1" --exec.="spawn task2"
        (the dot "." turns exec into a list, and a list is expected for exec)
        The "autoexec" list in anything.conf isn't executed if an --exec. is
        given on the commandline.
        xxx: executing more than one cmd is broken because of ConfigNode lol
    --data=path
        Mount 'path' as extra data directory (with highest priority, i.e. it
        overrides the standard paths).
    --logconsole
        Output all log output on stdio.`;
//Also see parseCmdLine() for how parsing works.

void lmain(char[][] args) {
    ConfigNode cmdargs = init(args, cCommandLineHelp);

    if (!cmdargs)
        return;

    auto fwconf = loadConfig("framework");
    fwconf.mixinNode(cmdargs.getSubNode("fw"), true);
    auto fw = new Framework(fwconf);
    fw.setCaption("Lumbricus");

    globals.initGUIStuff();

    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    toplevel.gTopLevel.deinitialize();
    fw.deinitialize();

    Stdout.formatln("Bye!");
}

version(LogExceptions) {
    import utils.log;
    import tango.util.log.Trace : Trace;
}

int main(char[][] args) {
    version(LogExceptions) {
        //catch all exceptions, write them to logfile and console and exit
        try {
            lmain(args);
        } catch (Exception e) {
            if (gLogEverything.destination) {
                //logfile output
                e.writeOut((char[] s) {
                    gLogEverything.destination.writeString(s);
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
        lmain(args);
    }
    return 0;
}
