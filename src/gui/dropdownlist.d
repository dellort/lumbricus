module gui.dropdownlist;


import framework.font;
import framework.framework;

import gui.button;
import gui.boxcontainer;
import gui.container;
import gui.global;
import gui.label;
import gui.list;
import gui.scrollwindow;
import gui.widget;
import gui.window;
import gui.edit;

import utils.vector2;

///a DropDownControl consists of a popup, a button to trigger the popup, and a
///client control
///both the the client control and the popup must be set by the user before a
///popup can be displayed
class DropDownControl : Container {
    private {
        Widget mClientWidget, mPopupWidget;
        Button mDropDown;
        WindowWidget mActivePopup;
        BoxContainer mClientBox;
        bool mLastSuccess;
    }

    ///if a popup is triggered
    void delegate(DropDownControl sender) onPopupOpen;
    ///before the popup is created, return false to prevent it
    bool delegate(DropDownControl sender) onTryPopupOpen;
    ///in any case it's closed
    void delegate(DropDownControl sender, bool success) onPopupClose;

    this() {
        styles.addClass("drop-down-control");
        mDropDown = new Button();
        //use that down-arrow...
        mDropDown.setClient(
            new ImageLabel(gGuiResources.get!(Surface)("scroll_down")));
        mDropDown.onClick = &clickDrownDown;
        auto lay = WidgetLayout.Expand(false);
        lay.border = Vector2i(2, 0);
        mDropDown.setLayout(lay);
    }

    ///widget in the normally visible area, besides the drop down button
    void setClientWidget(Widget w) {
        assert(!!w);
        if (mClientWidget)
            mClientWidget.remove();
        mClientWidget = w;
        mDropDown.remove();
        if (mClientBox)
            mClientBox.remove();
        mClientBox = new BoxContainer(true);
        mClientBox.add(w);
        mClientBox.add(mDropDown);
        mClientBox.setLayout(WidgetLayout.Border(Vector2i(0)));
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
            mActivePopup.remove();
            mActivePopup = null;
        }
    }

    private void onPopupDestroy(WindowWidget sender) {
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

        if (onTryPopupOpen) {
            if (!onTryPopupOpen(this))
                return;
        }

        //create the popup and show it...
        //the popup's height is chosen arbitrarily (need better ideas...?)
        Vector2i initsize;
        initsize.x = mClientBox.size.x;
        initsize.y = mClientBox.size.x;
        mActivePopup = gWindowFrame.createPopup(mPopupWidget,
            mClientBox, initsize);
        mActivePopup.onClose = &onPopupDestroy;

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

class DropDownSelect : Button {
    private {
        bool mState;
        Font[2] mFonts;
    }

    this() {
        styles.addClass("drop-down-select");
        //shrink = true;
        //enableHighlight = false;
    }

    override bool onTestMouse(Vector2i) {
        //click-through if dropped down
        return !mState;
    }

    bool dropdownState() {
        return mState;
    }
    void dropdownState(bool b) {
        mState = b;
        styles.setState("selected", b);
    }

    override void onDraw(Canvas canvas) {
        //wtf is this
        if (mState)
            canvas.drawFilledRect(Vector2i(0), size, Color(0, 0, 0.5));
        super.onDraw(canvas);
    }
}

class DropDownList : Container {
    private {
        DropDownControl mDropDown;
        DropDownSelect mClient;
        EditLine mEdit;
        StringListWidget mList;
        //"official" selection
        char[] mSelection;
        bool mAllowEdit, mEditing;
    }

    ///if really a new entry was selected (when the selection popup was closed
    ///and not cancelled)
    void delegate(DropDownList sender) onSelect;
    void delegate(DropDownList sender) onEditStart;
    void delegate(DropDownList sender) onEditEnd;

    this() {
        mClient = new DropDownSelect();
        mClient.onClick = &clientClick;
        mEdit = new EditLine();
        mList = new StringListWidget();
        auto listpopup = new SimpleContainer();
        listpopup.add(mList);
        auto listwind = new ScrollWindow(listpopup, [false, true]);
        listwind.enableMouseWheel = true;
        mDropDown = new DropDownControl();
        mDropDown.setPopupWidget(listwind);
        mDropDown.setClientWidget(mClient);
        addChild(mDropDown);
        mList.onSelect = &listSelect;
        mDropDown.onPopupOpen = &popupOpen;
        mDropDown.onTryPopupOpen = &tryPopupOpen;
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
        endEdit();
        if (index >= 0 && index < mList.contents.length) {
            selection = mList.contents[index];
        } else {
            selection = null;
        }
        if (onSelect)
            onSelect(this);
    }

    private bool tryPopupOpen(DropDownControl sender) {
        endEdit();
        return true;
    }
    private void popupOpen(DropDownControl sender) {
        mClient.dropdownState = true;
    }
    private void popupClose(DropDownControl sender, bool success) {
        mClient.dropdownState = false;
    }

    bool allowEdit() {
        return mAllowEdit;
    }
    void allowEdit(bool e) {
        if (!e)
            endEdit();
        mAllowEdit = e;
    }

    bool editing() {
        return mEditing;
    }

    private void clientClick(Button sender) {
        if (mAllowEdit) {
            startEdit();
        } else {
            if (!mDropDown.popupActive)
                mDropDown.popup;
        }
    }

    private void startEdit() {
        if (!mAllowEdit || mEditing)
            return;
        mDropDown.setClientWidget(mEdit);
        mEdit.text = mSelection;
        mEdit.claimFocus();
        mEditing = true;
        if (onEditStart)
            onEditStart(this);
    }

    private void endEdit() {
        if (!mEditing)
            return;
        mEditing = false;
        mDropDown.setClientWidget(mClient);
        if (onEditEnd)
            onEditEnd(this);
    }

    ///get the list; the DropDownList reserves the StringListWidget.onSelect
    StringListWidget list() {
        return mList;
    }

    EditLine edit() {
        return mEdit;
    }

    void loadFrom(GuiLoader loader) {
        auto node = loader.node;
        mAllowEdit = node.getValue("allow_edit", mAllowEdit);
        super.loadFrom(loader);
    }

    static this() {
        WidgetFactory.register!(typeof(this))("dropdownlist");
    }
}
