module sdltest;

import std.stdio;
import std.stream;
import std.string;
import framework.framework;
import framework.sdl.framework;
import utils.configfile;
import std.cstream, std.file;

class MainGame {
    Framework mFramework;
    Image img;
    Font font;

    this() {
        mFramework = new FrameworkSDL();
        mFramework.setVideoMode(800,600,32,false);
    }

    public void run() {
        img = mFramework.loadImage("test.bmp");
        FontProperties fontprops;
        File f = new File("Vera.ttf");
        font = mFramework.loadFont(f, fontprops);
        mFramework.onFrame = &frame;
        mFramework.onKeyDown = &keyDown;
        mFramework.onKeyUp = &keyUp;
        mFramework.onKeyPress = &keyPress;
        mFramework.onMouseMove = &mouseMove;
        mFramework.setCaption("strange lumbricus test thingy");
        mFramework.run();
    }

    void frame() {
        mFramework.screen.draw(img.surface,Vector2i(0,0));
        font.drawText(mFramework.screen, Vector2i(50, 50), "halllloxyzäöüß.");
        mFramework.screen.draw(img.surface,Vector2i(75,75));
    }

    void keyDown(KeyInfo infos) {
        writefln("onKeyDown: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
        if (infos.code == Keycode.ESCAPE) {
            mFramework.terminate();
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
        writef("onMouseMove: (%s, %s)", infos.pos.x, infos.pos.y);
        writefln(" rel: (%s, %s)", infos.rel.x, infos.rel.y);
    }
}

int main(char[][] args)
{
    //MainGame game = new MainGame();
    //game.run();
    
    //SVN never forgets, but I don't want to rewrite that crap if I need it again
    ConfigFile f = new ConfigFile(cast(char[])read("test.conf"), "file", std.cstream.dout);
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
    f.writeFile(new File("test.conf2", FileMode.OutNew));
    //*/
    return 0;
}
