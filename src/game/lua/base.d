module game.lua.base;

import common.lua;
import framework.config;
import framework.framework;
import framework.lua;
import gui.lua;
import gui.rendertext; //: FormattedText
import utils.color;
import utils.configfile;
import utils.timesource;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.random;
import str = utils.string;

/+ ?
debug {
    alias framework.lua.gLuaToDCalls gLuaToDCalls;
    alias framework.lua.gDToLuaCalls gDToLuaCalls;
}
+/

LuaRegistry gScripting;

static this() {
    gScripting = new typeof(gScripting)();
    //I'm not gonna rewrite that
    gScripting.func!(Time.fromString)("timeParse");

    gScripting.setClassPrefix!(TimeSourcePublic)("Time");
    gScripting.methods!(TimeSourcePublic, "current", "difference");
    gScripting.methods!(Random, "rangei", "rangef");

    gScripting.properties_ro!(Surface, "size");
    gScripting.methods!(Surface, "rotated");

    gScripting.ctor!(FormattedText)();
    //xxx getText is problematic because of out params
    gScripting.method!(FormattedText, "setTextCopy")("setText");

    //temporary (hopefully)
    gScripting.method!(ConfigNode, "getStringValue")("get");
    gScripting.method!(ConfigNode, "setStringValue")("set");
    gScripting.method!(ConfigNode, "getStringArray")("getArray");
    gScripting.method!(ConfigNode, "setStringArray")("setArray");
    gScripting.func!(loadConfig)();
}

LuaState createScriptingState() {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);
    state.register(gLuaGuiAdapt);
    state.register(gLuaScenes);
    state.register(gLuaCanvas);

    //only load base stuff here
    //don't load game specific stuff here

    loadScript(state, "utils.lua");
    loadScript(state, "wrap.lua");

    loadScript(state, "vector2.lua");
    state.addScriptType!(Vector2i)("Vector2");
    state.addScriptType!(Vector2f)("Vector2");

    loadScript(state, "rect2.lua");
    state.addScriptType!(Rect2i)("Rect2");
    state.addScriptType!(Rect2f)("Rect2");

    loadScript(state, "time.lua");
    state.addScriptType!(Time)("Time");

    loadScript(state, "color.lua");
    state.addScriptType!(Color)("Color");

    return state;
}
