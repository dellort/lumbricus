module gui.tabs;

import framework.drawing;
import gui.container;
import gui.button;
import gui.widget;
import utils.color;
import utils.rect2;
import utils.vector2;
import utils.configfile;
import utils.misc;

//NOTE: Tabs uses TabPage.visible internally
class TabPage : Widget {
    private Widget mClient;

    this(Widget client) {
        mClient = client;
        styles.addClass("tab-page");
        focusable = false;
        addChild(mClient);
    }

    final Widget client() {
        return mClient;
    }
}


//NOTE: Widget.parent is meaningless for client widgets.
class Tabs : Container {
    private {
        struct Item {
            Button button;
            TabPage page;
            //rectangle for the button, only valid after relayouting
            Rect2i buttonrc;
            Vector2i size_tmp;
        }

        Item[] mItems;
        TabPage mActive;
        Vector2i mButtons;

        enum cBorder = 1;
    }

    void delegate(Tabs sender) onActiveChange;

    TabPage addTab(Widget client, string caption) {
        assert (!!client);
        assert (!client.parent);
        auto page = new TabPage(client);
        page.visible = false;
        auto b = new Button();
        b.styles.addClass("tab-button");
        b.text = caption;
        b.onClick = &onSetActive;
        auto l = WidgetLayout.Noexpand();
        l.padA.x = l.padB.x = cBorder*3;
        l.padA.y = cBorder*2;
        l.padB.y = cBorder;
        b.setLayout(l);
        mItems ~= Item(b, page);
        addChild(b);
        addChild(page);
        //-- addChild for the button already does this
        //-- needRelayout();
        if (!active)
            active = page;
        return page;
    }

    void removeTab(TabPage page) {
        foreach (int i, Item item; mItems) {
            if (item.page is page) {
                item.button.remove();
                mItems = mItems[0..i] ~ mItems[i+1..$];
                if (page is active)
                    active = null;
                return;
            }
        }
        assert (false);
    }

    TabPage active() {
        return mActive;
    }

    void active(TabPage w) {
        if (mActive is w)
            return;
        if (!w)
            return;
        assert(w.parent is this);
        if (mActive)
            mActive.visible = false;
        foreach (Item item; mItems) {
            if (item.page is w) {
                mActive = w;
                mActive.visible = true;
                if (onActiveChange)
                    onActiveChange(this);
                return;
            }
        }
        assert (false);
    }

    private void onSetActive(Button sender) {
        foreach (Item item; mItems) {
            if (item.button is sender) {
                active = item.page;
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
            biggest = biggest.max(w.page.layoutCachedContainerSizeRequest());
            //and some manual layouting (see drawing code) for the button bar
            w.size_tmp = w.button.layoutCachedContainerSizeRequest();
            buttons.x += w.size_tmp.x;
            buttons.y = max(buttons.y, w.size_tmp.y);
        }
        biggest.y += buttons.y + (cBorder+1)/2;
        biggest.x = max(biggest.x, buttons.x + 1);
        mButtons = buttons;
        return biggest;
    }

    protected override void layoutSizeAllocation() {
        Rect2i b = widgetBounds();
        b.p1.y += mButtons.y + (cBorder+1)/2;
        Vector2i cur;
        foreach (ref Item w; mItems) {
            w.buttonrc = Rect2i(cur, cur + w.size_tmp);
            cur.x += w.size_tmp.x;
            w.button.layoutContainerAllocate(w.buttonrc);
            w.page.layoutContainerAllocate(b);
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
            bool ac = item.page is mActive;
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

    override void loadFrom(GuiLoader loader) {
        auto node = loader.node;

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
