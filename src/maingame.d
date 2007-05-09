module maingame;
import std.stdio;
import std.stream;
import std.string;
import framework.framework;
import framework.keysyms;
import framework.sdl.framework;
import framework.font;
import utils.configfile;
import std.file;
import path = std.path;
import level.generator;
import filesystem;
import gc = std.gc;
import perf = std.perf;
import level.level;
import level.placeobjects;
import framework.console;
import framework.commandline;
import utils.log;
import framework.i18n;
import game.common;

class MainGame {
    Framework mFramework;
    Surface img, imglevel;
    Font font;
    Vector2i offset;
    uint mLevelWidth = 1920, mLevelHeight = 696;
    LevelGenerator generator;
    Level mLevel;
    Vector2i foo1, foo2;
    PlaceObjects placer;
    Console cons;
    CommandLine cmdLine;

    uint fg;

    this(char[][] args) {
        initFileSystem(args[0]);

        mFramework = new FrameworkSDL();
        mFramework.setVideoMode(800,600,0,false);

        Log log = registerLog("main");
        log.writefln("hallo welt");

        Stream x = gFileSystem.openData("i18n.conf");
        ConfigFile c = new ConfigFile(x, "i18n.conf", &doout);
        initI18N(c.rootnode, "de");
        auto g = new Translator("module1.mod2");
        log.writefln("?");
        log.writefln(g("id1", 1, "llklk"));

        //throw new Exception("terminate");
    }

    void cmdQuit(CommandLine cmdline, uint id) {
        mFramework.terminate();
    }

    public void run() {
        Stream foo = gFileSystem.openData("basselope.gif");
        img = mFramework.loadImage(foo, Transparency.Alpha);
        foo.close();
        Stream f = gFileSystem.openData("font/vera.ttf");
        FontProperties fontprops;
        fontprops.size = 50;
        fontprops.back.g = 1.0f;
        fontprops.back.a = 0.2f;
        fontprops.fore.r = 1f;
        fontprops.fore.g = 0;
        fontprops.fore.b = 0;
        fontprops.fore.a = 0.6f;

        font = mFramework.loadFont(f, fontprops);

        fontprops.size = 12;
        fontprops.back.a = 0.0f;
        fontprops.fore.r = 0;
        fontprops.fore.g = 1.0f;
        fontprops.fore.b = 0;
        fontprops.fore.a = 1;
        Font consFont = mFramework.loadFont(f, fontprops);
        f.close();
        mFramework.onFrame = &frame;
        mFramework.onKeyDown = &keyDown;
        mFramework.onKeyUp = &keyUp;
        mFramework.onKeyPress = &keyPress;
        mFramework.onMouseMove = &mouseMove;
        mFramework.setCaption("strange lumbricus test thingy");

        //testconfig();
        generator = new LevelGenerator();
        f = gFileSystem.openData("levelgen.conf");
        ConfigFile conf = new ConfigFile(f, "levelgen.conf", &doout);
        f.close();
        generator.config = conf.rootnode.getSubNode("levelgen");
        generate_level();

        //testing console, 50 lines of debug output
        cons = new Console(consFont);
        cmdLine = new CommandLine(cons);

        cmdLine.registerCommand("quit"c, &cmdQuit, "Leave the game.");

        Common c = new Common(mFramework, consFont);

        mFramework.run();
    }

    void doout(char[] str) {
        writefln(str);
    }

    /+void testconfig() {
        //SVN never forgets, but I don't want to rewrite that crap if I need it again
        auto inf = gFileSystem.openUser("test.conf",FileMode.In);
        ConfigFile f = new ConfigFile(inf, "test.conf", &doout);
        inf.close();
        //ConfigFile f = new ConfigFile(" ha        llo    ", "file", std.cstream.dout);
        //f.schnitzel();
        f.rootnode().setStringValue("hallokey", "data");
        ConfigNode s = f.rootnode().getSubNode("node1");
        writefln("val1 = %s", s.getStringValue("val1"));
        writefln("val5 = %s", s.getIntValue("val5"));
        writefln("valnothing = %s", s.getStringValue("valnothing", "default value"));
        //put in some stupid stuff
        s.setStringValue("stoopid", "123 hi");
        static char[] bingarbage = [0x12, 1, 0x34, 0x10, 0xa, 0x66, 0x74];
        s.setStringValue("evil_binary", bingarbage);
        auto outf = gFileSystem.openUser("test.conf", FileMode.OutNew);
        f.writeFile(outf);
        outf.close();
    }+/

