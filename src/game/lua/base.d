module game.lua.base;

import framework.framework;
import framework.lua;
import gui.rendertext; //: FormattedText
import utils.configfile;
import utils.timesource;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.random;
import str = utils.string;

//this alias is just so that we can pretend our scripting interface is generic
alias LuaException ScriptingException;

LuaRegistry gScripting;

static this() {
    gScripting = new typeof(gScripting)();
    //I'm not gonna rewrite that
    gScripting.func!(Time.fromString)("timeParse");

    gScripting.setClassPrefix!(TimeSourcePublic)("Time");
    gScripting.methods!(TimeSourcePublic, "current", "difference");
    gScripting.methods!(Random, "rangei", "rangef");

    gScripting.properties_ro!(Surface, "size");

    gScripting.ctor!(FormattedText)();
    //xxx getText is problematic because of out params
    gScripting.method!(FormattedText, "setTextCopy")("setText");

    //temporary (hopefully)
    gScripting.method!(ConfigNode, "getStringValue")("get");
    gScripting.method!(ConfigNode, "setStringValue")("set");
    gScripting.method!(ConfigNode, "getStringArray")("getArray");
    gScripting.method!(ConfigNode, "setStringArray")("setArray");
}

void loadScript(LuaState state, char[] filename) {
    filename = "lua/" ~ filename;
    auto st = gFS.open(filename);
    scope(exit) st.close();
    state.loadScript(filename, st);
}

LuaState createScriptingObj() {
    auto state = new LuaState(LuaLib.safe);
    state.register(gScripting);

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

    return state;
}
