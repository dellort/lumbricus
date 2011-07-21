module game.hud.hudbase;

import game.core;
import gui.container;
import gui.widget;
import utils.factory;
import utils.misc;

//maintains engine the GUI container for engine created HudElements
//xxx: for some retarded reason, the GameFrame is created after the GameEngine
//  and the plugins and all that (looks too complicated to reverse order or so);
//  work it around by creating an intermediary container widget - only reason
//  for this HudManager thing, and should be changed if it becomes possible
//GameFrame will query this when created
class HudManager {
    private {
        SimpleContainer mHudFrame;
    }

    this() {
        mHudFrame = new SimpleContainer();
    }

    SimpleContainer hudFrame() {
        return mHudFrame;
    }

    //yay singletons
    //return per-game instance (create it if non-existent)
    static HudManager Get(GameCore engine) {
        auto me = engine.querySingleton!(HudManager)();
        if (!me) {
            me = new HudManager();
            engine.addSingleton(me);
        }
        return me;
    }
}

interface HudElement {
    //setting it to visible=false will remove the HUD permanently (i.e. if all
    //  user references to it are cleared, it will be GC'ed)
    //xxx maybe a bad idea; should there only be a remove() method?
    bool visible();
    void visible(bool set);
}

class HudElementWidget : HudElement {
    private {
        GameCore mEngine;
        Widget mWidget;
    }

    this(GameCore a_engine) {
        argcheck(a_engine);
        mEngine = a_engine;
    }

    //can be used by HUD elements that don't want to derive this class etc.
    this(GameCore a_engine, Widget w) {
        this(a_engine);
        set(w);
    }

    SimpleContainer getHudFrame() {
        return HudManager.Get(mEngine).hudFrame;
    }

    GameCore engine() {
        return mEngine;
    }

    bool visible() {
        return mWidget && mWidget.parent;
    }

    void visible(bool set) {
        if (!mWidget)
            return;
        if ((!!mWidget.parent) == set)
            return;
        if (!set) {
            mWidget.remove();
        } else {
            getHudFrame.add(mWidget);
        }
    }

    protected void set(Widget widget, bool initially_visible = true) {
        visible = false;
        mWidget = widget;
        visible = initially_visible;
    }
}
