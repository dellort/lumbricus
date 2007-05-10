module maingame;
import framework.framework;
import framework.sdl.framework;
import framework.filesystem;
import game = game.common;

const char[] APP_ID = "lumbricus";

int main(char[][] args)
{
    auto fw = new FrameworkSDL(args[0], APP_ID);
    fw.setVideoMode(800,600,0,false);
    fw.setCaption("Lumbricus");

    //init filesystem
    fw.fs.mount(MountPath.data,"data/","/",false);
    fw.fs.mount(MountPath.user,"/","/",true);

    new game.Common(fw);

    fw.run();

    return 0;
}
