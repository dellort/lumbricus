module game.hud.register;

import game.hud.teaminfo;
import gui.container;
import gui.widget;
import utils.factory;

alias StaticFactory!("HudElements", Widget, SimpleContainer, GameInfo, Object)
    HudFactory;
