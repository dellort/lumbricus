module common.localeswitch;

import common.common;
import common.task;
import framework.framework;
import framework.font;
import framework.i18n;
import gui.loader;
import gui.widget;
import gui.window;
import gui.button;
import gui.dropdownlist;
import utils.configfile;
import utils.misc;
import utils.rect2;
import utils.vector2;

class LocaleSwitch {
    private {
        Widget mDialog;
        WindowWidget mWindow;
        DropDownList mLocaleList;
        char[][] mLocaleIds;
        char[] mOldLanguage, mSelLanguage;
    }

    this(char[] args) {
        //if "check" is passed, exit if a language is already set
        if (args == "check" && gCurrentLanguage.value.length > 0) {
            return;
        }

        //for reset on cancel
        mOldLanguage = gCurrentLanguage.value;

        auto loader = new LoadGui(loadConfig("dialogs/locale_gui"));
        loader.load();

        loader.lookup!(Button)("btn_ok").onClick = &okClick;
        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;
        mLocaleList = loader.lookup!(DropDownList)("dd_locales");
        mLocaleList.onSelect = &localeSelect;

        char[][] locList;
        mLocaleIds = null;
        //get the currently displayed locale, to set initial selection
        char[] curId = gCurrentLanguage.value;
        if (curId.length == 0)
            curId = gFallbackLanguage;
        //list locale directory and add all files to the dropdownlist
        scanLocales((char[] id, char[] name_en, char[] name) {
            //e.g. German (Deutsch)
            locList ~= name_en ~ " (" ~ name ~ ")";
            if (id == curId) {
                //this file is the current language, select it
                mLocaleList.selection = locList[$-1];
                mSelLanguage = id;
            }
            mLocaleIds ~= id;
        });
        mLocaleList.list.setContents(locList);

        mDialog = loader.lookup("locale_root");
        mWindow = gWindowFrame.createWindow(mDialog,
            r"\t(localeswitch.caption)");
    }

    private void cancelClick(Button sender) {
        //locale may have been changed on selection, reset it
        initI18N(mOldLanguage);
        mWindow.remove();
    }

    private void okClick(Button sender) {
        assert(mSelLanguage.length > 0);
        //update config file
        auto node = loadConfigDef("language");
        node["language_id"] = mSelLanguage;
        saveConfig(node, "language.conf");
        //locale should already be active
        mWindow.remove();
    }

    private void localeSelect(DropDownList sender) {
        int idx = sender.list.selectedIndex;
        if (idx >= 0) {
            //a locale was selected, activate it for preview
            mSelLanguage = mLocaleIds[idx];
            initI18N(mSelLanguage);
        }
    }

    static this() {
        registerTaskClass!(typeof(this))("localeswitch");
    }
}
