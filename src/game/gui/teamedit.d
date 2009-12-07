module game.gui.teamedit;

import framework.framework;
import framework.i18n;
import common.task;
import common.common;
import common.visual;
import game.gfxset;
import gui.widget;
import gui.edit;
import gui.dropdownlist;
import gui.button;
import gui.wm;
import gui.loader;
import gui.list;
import utils.configfile;
import utils.misc;

class TeamEditorTask : Task {
    private {
        Widget mEditor;
        Window mWindow;

        DropDownList mTeamsDropdown, mControlDropdown;
        EditLine mTeamEdit;
        EditLine[8] mWormEdit;
        Button mColorButton;
        ConfigNode mTeamConf, mTeams;
        ConfigNode mEditedTeam;
        int mNewTeamColIdx = 0;
        int mLastTeamId = -1;
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mTeamConf = loadConfig("teams");
        mTeams = mTeamConf.getSubNode("teams");
        mLastTeamId = mTeamConf.getIntValue("lastid", mLastTeamId);

        auto loader = new LoadGui(loadConfig("dialogs/teamedit_gui"));
        loader.load();

        loader.lookup!(Button)("ok").onClick = &okClick;
        loader.lookup!(Button)("cancel").onClick = &cancelClick;
        loader.lookup!(Button)("deleteteam").onClick = &deleteClick;
        mTeamsDropdown = loader.lookup!(DropDownList)("dd_teams");
        mTeamsDropdown.onSelect = &teamSelect;
        mTeamEdit = loader.lookup!(EditLine)("edit_teamname");
        mTeamEdit.onChange = &teamChange;
        for (int i = 0; i < 8; i++) {
            //hardcoded to 8 teammembers
            mWormEdit[i] = loader.lookup!(EditLine)(myformat("edit_worm{}", i+1));
            mWormEdit[i].onChange = &wormChange;
        }
        mColorButton = loader.lookup!(Button)("colorbutton");
        mColorButton.onClick = &colorClick;
        mControlDropdown = loader.lookup!(DropDownList)("dd_control");
        mControlDropdown.onSelect = &controlSelect;
        mControlDropdown.list.setContents([translate("teameditor.control_def"),
            translate("teameditor.control_wwp")]);

        updateTeams();

        mEditor = loader.lookup("teamedit_root");
        mWindow = gWindowManager.createWindow(this, mEditor,
            translate("teameditor.caption"));
    }

    //update list of teams in dropdown, and choose the first if none selected
    //if listonly = true, doesn't select a team
    private void updateTeams(bool listonly = false) {
        char[][] teams;
        foreach (ConfigNode t; mTeams) {
            teams ~= t.name;
        }
        teams.sort;
        teams ~= translate("teameditor.newteam");
        mTeamsDropdown.list.setContents(teams);
        if (!mEditedTeam && mTeams.count > 0)
            mEditedTeam = mTeams.findNode(teams[0]);
        if (mEditedTeam) {
            mTeamsDropdown.selection = mEditedTeam.name;
            if (!listonly) {
                //refresh fields
                doSelectTeam(mEditedTeam.name);
            }
        } else {
            mTeamsDropdown.selection = "";
            if (!listonly)
                clearDialog(false);
        }
    }

    //clear all editing fields, enabled = false to gray them out
    private void clearDialog(bool enabled) {
        mTeamEdit.text = "";
        mTeamEdit.enabled = enabled;
        foreach (l; mWormEdit) {
            l.text = "";
            l.enabled = enabled;
        }
        showColor(TeamTheme.cTeamColors[0]);
        mControlDropdown.selection = "";
    }

    //set color button to passed team color
    private void showColor(char[] teamCol) {
        mColorButton.styles.replaceRule("*", "border-back-color",
            "team_"~teamCol);
    }

    //Team selection dropdown clicked
    private void teamSelect(DropDownList l) {
        int idx = l.list.selectedIndex;
        if (idx == mTeamsDropdown.list.count-1)
            doSelectTeam("", true);
        else
            doSelectTeam(l.selection);
    }

