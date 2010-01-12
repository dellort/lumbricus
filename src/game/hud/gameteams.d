///in-game display of team infos
module game.hud.gameteams;

import common.common;
import common.scene;
import framework.font;
import framework.framework;
import utils.timesource;
import gui.container;
import gui.label;
import gui.progress;
import gui.rendertext;
import gui.tablecontainer;
import gui.widget;
import game.clientengine;
import game.gfxset;
import game.hud.teaminfo;
import utils.array;
import utils.misc;
import utils.time;
import utils.vector2;

import tango.math.Math : PI;
import marray = utils.array;

class WormLabel : Widget {
    Team team;
    FormattedText txt;

    this(Team team) {
        focusable = false;
        isClickable = false;
        txt = team.color.textCreate();
        txt.setLiteral(team.name);
    }

    override Vector2i layoutSizeRequest() {
        return txt.size();
    }

    void update() {
        needResize();
    }

    override void onDraw(Canvas c) {
        txt.draw(c, Vector2i(0));
    }
}

//the team-bars on the bottom of the screen
class TeamWindow : Widget {
    const Time cSwapLinesDuration = timeMsecs(500);
    const Time cRemoveLinesDuration = timeMsecs(500);
    const Time cDropLineDuration = timeMsecs(150);
    private {
        //for memory managment reasons, make larger if too small
        const cWidgetsPerRow = 3;
        TableContainer mTable;
        PerTeam[Team] mTeam;
        Team[] mLines; //keep track to which team a table line maps
        //if >= 0, the first line when swapping them
        int currentSwapLine = -1; //this and this+1 are the lines being swapped
        Time currentSwapStart;
        int currentRemoveLines = -1; //number of lines which currently move out
        Time currentRemoveStart;
        bool mDropLastLine;
        Time mDropStart;
        bool mUpdating;
        TimeSourcePublic mTimeSource;

        class PerTeam {
            Foobar bar;
            WormLabel global_wins;
            int last_global_wins = -1; //-1: force lazy initialization
        }
    }

    //return if a is less than b... (== a is higher on list than b)
    bool compareTeam(Team a, Team b) {
        return a.totalCurrentHealth() > b.totalCurrentHealth();
    }

    this(GameInfo game) {
        setVirtualFrame(false);

        mTimeSource = game.clientTime;

        //cells both expanded and homogeneous in x-dir => centered correctly
        //will give you headaches if you want more than two columns
        auto table = new TableContainer(3, 0, Vector2i(3, 2),
            [false, true], [true, false]);

        //MAGIC to make column 0 and 2 the same size
        table.setHomogeneousGroup(0, 0, 1);
        table.setHomogeneousGroup(0, 2, 1);

        Team[] teams = game.engine.controller.teams().dup;

        marray.mergeSort(teams, (Team a, Team b) {
            return a.name < b.name;
        });
        marray.mergeSort(teams, (Team a, Team b) {
            return a.globalWins > b.globalWins;
        });
        marray.mergeSort(teams, &compareTeam);

        foreach (t; teams) {
            table.addRow();

            table.add(new WormLabel(t), 0, table.height() - 1,
                WidgetLayout.Aligned(1, 0));

            PerTeam ti = new PerTeam();

            ti.global_wins = new WormLabel(t);
            table.add(ti.global_wins, 1, table.height() -1,
                WidgetLayout.Noexpand());

            ti.bar = new Foobar();
            ti.bar.border = GfxSet.textWormBorderStyle();
            ti.bar.fill = t.color.color;
            WidgetLayout lay; //expand in y, but left-align in x
            lay.alignment[0] = 0;
            lay.expand[0] = false;
            table.add(ti.bar, 2, table.height() - 1, lay);

            mTeam[t] = ti;
            mLines ~= t;

            //mMaxHealth = max(mMaxHealth, teams[n].totalHealth);
        }

        //no clipping because the animation moves the labels outside the
        //clipping area
        table.doClipping = false;
        table.setLayout(WidgetLayout.Aligned(0, 1, Vector2i(0, 7)));

        addChild(table);

        mTable = table;
    }

