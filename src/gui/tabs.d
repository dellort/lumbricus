module gui.tabs;

import framework.framework;
import gui.container;
import gui.button;
import gui.widget;
import utils.color;
import utils.rect2;
import utils.vector2;
import utils.configfile;

//NOTE: reparents the client widgets depending on which tab is active; this
//      means you must not use Widget.remove() to remove clients from it, and
//      Widget.parent is meaningless for client widgets.
class Tabs : Container {
    private {
        struct Item {
            Button button;
            Widget client;
            //rectangle for the button, only valid after relayouting
            Rect2i buttonrc;
        }

        Font mFont;
        Item[] mItems;
        Widget mActive;
        Vector2i mButtons;

        const cBorder = 1;
    }

    void delegate(Tabs sender) onActiveChange;

    void addTab(Widget client, char[] caption) {
        assert (!!client);
        assert (!client.parent);
        auto b = new Button();
        b.styles.addClass("tab-button");
        b.text = caption;
        b.onClick = &onSetActive;
        auto l = WidgetLayout.Noexpand();
        l.padA.x = l.padB.x = cBorder*3;
        l.padA.y = cBorder*2;
        l.padB.y = cBorder;
        b.setLayout(l);
        mItems ~= Item(b, client);
        addChild(b);
        //-- addChild for the button already does this
        //-- needRelayout();
        if (!active)
            active = client;
    }

    void removeTab(Widget client) {
        foreach (int i, Item item; mItems) {
            if (item.client is client) {
                item.button.remove();
                mItems = mItems[0..i] ~ mItems[i+1..$];
                if (client is active)
                    active = null;
                return;
            }
        }
        assert (false);
    }

    Widget active() {
        return mActive;
    }

    void active(Widget w) {
        if (mActive is w)
            return;
        if (mActive)
            mActive.remove();
        if (!w)
            return;
        foreach (Item item; mItems) {
            if (item.client is w) {
                mActive = w;
                addChild(mActive);
                if (onActiveChange)
                    onActiveChange(this);
                return;
            }
        }
        assert (false);
    }

    void font(Font font) {
        assert(font !is null);
        mFont = font;
        foreach (ref it; mItems) {
            it.button.font = mFont;
        }
        needResize(true);
    }
    Font font() {
        return mFont;
    }

    private void onSetActive(Button sender) {
        foreach (Item item; mItems) {
            if (item.button is sender) {
                active = item.client;
                return;
            }
        }
        assert (false);
    }

    protected override Vector2i layoutSizeRequest() {
        Vector2i biggest;
        Vector2i buttons;
        foreach (ref Item w; mItems) {
            //report the biggest, but among all existing tabs (?)
            biggest = biggest.max(w.client.layoutCachedContainerSizeRequest());
            //and some manual layouting (see drawing code) for the button bar
            auto b = w.button.layoutCachedContainerSizeRequest();
            w.buttonrc = Rect2i(b);
            buttons.x += b.x;
            buttons.y = max(buttons.y, b.y);
        }
        biggest.y += buttons.y + (cBorder+1)/2;
        biggest.x = max(biggest.x, buttons.x + 1);
        mButtons = buttons;
        return biggest;
    }

    protected override void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        if (mActive) {
            b.p1.y += mButtons.y + (cBorder+1)/2;
            mActive.layoutContainerAllocate(b);
        }
        Vector2i cur;
        foreach (ref Item w; mItems) {
            w.buttonrc += cur - w.buttonrc.p1;
            cur.x += w.buttonrc.size.x;
            w.button.layoutContainerAllocate(w.buttonrc);
        }
    }

    protected override void onDraw(Canvas c) {
        //draw buttons and the client
        super.onDraw(c);
        //draw all the borders
        //this is the actual feature of this widget
        //I thought one could use the nice rounded boxes from visual.d, but
        //  then I thought it's too bothersome and too complicated (especially
        //  if active and inactive buttons should have different background
        //  colors)
        Vector2i bx2 = Vector2i(cBorder, 0);
        Vector2i by2 = Vector2i(0, cBorder);
        auto bx = bx2 / 2;
        auto by = by2 / 2;
        void drawFrame(Rect2i rc, Color col) {
            c.drawLine(rc.pB + bx, rc.p1 + bx, col, cBorder);
            c.drawLine(rc.p1 + by, rc.pA + by, col, cBorder);
            c.drawLine(rc.pA - bx, rc.p2 - bx, col, cBorder);
        }
        Item* pactive = null;
        foreach (ref Item item; mItems) {
            bool ac = item.client is mActive;
            if (!ac) {
                drawFrame(item.buttonrc, Color(0.7));
            } else {
                pactive = &item;
            }
        }
        //active one is drawn at last for correct z-order
        if (pactive) {
            auto col = Color(0);
            drawFrame(pactive.buttonrc, col);
            //the "baseline", goes from left to right of the tab widget, but is
            //interrupted by the active button
            Vector2i bp = Vector2i(0, mButtons.y);
            c.drawLine(bp - by, pactive.buttonrc.pB - by + bx*2, col,
                cBorder);
            bp.x = size.x;
            c.drawLine(pactive.buttonrc.p2 - by - bx*2, bp - by, col,
                cBorder);
        } else {
            //draw a baseline without break?
        }
    }

    void loadFrom(GuiLoader loader) {
        auto node = loader.node;

        auto fnt = gFramework.fontManager.loadFont(
            node.getStringValue("font"), false);
        if (fnt)
            font = fnt;

        //load children; order in list decides layout
        foreach (ConfigNode child; node.getSubNode("cells")) {
            addTab(loader.loadWidget(child),
                loader.locale()(child["tab_caption"]));
        }
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("tabs");
    }
}
