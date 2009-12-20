module gui.global;

import common.resset;

ResourceSet gGuiResources;

static this() {
    //this is actually initialized somewhere in common.common
    //loaded from guires.conf
    gGuiResources = new ResourceSet();
}
