module gui.fps;

import framework.framework;
import game.common;
import game.scene;
import game.visual;
import gui.guiobject;
import std.string;
import utils.time;

class GuiFps : GuiObject {
    FontLabel fpsDisplay;

    this() {
        fpsDisplay = new FontLabel(globals.framework.getFont("fpsfont"));
        addManagedSceneObject(fpsDisplay);
    }

    override void relayout() {
        //?
    }

    override void simulate(Time curTime, Time deltaT) {
        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);
        fpsDisplay.pos = (fpsDisplay.scene.size - fpsDisplay.size).X;
    }
}
