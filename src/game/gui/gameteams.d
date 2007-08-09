///in-game display of team infos
module game.gui.gameteams;

import common.common;
import common.scene;
import common.visual;
import framework.framework;
import gui.container;
import gui.label;
import gui.progress;
import gui.tablecontainer;
import gui.widget;
import game.clientengine;
import game.gamepublic;
import utils.time;
import utils.misc;
import utils.vector2;
import utils.log;

//the team-bars on the bottom of the screen
class TeamWindow : Container {
    int mMaxHealth;
    Foobar[Team] mBars;

    this(Team[] teams) {
        auto table = new TableContainer(2, teams.length, Vector2i(3));
        for (int n = 0; n < teams.length; n++) {
            auto teamname = new Label();
            //xxx proper font and color etc.
            teamname.text = teams[n].name;
            //teamname.border = Vector2i(3,3);
            //xxx code duplication with gameview.d
            teamname.font = globals.framework.fontManager.loadFont("wormfont_"
                ~ cTeamColors[teams[n].color]);
            table.add(teamname, 0, n, WidgetLayout.Aligned(1, 0));
            auto bar = new Foobar();
            //xxx again code duplication from gameview.d
            Color c;
            bool res = parseColor(cTeamColors[teams[n].color], c);
            assert(res);
            bar.fill = c;
            mBars[teams[n]] = bar;
            table.add(bar, 1, n, WidgetLayout.Expand(false));

            mMaxHealth = max(mMaxHealth, teams[n].totalHealth);
        }

        addChild(table);
        table.setLayout(WidgetLayout.Aligned(0, 1, Vector2i(0, 7)));
    }

    void update() {
        foreach (Team team, Foobar bar; mBars) {
            bar.percent = mMaxHealth ? 1.0f*team.totalHealth/mMaxHealth : 0;
        }
    }

    //don't eat mouse events
    override bool testMouse(Vector2i pos) {
        return false;
    }
}