    /+
    this updates the livepoints etc. from the shared client team infos
    if doanimation is true, the animation as known from worms is started: the
    team labels are resorted and changed until it reflects the actual situation
    it works as follows (similar to bubblesort):
    1. go from top to bottom through the GUI label list
    2. if there is a team which has higher livepoints than the team before, do:
        2.1. move winner up/loser down on a half circle like way
        2.3. the positions are swapped now
             go back to 1. and do everything again
    3. the losers are now at the end, if there are losers which died:
        3.1. move the losers out of the screen ("drop line")
        3.2. move down the rest of the team window ("remove line")
    during all that, animating() returns true
    theres also that thing that the health is counted down, this is in
    gameframe.d; during that update(false) is called to update the bar widths
    +/
    void update(bool doanimation) {
        foreach (Team team, PerTeam ti; mTeam) {
            //bar.percent = mMaxHealth ? 1.0f*team.totalHealth/mMaxHealth : 0;
            //this makes 10 life points exactly a pixel on the screen
            ti.bar.minSize = Vector2i(team.totalCurrentHealth / 10, 0);

            //also does the first time initialization
            auto curwin = team.globalWins();
            if (ti.last_global_wins != curwin) {
                ti.global_wins.txt.setTextFmt(false, "{}", curwin);
                ti.global_wins.update();
                ti.last_global_wins = curwin;
            }
        }

        if (doanimation) {
            mUpdating = true;
        }
    }

    //check step 1., possibly initiate 2.1. (return true then)
    //if you'd need to proceed to step 3. now, return false
    bool checkSort() {
        if (mLines.length == 0)
            return false;
        for (int n = 0; n < mLines.length - 1; n++) {
            if (compareTeam(mLines[n+1], mLines[n])) {
                startSwap(n);
                return true;
            }
        }
        return false;
    }

    //check step 3., possibly initiate 3.1. (return true then)
    bool checkMoveOut() {
        int lines_to_remove = 0;
        for (int n = mLines.length-1; n >= 0; n--) {
            if (mLines[n].totalCurrentHealth > 0)
                break;
            lines_to_remove++;
        }
        if (lines_to_remove == 0)
            return false;
        //initiate 3.1
        mDropLastLine = true;
        mDropStart = mTimeSource.current();
        return true;
    }

    bool swapping() {
        return currentSwapLine >= 0;
    }

    void startSwap(int line) {
        assert(!swapping(), "swapping already in progress!");
        assert(mTable.height() >= 2, "need at least 2 teams");
        assert(line >= 0 && line - 1 < mTable.height());
        currentSwapLine = line;
        currentSwapStart = mTimeSource.current();
    }

    bool removingLines() {
        return currentRemoveLines > 0;
    }

    //initiate animated removal of the last count lines
    void startRemoveLines(int count) {
        assert(!removingLines(), "already in progress");
        assert(count > 0 && count <= mLines.length);
        currentRemoveLines = count;
        currentRemoveStart = mTimeSource.current();
    }

    //probably needed to wait until it's done?
    bool animating() {
        return mUpdating;
    }

