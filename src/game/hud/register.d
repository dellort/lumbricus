module game.hud.register;

import game.hud.teaminfo;
import gui.container;
import gui.widget;
import utils.factory;
import utils.misc;

alias StaticFactory!("HudElements", Widget, SimpleContainer, GameInfo, Object)
    HudFactory;

//GuiClass = what will be instantiated by HudFactory
//HudObject = type of the status object passed by OnHudAdd (and type of the
//  Object parameter passed to HudFactory.instantiate)
void registerHud(GuiClass, HudObject)() {
    HudFactory.register!(GuiClass)(HudObject.classinfo.name);
}

Widget instantiateHud(SimpleContainer parent, GameInfo game, Object status) {
    argcheck(status);
    char[] key = status.classinfo.name;
    return HudFactory.instantiate(key, parent, game, status);
}
