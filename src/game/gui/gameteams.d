///in-game display of team infos
module game.gui.gameteams;

import common.scene;
import common.visual;
import framework.font;
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
    private {
        //int mMaxHealth;
        Foobar[Team] mBars;
    }

    this(Team[] teams) {
        //cells both expanded and homogeneous in x-dir => centered correctly
        //will give you headaches if you want more than two columns
        auto table = new TableContainer(2, teams.length, Vector2i(3),
            [true, true], [true, false]);

        for (int n = 0; n < teams.length; n++) {
            auto teamname = new Label();
            //xxx proper font and color etc.
            teamname.text = teams[n].name;
            //teamname.border = Vector2i(3,3);
            //xxx again code duplication from gameview.d
            Color c;
            bool res = c.parse(cTeamColors[teams[n].color]);
            assert(res);
            auto st = gFramework.fontManager.getStyle("wormfont");
            st.fore = c;
            teamname.font = new Font(st);
            table.add(teamname, 0, n, WidgetLayout.Aligned(1, 0));
            auto bar = new Foobar();
            bar.fill = c;
            mBars[teams[n]] = bar;
            WidgetLayout lay; //expand in y, but left-align in x
            lay.alignment[0] = 0;
            lay.expand[0] = false;
            table.add(bar, 1, n, lay);

            //mMaxHealth = max(mMaxHealth, teams[n].totalHealth);
        }

        addChild(table);
        table.setLayout(WidgetLayout.Aligned(0, 1, Vector2i(0, 7)));
    }

    void update() {
        foreach (Team team, Foobar bar; mBars) {
            //bar.percent = mMaxHealth ? 1.0f*team.totalHealth/mMaxHealth : 0;
            //this makes 10 life points exactly a pixel on the screen
            bar.width = team.totalHealth / 10;
        }
    }

    //don't eat mouse events
    override bool testMouse(Vector2i pos) {
        return false;
    }
}
