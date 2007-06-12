module lumbricus;
import framework.sdl.framework;
import framework.filesystem : MountPath;
import game = game.common;
import toplevel = game.toplevel;
import std.random : rand_seed;
import utils.log;
import utils.output;
import std.stream : File, FileMode;

const char[] APP_ID = "lumbricus";

int main(char[][] args)
{
    //xxx
    rand_seed(1, 1);

    auto fw = new FrameworkSDL(args[0], APP_ID);
    fw.setCaption("Lumbricus");

    //init filesystem
    fw.fs.mount(MountPath.data,"locale/","/locale/",false);
    fw.fs.tryMount(MountPath.data,"data2/","/",false);
    fw.fs.mount(MountPath.data,"data/","/",false);
    fw.fs.mount(MountPath.user,"/","/",true);

    gLogEverything.destination = new StreamOutput(new File("logall.txt",
        FileMode.OutNew));

    new game.Common(fw, args[1..$]);
    //installs callbacks to framework, which get called in the mainloop
    new toplevel.TopLevel();

    fw.run();

    return 0;
}
