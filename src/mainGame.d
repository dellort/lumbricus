module sdltest;

import std.stdio;
import std.string;
import framework.framework;
import framework.sdl.framework;

class MainGame {
    Framework mFramework;
    Image img;
    Font font;

    this() {
        mFramework = new FrameworkSDL();
        mFramework.setVideoMode(800,600,32,false);
    }

    public void run() {
        img = mFramework.loadImage("C:\\Windows\\winnt256.bmp");
        FontProperties fontprops;
        File f = new File("c:\\windows\\fonts\\ARIAL.ttf");
        font = mFramework.loadFont(f, fontprops);
        mFramework.onFrame = &frame;
        mFramework.onKeyDown = &keyDown;
        mFramework.onKeyUp = &keyUp;
        mFramework.onKeyPress = &keyPress;
        mFramework.onMouseMove = &mouseMove;
        mFramework.run();
    }

    void frame() {
        mFramework.screen.draw(img.surface,Vector2(0,0));
        font.drawText(mFramework.screen, Vector2(50, 50), "halllloxyzäöüß.");
    }

    void keyDown(KeyInfo infos) {
        writefln("onKeyDown: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
        if (infos.code == Keycode.ESCAPE) {
            mFramework.terminate();
        }
    }

    void keyUp(KeyInfo infos) {
        writefln("onKeyUp: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
    }

    void keyPress(KeyInfo infos) {
        writefln("onKeyPress: key=%s unicode=>%s<", cast(int)infos.code, infos.unicode);
    }

    void mouseMove(MouseInfo infos) {
        writefln("onMouseMove: (%s, %s)", infos.pos.x, infos.pos.y);
    }
}

int main(char[][] args)
{
    MainGame game = new MainGame();
    game.run();
    return 0;
}