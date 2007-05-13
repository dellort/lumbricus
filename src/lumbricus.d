module lumbricus;
import framework.framework;
import framework.sdl.framework;
import framework.filesystem;
import game = game.common;

version (linux) {
    //don't know if it works with GDC, but it does (mostly?) with DMD/Linux
    //and together with my Phobos patch, I can get backtraces on signals
    version = EnableSignalExceptions;
}

version (EnableSignalExceptions) {
    import std.c.linux.linux;
    import std.c.stdio;

    //missing declarations... *sigh*
    alias void function(int) sighandler_t;
    extern(C) sighandler_t signal(int signum, sighandler_t handler);

    private Exception gSigException;

    void signal_handler(int sig) {
        char[] signame;
        switch (sig) {
            case SIGSEGV: signame = "SIGSEGV"; break;
            case SIGFPE: signame = "SIGFPE"; break;
            default:
                signame = "unknown, add to lumbricus.d/signal_handler()";
        }
        printf("Signal caught: %.*s!\n", signame);
        throw gSigException;
    }
}

const char[] APP_ID = "lumbricus";

int main(char[][] args)
{
    version (EnableSignalExceptions) {
        gSigException = new Exception("signal caught");

        //add whatever signal barked on you
        signal(SIGSEGV, &signal_handler);
        signal(SIGFPE, &signal_handler);
    }

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
