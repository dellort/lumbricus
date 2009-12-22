module gui.container;

import framework.framework : Canvas;
import framework.event;
import gui.widget;
import utils.configfile;
import utils.misc;
import utils.vector2;
import utils.rect2;
import utils.time;
import utils.log;

//this is a "legacy" thing; don't use for new code
class Container : Widget {
    this() {
        setVirtualFrame(false);
    }
}

///Container with a public Container-interface
///Container introduces some public methods too, but only ones that need a
///valid object reference to child widgets
///xxx: maybe do it right, I didn't even catch all functions, but it makes
///     problems in widget.d/Widget
class PublicContainer : Container {
    void clear() {
        super.clear();
    }
}

///PublicContainer which supports simple layouting
///by coincidence only needs to add more accessors to the original Container
///also supports loading of children widgets using loadFrom()
class SimpleContainer : PublicContainer {
    bool mouseEvents = true; //xxx silly hack

    override bool onTestMouse(Vector2i pos) {
        return mouseEvents ? super.onTestMouse(pos) : false;
    }

    /// Add an element to the GUI, which gets automatically cleaned up later.
    void add(Widget obj) {
        addChild(obj);
    }

    /// Add and set layout.
    void add(Widget obj, WidgetLayout layout) {
        setChildLayout(obj, layout);
        addChild(obj);
    }

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto children = node.findNode("children");
        if (children) {
            clear();
            foreach (ConfigNode sub; children) {
                add(loader.loadWidget(sub));
            }
        }

        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("simplecontainer");
    }
}
