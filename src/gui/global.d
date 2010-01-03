module gui.global;

import common.resset;
import gui.styles;

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
    styleRegisterBool("bitmap-background-tile");
    styleRegisterInt("widget-pad");

    styleRegisterFont("text-font");
    styleRegisterColor("window-fullscreen-color");

    styleRegisterColor("cooldown-color");
}