    void frame() {
        Canvas scrCanvas = mFramework.screen.startDraw();
        scrCanvas.drawFilledRect(Vector2i(0,0),mFramework.screen.size,Color(1.0f,1.0f,1.0f));
        scrCanvas.draw(img,Vector2i(0,0));
        font.drawText(scrCanvas, Vector2i(50, 50), "halllloxyzäöüß."c);
        scrCanvas.draw(imglevel, offset);
        if (placer && placer.objectImage && mFramework.getModifierState(Modifier.Shift)) {
            scrCanvas.draw(placer.objectImage, mFramework.mousePos-placer.objectImage.size/2);
            scrCanvas.drawLine(foo1, foo2, Color(255, 0, 0));
            font.drawText(scrCanvas, Vector2i(0, 0), format("fo: %d", fg));
        }
        //mFramework.screen.draw(img.surface,Vector2i(75,75));
        //FPS
        font.drawText(scrCanvas, Vector2i(mFramework.screen.size.x-300, mFramework.screen.size.y - 60),
            format("FPS: %1.2f", mFramework.FPS));
        //render console last, to make it topmost
        cons.frame(scrCanvas);
        scrCanvas.endDraw();
    }

    void generate_level() {
        mLevel = generator.generateRandom(mLevelWidth, mLevelHeight, "");
        imglevel = mLevel.image;
    }

    void keyDown(KeyInfo infos) {
        writefln("onKeyDown: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
        if (infos.code == Keycode.ESCAPE) {
            mFramework.terminate();
        } else if (infos.code == Keycode.MOUSE_LEFT) {
            //generate_level();
            if (placer)
                placer.placeObject(mFramework.mousePos);
        }
        if (infos.code == Keycode.A) {
            cons.toggle();
            return true;
        }
        writefln("Key-ID: %s", mFramework.translateKeycodeToKeyID(infos.code));
        cmdLine.keyDown(infos);
    }

    void keyUp(KeyInfo infos) {
        writefln("onKeyUp: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
    }

    void keyPress(KeyInfo infos) {
        writefln("onKeyPress: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
        //output all modifiers
        for (Modifier mod = Modifier.min; mod <= Modifier.max; mod++) {
            writefln("modifier %s: %s", cast(int)mod,
                mFramework.getModifierState(mod));
        }
        if (cons.visible && cmdLine.keyPress(infos))
            return;
        if (true) {
            if (infos.unicode == 'g') {
                auto counter = new perf.PerformanceCounter();
                counter.start();
                gc.fullCollect();
                counter.stop();
                writefln("GC fullcollect: %s us", counter.microseconds);
            }
        }
    }


    void mouseMove(MouseInfo infos) {
        //writef("onMouseMove: (%s, %s)", infos.pos.x, infos.pos.y);
        //writefln(" rel: (%s, %s)", infos.rel.x, infos.rel.y);
        //offset = -infos.pos*4+Vector2i(300,300);
        if (!mFramework.getModifierState(Modifier.Shift))
            return;
        if (placer is null) {
            placer = new PlaceObjects(mLevel);
            Stream foo = gFileSystem.openData("test.png");
            auto imgbla = mFramework.loadImage(foo, Transparency.Colorkey);
            foo.close();
            placer.loadObject(imgbla, PlaceObjects.Side.North, 10);
        }
        Vector2i dir;
        uint cols;
        placer.checkCollide(infos.pos, dir, cols);
        foo1 = infos.pos;
        Vector2f fdir = Vector2f(dir.x, dir.y);
        fdir = fdir.normal()*50;
        dir = Vector2i(cast(int)fdir.x, cast(int)fdir.y);
        foo2 = infos.pos+dir;
        fg = cols;
    }
}

int main(char[][] args)
{
    MainGame game = new MainGame(args);
    game.run();

    return 0;
}
