module common.settings;

import framework.framework;
import utils.proplist;

PropertyList gSettings;

static this() {
    gSettings = new PropertyList;
    gSettings.name = "global";
    gSettings.addNode(gFrameworkSettings);
}