    private void doSelectTeam(char[] name, bool createNew = false) {
        clearDialog(true);
        if (createNew) {
            //create new team
            //find a unique name first
            int i = 0;
            char[] unnamed = translate("teameditor.defaultteam");
            char[] newName = unnamed;
            if (name.length > 0)
                newName = name;
            while (mTeams.hasNode(newName)) {
                i++;
                newName = myformat("{} {}", unnamed, i);
            }
            //create team
            auto newTeam = mTeams.getSubNode(newName);
            //assign id
            mLastTeamId++;
            newTeam.setIntValue("id", mLastTeamId);
            //set defaults
            newTeam["color"] = TeamTheme.cTeamColors[mNewTeamColIdx];
            //different color for each new team
            mNewTeamColIdx = (mNewTeamColIdx+1) % TeamTheme.cTeamColors.length;
            //Smaller xxx: this should be configurable
            newTeam["weapon_set"] = "default";
            //unsupported for now
            newTeam["grave"] = "0";
            newTeam["control"] = "default";
            mEditedTeam = newTeam;
            updateTeams;
            mTeamEdit.text = "";
            mTeamEdit.claimFocus();
        } else {
            //edit existing
            ConfigNode tNode = mTeams.getSubNode(name);
            assert(tNode);
            mEditedTeam = tNode;

            mTeamEdit.text = mEditedTeam.name;
            int idx = 0;
            foreach (char[] name, char[] val; mEditedTeam.getSubNode("member_names")) {
                if (idx < 8)
                    mWormEdit[idx].text = val;
                idx++;
            }
            showColor(mEditedTeam["color"]);
            if (mEditedTeam["control"] == "default") {
                mControlDropdown.selection = mControlDropdown.list.contents[0];
            } else {
                mControlDropdown.selection = mControlDropdown.list.contents[1];
            }
        }
    }

    //Teamname edited
    private void teamChange(EditLine sender) {
        if (mEditedTeam) {
            if (!mTeams.hasNode(sender.text))
                mEditedTeam.rename(sender.text);
            updateTeams(true);
        }
    }

    //Control dropdown changed
    private void controlSelect(DropDownList l) {
        if (mEditedTeam) {
            int idx = l.list.selectedIndex;
            if (idx > 0)
                mEditedTeam["control"] = "worms";
            else
                mEditedTeam["control"] = "default";
        }
    }

    //A wormlabel changed (updates all of them)
    private void wormChange(EditLine sender) {
        if (mEditedTeam) {
            auto node = mEditedTeam.getSubNode("member_names");
            //lol, can't access a list of nodes by index
            node.clear();
            foreach (EditLine l; mWormEdit) {
                if (l.text.length > 0)
                    node.add("", l.text);
            }
        }
    }

    //delete team button clicked
    private void deleteClick(Button sender) {
        if (mEditedTeam) {
            mTeams.remove(mEditedTeam);
            mEditedTeam = null;
            updateTeams();
        }
    }

    //team color button clicked
    //cycles color to the next in TeamTheme.cTeamColors
    private void colorClick(Button sender) {
        //function in utils.array only works for object arrays
        char[] arrayFindNextStr(char[][] arr, char[] w) {
            if (arr.length == 0)
                return "";

            int found = -1;
            foreach (int i, char[] c; arr) {
                if (w == c) {
                    found = i;
                    break;
                }
            }
            found = (found + 1) % arr.length;
            return arr[found];
        }

        if (mEditedTeam) {
            char[] cur = mEditedTeam["color"];
            mEditedTeam["color"] = arrayFindNextStr(TeamTheme.cTeamColors, cur);
            showColor(mEditedTeam["color"]);
        }
    }

    //save button clicked
    private void okClick(Button sender) {
        mTeamConf.setIntValue("lastid", mLastTeamId);
        saveConfig(mTeamConf, "teams.conf");
        kill();
    }

    private void cancelClick(Button sender) {
        kill();
    }

    static this() {
        TaskFactory.register!(typeof(this))("teameditor");
    }
}
