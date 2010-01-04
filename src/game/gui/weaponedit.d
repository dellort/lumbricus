module game.gui.weaponedit;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import game.gfxset;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.wm;
import gui.loader;
import gui.list;
import utils.configfile;


class WeaponEditorTask : Task {
    private {
        Widget mEditor;
        Window mWindow;

        ConfigNode mWeaponConf;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mWeaponConf = loadConfig("gamemode").getSubNode("weapon_sets");

        auto loader = new LoadGui(loadConfig("dialogs/weaponedit_gui"));
        loader.load();

        loader.lookup!(Button)("btn_ok").onClick = &okClick;
        loader.lookup!(Button)("btn_cancel").onClick = &cancelClick;

        mEditor = loader.lookup("weaponedit_root");
        mWindow = gWindowManager.createWindow(this, mEditor,
            r"\t(weaponeditor.caption)");
    }

    private void cancelClick(Button sender) {
        kill();
    }

    private void okClick(Button sender) {
        //
        kill();
    }

    static this() {
        TaskFactory.register!(typeof(this))("weaponeditor");
    }
}
