module gui.fps;

import framework.framework;
import game.common;
import game.scene;
import game.visual;
import gui.guiobject;
import std.string;

class GuiFps : GuiObject {
    FontLabel fpsDisplay;

    this() {
        fpsDisplay = new FontLabel(globals.framework.getFont("fpsfont"));
    }

    public void setScene(Scene s, int z) {
        super.setScene(s, z);
        fpsDisplay.setScene(s, z);
    }

    void simulate(float deltaT) {
        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);
        fpsDisplay.pos = (fpsDisplay.scene.size - fpsDisplay.size).X;
    }

    void draw(Canvas canvas) {
        //
    }
}
