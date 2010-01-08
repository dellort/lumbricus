module gui.global;

import common.resset;
import framework.drawing;
import gui.styles;
import utils.strparser;

ResourceSet gGuiResources;

static this() {
    //this is actually initialized somewhere in common.common
    //loaded from guires.conf
    gGuiResources = new ResourceSet();

    styleRegisterFloat("highlight-alpha");
    styleRegisterColor("border-color");
    styleRegisterColor("border-back-color");
    styleRegisterColor("border-bevel-color");
    styleRegisterInt("border-corner-radius");
    styleRegisterInt("border-width");
    styleRegisterBool("border-enable");
    styleRegisterBool("border-bevel-enable");
    styleRegisterBool("border-not-rounded");
    styleRegisterColor("widget-background");
    styleRegisterString("bitmap-background-res");
    enumStrings!(ImageDrawStyle, "center,tile,stretch,stretchx,stretchy,fitInner,fitOuter");
    styleRegisterStrParser!(ImageDrawStyle)("bitmap-background-tile");
    styleRegisterInt("widget-pad");
    styleRegisterInt("border-min");

    styleRegisterFont("text-font");
    styleRegisterColor("window-fullscreen-color");

    styleRegisterColor("cooldown-color");
}
