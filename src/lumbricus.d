module lumbricus;
import framework.framework;

import common.init;

//also a factory-import
import framework.sdl.framework;
import framework.sdl.soundmixer;
import framework.openal;
import framework.fontft;

//--> FMOD is not perfectly GPL compatible, so you may need to comment
//    this line in some scenarios (this is all it needs to disable FMOD)
import framework.fmod;
//<--

import framework.imgwrite;

import framework.filesystem;
import common.common : globals;
import common.config;
import toplevel = common.toplevel;

import utils.configfile;
import utils.log;
import utils.output;

//hacky hack
import tracer = utils.mytrace;

import tango.io.Stdout;
import str = stdx.string;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidentally

import gui.test; //GUI test code
import game.gametask; //the game itself
version(DigitalMars) {
    //I can only assume that this caused problems with ldc
    import game.gui.leveledit; //aw
}
import game.gui.welcome;
import game.gui.teamedit;
import game.gui.weaponedit;
import game.gui.setup_local;
import game.gui.levelpaint;
import game.wtris; //lol
import game.bomberworm; //?
//debugging
import common.resview;
//net tests
//--compiling this module with LDC results in a segfault
version(DigitalMars) {
    import net.enet_test;
}
//import net.test;
import net.testgame;
import net.cmdserver_gui;
import net.lobby;

//import test;

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

void main(char[][] args) {
    ConfigNode cmdargs = init(args, cCommandLineHelp);

    if (!cmdargs)
        return;

    auto fwconf = gConf.loadConfig("framework");
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
