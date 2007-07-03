module gui.guiframe;
import framework.framework : Canvas;
import gui.guiobject;
import gui.gui;

public import gui.gui : GuiMain;

/// Group of GUI objects.
//xxx currently completely pointless? future: make this a gui "window"?
class GuiFrame {
    private GuiMain mGui;
    private GuiObject[] mGuiObjects;

    this(GuiMain gui) {
        assert(gui !is null);
        mGui = gui;
    }

    GuiMain gui() {
        return mGui;
    }

    /// Called on every redraw.
    void onFrame(Canvas c) {
    }

    /// Add an element to the GUI, which gets automatically cleaned up later.
    protected void addGui(GuiObject obj) {
        mGui.add(obj, GUIZOrder.Gui);
        mGuiObjects ~= obj;
    }

    /// Deinitialize GUI.
    protected void killGui() {
        foreach (GuiObject o; mGuiObjects) {
            //should be enough
            o.active = false;
        }
        mGuiObjects = null;
    }

    /// Completely deinitialize, call if you had enough.
    void kill() {
        killGui();
    }
}
