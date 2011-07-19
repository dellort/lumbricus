//handle GUI intialization, e.g. add some toplevel widgets
//xxx maybe some stuff from toplevel.d should be moved here
module common.gui_init;

import common.resources;
import framework.config;
import framework.event;
import framework.filesystem;
import framework.font;
import framework.globalsettings;
import framework.main;
import gui.global;
import gui.widget;
import utils.configfile;
import utils.log;
import utils.misc;
import utils.vector2;

//globally capture input
//if a delegate returns true, propagation of the event is stopped, and on
//  false, the next delegate will tried. if no delegate wants to catch the
//  input, it is propagated to the GUI.
alias bool delegate(InputEvent event) CatchInput;
CatchInput[] gCatchInput;

enum cVideoNode = "video";
enum cVideoFS = cVideoNode ~ ".fullscreen";
enum cVideoSizeWnd = cVideoNode ~ ".size.window";
enum cVideoSizeFS = cVideoNode ~ ".size.fullscreen";

static this() {
    addSetting!(bool)(cVideoFS, false);
    addSetting!(Vector2i)(cVideoSizeWnd, Vector2i(0));
    addSetting!(Vector2i)(cVideoSizeFS, Vector2i(0));
}

//GUI root; not entirely sure why this isn't in gui/widget.d (surely there's no
//  good reason, just makes everything harder, feel free to change it)
GUI gGui;

bool guiInitialized() {
    return !!gGui;
}

//call to init GUI related stuff; filesystem must have been initialized/mounted
void initGUI() {
    assert(!guiInitialized());

    setVideoFromConf();
    if (!gFramework.videoActive) {
        //this means we're F****D!!1  ("FOOLED")
        gLog.error("couldn't initialize video");
        //end program in some way
        throw new Exception("can't continue");
    }

    //xxx there was some reason why this was here (after video init), but
    //  this reason disappeared; now where should this be moved to?
    //- maybe create a global "filesystem available" event?

    //GUI resources, this is a bit off here
    gGuiResources = gResources.loadResSet("guires.conf");

    gFontManager.readFontDefinitions(loadConfig("fonts.conf"));

    //GUI ctor tries to load a theme -> FS should be available
    gGui = new GUI();
}

//read configuration from video.conf and set video mode
//xxx revisit this, this toggle thing looks like a hack and how it's used too
void setVideoFromConf(bool toggleFullscreen = false) {
    bool fs = getSetting!(bool)(cVideoFS);
    if (toggleFullscreen)
        fs = !gFramework.fullScreen;
    Vector2i res = getSetting!(Vector2i)(fs ? cVideoSizeFS : cVideoSizeWnd);
    //if nothing set, default to desktop resolution
    if (res.x == 0 || res.y == 0) {
        if (fs)
            res = gFramework.desktopResolution;
        else
            res = Vector2i(1024, 768);
    }
    gFramework.setVideoMode(res, 0, fs);
}

void saveVideoConfig() {
    bool fs = gFramework.fullScreen;
    setSetting!(bool)(cVideoFS, fs);
    Vector2i res = gFramework.screenSize;
    setSetting!(Vector2i)(fs ? cVideoSizeFS : cVideoSizeWnd, res);
    //saveSettings();
}

