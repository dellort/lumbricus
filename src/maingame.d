import std.stdio;
import std.stream;
import std.string;
import framework.framework;
import framework.keysyms;
import framework.sdl.framework;
import utils.configfile;
import std.file;
import path = std.path;
import level.generator;
import filesystem;

class MainGame {
    Framework mFramework;
    Surface img, imglevel;
    FileSystem mFileSystem;
    Font font;
    Vector2i offset;
    uint mLevelWidth = 750, mLevelHeight = 550;
    LevelGenerator generator;

    this(char[][] args) {
        mFileSystem = new FileSystem(args[0]);
        mFramework = new FrameworkSDL();
        mFramework.setVideoMode(800,600,32,false);
    }

    public void run() {
        Stream foo = mFileSystem.openData("basselope.gif");
        img = mFramework.loadImage(foo);
        foo.close();
        FontProperties fontprops;
        Stream f = mFileSystem.openData("font/vera.ttf");
        fontprops.size = 50;
        fontprops.back.g = 1.0f;
        fontprops.back.a = 0.2f;
        fontprops.fore.r = 1f;
        fontprops.fore.g = 0;
        fontprops.fore.b = 0;
        fontprops.fore.a = 0.6f;
        font = mFramework.loadFont(f, fontprops);
        f.close();
        mFramework.onFrame = &frame;
        mFramework.onKeyDown = &keyDown;
        mFramework.onKeyUp = &keyUp;
        mFramework.onKeyPress = &keyPress;
        mFramework.onMouseMove = &mouseMove;
        mFramework.setCaption("strange lumbricus test thingy");

        //testconfig();
        generator = new LevelGenerator();
        f = mFileSystem.openData("levelgen.conf");
        ConfigFile conf = new ConfigFile(f, "levelgen.conf", &doout);
        f.close();
        generator.config = conf.rootnode.getSubNode("levelgen");
        generate_level();

        mFramework.run();
    }

    void doout(char[] str) {
        writefln(str);
    }

    void testconfig() {
        //SVN never forgets, but I don't want to rewrite that crap if I need it again
        auto inf = mFileSystem.openUser("test.conf",FileMode.In);
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
        auto outf = mFileSystem.openUser("test.conf", FileMode.OutNew);
        f.writeFile(outf);
        outf.close();
    }

    void frame() {
        Canvas scrCanvas = mFramework.screen.startDraw();
        scrCanvas.drawFilledRect(Vector2i(0,0),mFramework.screen.size,Color(1.0f,1.0f,1.0f));
        scrCanvas.draw(img,Vector2i(0,0));
        font.drawText(scrCanvas, Vector2i(50, 50), "halllloxyzäöüß.");
        scrCanvas.draw(imglevel, offset);
        //mFramework.screen.draw(img.surface,Vector2i(75,75));
        scrCanvas.endDraw();
    }
    
    void generate_level() {
        imglevel = generator.generateRandom(mLevelWidth, mLevelHeight,
            "").image;
    }

    void keyDown(KeyInfo infos) {
        writefln("onKeyDown: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
        if (infos.code == Keycode.ESCAPE) {
            mFramework.terminate();
        } else if (infos.code == Keycode.MOUSE_LEFT) {
            generate_level();
        }
        writefln("Key-ID: %s", mFramework.translateKeycodeToKeyID(infos.code));
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
    }

    void mouseMove(MouseInfo infos) {
        //writef("onMouseMove: (%s, %s)", infos.pos.x, infos.pos.y);
        //writefln(" rel: (%s, %s)", infos.rel.x, infos.rel.y);
        //offset = -infos.pos*4+Vector2i(300,300);
    }
}

int main(char[][] args)
{
    MainGame game = new MainGame(args);
    game.run();

    return 0;
}