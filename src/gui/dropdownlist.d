module gui.dropdownlist;

import common.common;

import framework.restypes.bitmap;
import framework.font;
import framework.framework;

import gui.button;
import gui.boxcontainer;
import gui.container;
import gui.label;
import gui.list;
import gui.scrollwindow;
import gui.widget;
import gui.wm;

import utils.vector2;

///a DropDownControl consists of a popup, a button to trigger the popup, and a
///client control
///both the the client control and the popup must be set by the user before a
///popup can be displayed
class DropDownControl : Container {
    private {
        Widget mClientWidget, mPopupWidget;
        Button mDropDown;
        Window mActivePopup;
        BoxContainer mClientBox;
        bool mLastSuccess;
    }

    ///if a popup is triggered
    void delegate(DropDownControl sender) onPopupOpen;
    ///in any case it's closed
    void delegate(DropDownControl sender, bool success) onPopupClose;

    this() {
        drawBox = true;
        mDropDown = new Button();
        //use that down-arrow...
        mDropDown.image = globals.guiResources.get!(Surface)("scroll_down");
        mDropDown.onClick = &clickDrownDown;
        mDropDown.setLayout(WidgetLayout.Expand(false));
    }

    ///widget in the normally visible area, besides the drop down button
    void setClientWidget(Widget w) {
        assert(!!w);
        if (mClientWidget)
            mClientWidget.remove();
        mClientWidget = w;
        if (mClientBox)
            mClientBox.remove();
        mClientBox = new BoxContainer(true);
        mClientBox.add(w);
        mClientBox.add(mDropDown);
        mClientBox.setLayout(WidgetLayout.Border(Vector2i(3)));
        addChild(mClientBox);
    }

    ///widget in the popup window which is the "drop down" thingy
    void setPopupWidget(Widget w) {
        mPopupWidget = w;
        killPopup();
    }

    void killPopup(bool success = true) {
        if (mActivePopup) {
            mLastSuccess = success;
            mActivePopup.destroy();
            mActivePopup = null;
        }
    }

    private void onPopupDestroy(Window sender) {
        mActivePopup = null;
        if (onPopupClose)
            onPopupClose(this, mLastSuccess);
    }

    void popup() {
        if (mActivePopup)
            return;
        //must be set before it works
        if (!mPopupWidget || !mClientBox)
            return;

        //create the popup and show it...
        //the popup's height is chosen arbitrarily (need better ideas...?)
        Vector2i initsize;
        initsize.x = mClientBox.size.x;
        initsize.y = mClientBox.size.x;
        mActivePopup = gWindowManager.createPopup(mPopupWidget,
            mClientBox, Vector2i(0, 1), initsize, false);
        mActivePopup.onDestroy = &onPopupDestroy;
        mActivePopup.isFocusVolatile = true;
        mActivePopup.visible = true;

        mLastSuccess = false;

        if (onPopupOpen)
            onPopupOpen(this);
    }

    bool popupActive() {
        return !!mActivePopup;
    }

    private void clickDrownDown(Button sender) {
        popup();
    }
}

class DropDownSelect : Label {
    private {
        bool mState;
        Font[2] mFonts;
    }

    this() {
        drawBorder = false;
        shrink = true;
        font = font; //update mFonts
    }

    alias Label.font font;

    override void font(Font font) {
        mFonts[0] = font;
        auto p = font.properties;
        //invert the font
        p.fore.r = 1.0f - p.fore.r;
        p.fore.g = 1.0f - p.fore.g;
        p.fore.b = 1.0f - p.fore.b;
        mFonts[1] = new Font(p);

        super.font(mFonts[mState ? 1 : 0]);
    }

    bool dropdownState() {
        return mState;
    }
    void dropdownState(bool b) {
        mState = b;
        super.font = mFonts[b ? 1 : 0];
    }

    override void onDraw(Canvas canvas) {
        if (mState)
            canvas.drawFilledRect(Vector2i(0), size, Color(0, 0, 0.5));
        super.onDraw(canvas);
    }
}

class DropDownList : Container {
    private {
        DropDownControl mDropDown;
        DropDownSelect mClient;
        StringListWidget mList;
        //"official" selection
        char[] mSelection;
    }

    ///if really a new entry was selected (when the selection popup was closed
    ///and not cancelled)
    void delegate(DropDownList sender) onSelect;

    this() {
        mClient = new DropDownSelect();
        mList = new StringListWidget();
        auto listpopup = new SimpleContainer();
        listpopup.drawBox = true;
        listpopup.drawBoxStyle.cornerRadius = 1;
        listpopup.add(mList);
        auto listwind = new ScrollWindow(listpopup, [false, true]);
        listwind.enableMouseWheel = true;
        listwind.drawBox = true;
        mDropDown = new DropDownControl();
        mDropDown.setPopupWidget(listwind);
        mDropDown.setClientWidget(mClient);
        addChild(mDropDown);
        mList.onSelect = &listSelect;
        mDropDown.onPopupOpen = &popupOpen;
        mDropDown.onPopupClose = &popupClose;
    }

    ///get/set selection - setting selection doesn't trigger onSelect
    char[] selection() {
        return mSelection;
    }
    void selection(char[] v) {
        mSelection = v;
        mClient.text = v;
    }

    private void listSelect(int index) {
        mDropDown.killPopup(true);
        if (index >= 0 && index < mList.contents.length) {
            selection = mList.contents[index];
        } else {
            selection = null;
        }
        if (onSelect)
            onSelect(this);
    }

    private void popupOpen(DropDownControl sender) {
        mClient.dropdownState = true;
    }
    private void popupClose(DropDownControl sender, bool success) {
        mClient.dropdownState = false;
    }

    ///get the list; the DropDownList reserves the StringListWidget.onSelect
    StringListWidget list() {
        return mList;
    }
}
