module gui.global;

import common.resset;
import framework.drawing;
import gui.styles;
import utils.strparser;

ResourceSet gGuiResources;

static this() {
    //this is actually initialized somewhere in common.gui_init
    //loaded from guires.conf
    gGuiResources = null; //new ResourceSet();

    styleRegisterFloat("highlight-alpha");
    styleRegisterBorder("border");
    styleRegisterColor("widget-background");
    styleRegisterString("bitmap-background-res");
    styleRegisterString("bitmap-cursor-res");
    enumStrings!(ImageDrawStyle, "center,tile,stretch,stretchx,stretchy,fitInner,fitOuter");
    styleRegisterStrParser!(ImageDrawStyle)("bitmap-background-tile");
    styleRegisterInt("widget-pad");
    styleRegisterInt("border-min");
    styleRegisterInt("focus-border");

    styleRegisterFont("text-font");
    styleRegisterColor("selection-foreground");
    styleRegisterColor("selection-background");
    styleRegisterColor("window-fullscreen-color");

    styleRegisterColor("cooldown-color");
    styleRegisterColor("misfire-color");

    styleRegisterTime("fade-delay");
}
