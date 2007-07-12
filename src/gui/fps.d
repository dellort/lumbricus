module gui.fps;

import framework.framework;
import common.common;
import common.scene;
import common.visual;
import gui.widget;
import std.string;
import utils.time;

class GuiFps : Widget {
    FontLabel fpsDisplay;

    this() {
        fpsDisplay = new FontLabel(globals.framework.getFont("fpsfont"));
        scene.add(fpsDisplay);
    }

    override bool testMouse(Vector2i pos) {
        return false;
    }

    override void simulate(Time curTime, Time deltaT) {
        fpsDisplay.text = format("FPS: %1.2f", globals.framework.FPS);
        fpsDisplay.pos = (scene.size - fpsDisplay.size).X;
    }
}