    //"how to make simple things complicated"
    override void simulate() {
        if (!mUpdating)
            return;

        Time curt = mTimeSource.current();

        //return all Widgets in this table row
        //mem = trying to avoid memory allocation in a per-frame function
        Widget[] getRow(int row, Widget[] mem) {
            int cnt = 0;
            mTable.findCellsAt(0, row, mTable.width(), 1, (Widget w) {
                assert(cnt < mem.length, "increase cWidgetsPerRow");
                mem[cnt] = w;
                cnt++;
            });
            return mem[0..cnt];
        }

        if (swapping()) {
            Widget[cWidgetsPerRow] alloc_line1, alloc_line2;

            Widget[] line1 = getRow(currentSwapLine, alloc_line1);
            Widget[] line2 = getRow(currentSwapLine + 1, alloc_line2);

            float progress = 1.0f*(curt - currentSwapStart).msecs
                / cSwapLinesDuration.msecs;

            Vector2f delta1, delta2;

            if (progress >= 1.0f) {
                //stop it, _really_ swap table lines and reset positions

                void setRow(Widget[] line, int row) {
                    foreach (Widget w; line) {
                        int x, y, sx, sy;
                        mTable.getChildRowCol(w, x, y, sx, sy);
                        w.remove();
                        mTable.add(w, x, row, sx, sy);
                    }
                }

                setRow(line1, currentSwapLine + 1);
                setRow(line2, currentSwapLine);

                swap(mLines[currentSwapLine + 1], mLines[currentSwapLine]);

                currentSwapLine = -1;

                //positions are reset by letting delta1/delta2 be (0/0)
            } else {
                Vector2i p1 = line1[0].containedBounds.p1;
                Vector2i p2 = line2[0].containedBounds.p1;

                int radius = (p2-p1).y / 2;

                float angle1, angle2;
                //on every line change the side
                if (currentSwapLine % 2) {
                    angle1 = PI/2 + PI + progress*PI;
                    angle2 = PI/2 + progress*PI;
                } else {
                    angle1 = PI/2 + (1.0f - progress)*PI;
                    angle2 = PI/2 + PI + (1.0f - progress)*PI;
                }

                delta1 = Vector2f.fromPolar(radius, angle1);
                delta1.y += radius;
                delta2 = Vector2f.fromPolar(radius, angle2);
                delta2.y -= radius;
            }

            foreach (w; line1) { w.setAddToPos(toVector2i(delta1)); }
            foreach (w; line2) { w.setAddToPos(toVector2i(delta2)); }
        }

        if (removingLines()) {
            //meh that looks exactly like above
            //also, that duration is per line
            float progress = 1.0f*(curt - currentRemoveStart).msecs
                / (cRemoveLinesDuration.msecs*currentRemoveLines) - 0.5f;

            if (progress < 0) {
                //nop, wait
            } else if (progress >= 1.0f) {
                //end of animation, really remove stuff
                mTable.setAddToPos(Vector2i(0));
                for (int n = 0; n < currentRemoveLines; n++) {
                    Widget[cWidgetsPerRow] alloc_line;
                    auto line = getRow(mTable.height(), alloc_line);
                    foreach (w; line) {
                        w.remove();
                    }
                }
                mTable.setSize(mTable.width(), mTable.height()
                    - currentRemoveLines);
                mLines.length = mTable.height();
                currentRemoveLines = -1;
            } else {
                //try to guess how much the table would shrink if you remove the
                //last line
                int r = currentRemoveLines;
                int remove_y = mTable.cellRect(0, mTable.height() - r, 1, r)
                    .size.y + mTable.cellSpacing.y;
                mTable.setAddToPos(Vector2i(0, cast(int)(remove_y*progress)));
            }
        }

        if (mDropLastLine) {
            Widget[cWidgetsPerRow] alloc_line;
            Widget[] line = getRow(mTable.height - 1, alloc_line);

            auto height = mTable.cellRect(0, mTable.height - 1).size.y
                + mTable.cellSpacing.y;
            //gap between table and screen
            height += mTable.findParentBorderDistance(0, 1, true);

            auto f = (curt - mDropStart).secsf / cDropLineDuration.secsf;
            auto y = height * f;
            foreach (w; line) {
                w.setAddToPos(toVector2i(Vector2f(0, y)));
            }

            if (mDropStart + cDropLineDuration < curt) {
                //initiate 3.2
                mDropLastLine = false;
                startRemoveLines(1);
            }
        }

        if (!swapping() && !mDropLastLine && !removingLines()) {
            //d'oh, recheck everything
            mUpdating = checkSort() || checkMoveOut();
        }

        mUpdating = swapping() || mDropLastLine || removingLines();
    }
}
