module lumbricus;
import framework.sdl.framework;
import framework.filesystem : MountPath;
import common = common.common;
import toplevel = common.toplevel;
import std.random : rand_seed;
import utils.log;
import utils.output;
import std.stream : File, FileMode;

//these imports register classes in a factory on module initialization
//so be carefull not to remove them accidently
import gui.test; //GUI test code
import game.gametask; //the game itself
import game.gui.preview; //level preview window
import game.gui.leveledit; //aw
import game.wtris; //lol
//net tests
import net.enet_test;
//import net.test;

const char[] APP_ID = "lumbricus";

int main(char[][] args)
{
    //xxx
    rand_seed(1, 1);

    auto fw = new FrameworkSDL(args[0], APP_ID);
    fw.setCaption("Lumbricus");

    //init filesystem
    fw.fs.mount(MountPath.data, "locale/", "/locale/", false, 2);
    fw.fs.tryMount(MountPath.data, "data2/", "/", false, 2);
    fw.fs.mount(MountPath.data, "data/", "/", false, 3);
    fw.fs.mount(MountPath.user, "/", "/", true, 0);

    gLogEverything.destination = new StreamOutput(new File("logall.txt",
        FileMode.OutNew));

    new common.Common(fw, args[1..$]);
    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    return 0;
}
