module game.wtris;

import framework.framework;
import framework.event;
import framework.timesource;
import common.task;
import common.common;
import gui.widget;
import gui.container;
import gui.boxcontainer;
import gui.tablecontainer;
import gui.label;
import std.random;
import utils.time;
import utils.vector2;
import std.string : format;

//registers itself as Task "wtris"
public class WTris : Task {
    private {
        const PIECE_W = 4, PIECE_H = 4;

        //pieces[stone][rotation][x][y]
        alias bool[][] Piece;
        Piece[][] pieces;

        int[][] field; //-1 or stone-number
        int field_w, field_h; //size of field (in pieces)

        struct PieceState {
            int piece = -1, rot;//current_piece index of pieces[] resp. pieces[][]
            int x, y;  //field position, not in pixels
            bool valid() {return piece >= 0;}
        }

        PieceState currentPiece;
        PieceState previewPiece;

        bool removing_lines, game_over, pause;
        //sry! 0==blinking, 1==removing, 2==waiting for 1
        int remove_state;
        int kill_line = -1, killoffset;

        TimeSource thetime;
        Time last_piece;

        const PIECE_STEP_MS = 500;

        Texture boxes;
        const BOX_TYPE_COUNT = 7;
        int PIECE_DRAW_W, PIECE_DRAW_H;

        Widget thegui;

        int lines, speed, points;

        alias void delegate(char[]) SetText;
        SetText set_lines, set_points, set_speed;

        GuiLabel msg;
        SimpleContainer msg_parent;
    }

    private void create_game() {
        //syntax: "stone 1 row 1|stone 1 row 2/stone 2..."
        static char[][] muh = [
            ".x|.xx|.x/.x|xxx/.x|xx|.x/|xxx|.x",
            "|xxxx/.x|.x|.x|.x",
            "|.xx|.xx",
            ".x|.xx|..x/..xx|.xx",
            "..x|.xx|.x/.xx|..xx",
            ".x|.x|.xx/..x|xxx/.xx|..x|..x/xxx|x",
            "..x|..x|.xx/|xxx|..x/.xx|.x|.x/x|xxx"
        ];

        pieces.length = muh.length;
        for (int n = 0; n < muh.length; n++) {
            auto cur = muh[n];
            int rotcount = 1;
            for (int i = 0;i<cur.length;i++) {
                if (cur[i] == '/')
                    rotcount++;
            }
            int curpos = 0;
            int currot = 0;
            pieces[n].length = rotcount;
            foreach (inout x; pieces[n]) {
                x.length = PIECE_W;
                foreach (inout y; x) {
                    y.length = PIECE_H;
                }
            }
            //for each rotation...
            while (curpos < cur.length) {
                //each row
                int curx = 0, cury = 0;
                while (curpos < cur.length) {
                    if (cur[curpos] == '.') {
                        curpos++;
                        curx++;
                    } else if (cur[curpos] == 'x') {
                        curpos++;
                        pieces[n][currot][curx][cury] = true;
                        curx++;
                    } else if (cur[curpos] == '|') {
                        curx = 0; cury++;
                        curpos++;
                    } else if (cur[curpos] == '/') {
                        curpos++;
                        break;
                    }
                }
                currot++;
            }
        }

        field_w = 10;
        field_h = 20;
        field.length = field_w;
        foreach (inout x; field) {
            x.length = field_h;
        }
        do_clear_field();

        stats_reset();
    }

    private void do_clear_field() {
        for (int curx = 0; curx < field_w; curx++) {
            for (int cury = 0; cury < field_h; cury++) {
                field[curx][cury] = -1;
            }
        }
    }

    private bool check_collision(PieceState piece) {
        auto p = pieces[piece.piece][piece.rot];
        for (int x = 0; x < PIECE_W; x++) {
            for (int y = 0; y < PIECE_H; y++) {
                if (p[x][y]) {
                    if ((piece.x+x < 0 || piece.x+x >= field_w || piece.y+y < 0
                        || piece.y+y >= field_h))
                    {
                        return true;
                    } else if (field[piece.x+x][piece.y+y]>=0) {
                        return true;
                    }
                }
            }
        }
        return false;
    }

    private void put_current_piece() {
        if (!currentPiece.valid)
            return;
        auto p = pieces[currentPiece.piece][currentPiece.rot];
        for (int x = 0; x < PIECE_W; x++) {
            for (int y = 0; y < PIECE_H; y++) {
                if (p[x][y]) {
                    auto rx = currentPiece.x;
                    auto ry = currentPiece.y;
                    if (!(rx+x < 0 || rx+x >= field_w || ry+y < 0
                        || ry+y >= field_h))
                    {
                        field[rx+x][ry+y] = currentPiece.piece;
                    }
                }
            }
        }
        currentPiece = PieceState.init;
    }

    private void draw_field(Canvas c, Vector2i off, int piece, int rx, int ry,
        bool blink_on = false)
    {
        Vector2i s = Vector2i(PIECE_DRAW_W, PIECE_DRAW_H);
        Vector2i p = Vector2i(rx, ry).mulEntries(s);
        p += off;
        if (piece >= 0) {
            c.draw(boxes, p, Vector2i(piece*PIECE_DRAW_W, 0), s);
            if (blink_on) {
                c.drawFilledRect(p, p+s, Color(1.0, 1.0, 1.0, 0.5));
            }
        }
    }

    private void draw_piece(Canvas c, Vector2i off, PieceState piece) {
        if (!piece.valid)
            return;
        auto p = pieces[piece.piece][piece.rot];
        for (int x = 0; x < PIECE_W; x++) {
            for (int y = 0; y < PIECE_H; y++) {
                if (p[x][y]) {
                    draw_field(c, off, piece.piece, piece.x+x, piece.y+y);
                }
            }
        }
    }

    private const Vector2i border = {5,5};

    //the main field, and also eat events
    private class GameView : GuiObjectOwnerDrawn {

        override protected void draw(Canvas c) {
            //draw the complete background; could be quite expensive
            c.drawFilledRect(Vector2i(0), size, Color(0.7,0.7,0.7));

            int diff = (thetime.current - last_piece).msecs;
            int foo = cast(int)(PIECE_DRAW_H*(1.0f*diff/PIECE_STEP_MS));

            Vector2i add = border;

            for (int y = field_h-1; y >= 0; y--) {
                //foo is just abused for blinking-animation
                bool blinkline;
                if (remove_state == 0) {
                     blinkline = is_line_full(y) && (foo % 4) < 2;
                }
                if (y == kill_line) {
                    if (remove_state == 1) {
                        add.y += foo - PIECE_DRAW_H;
                    }
                }
                for (int x = 0; x < field_w; x++) {
                    if (field[x][y] >= 0)
                        draw_field(c, add, field[x][y], x, y, blinkline);
                }
            }

            draw_piece(c, border, currentPiece);
        }

        override Vector2i layoutSizeRequest() {
            return Vector2i(field.length*PIECE_DRAW_W,
                field[0].length*PIECE_DRAW_H) + border*2;
        }

        bool canHaveFocus() {
            return true;
        }
        bool greedyFocus() {
            return true;
        }

        override protected bool onKeyDown(char[] bind, KeyInfo key) {
            int rel_x, rel_rot;
            switch (key.code) {
                case Keycode.LEFT: rel_x -= 1; break;
                case Keycode.RIGHT: rel_x += 1; break;
                case Keycode.UP: rel_rot += 1; break;
                case Keycode.DOWN: {
                    move_piece(false);
                    break;
                }
                case Keycode.SPACE: {
                    move_piece(true);
                    break;
                }
                case Keycode.P: {
                    if (!game_over) {
                        pause = !pause;
                        thetime.paused = pause;
                        update_gui();
                    }
                    break;
                }
                case Keycode.N: {
                    reset_game();
                    break;
                }
                default:
                    return false;
            }

            static int realmod(int a, int b) {
                return ((a%b)+b)%b;
            }

            if (pause == false && currentPiece.valid &&
                (rel_rot != 0 || rel_x != 0))
            {
                auto npiece = currentPiece;
                npiece.rot = realmod(rel_rot+npiece.rot,
                    pieces[npiece.piece].length);
                npiece.x += rel_x;
                if (!check_collision(npiece)) {
                    currentPiece = npiece;
                }
            }

            return true;
        }
    }

    private class Preview : GuiObjectOwnerDrawn {
        override protected void draw(Canvas c) {
            draw_piece(c, border, previewPiece);
        }

        override Vector2i layoutSizeRequest() {
            return border*2+Vector2i(PIECE_DRAW_W*PIECE_W,PIECE_DRAW_H*PIECE_H);
        }
    }

    private bool is_line_full(int y) {
        bool complete = true;
        for (int x = 0; x < field_w; x++) {
            complete &= (field[x][y] >= 0);
        }
        return complete;
     }

    //find next complete line >= y_start, or -1
    private int find_complete_line(int y_start = 0) {
        for (int y = y_start; y < field_h; y++) {
            if (is_line_full(y))
                return y;
        }
        //nothing
        return -1;
    }

    //remove the line at at_y (including moving-stuff-down)
    private void remove_line(int at_y) {
        for (int y = at_y; y >= 0; y--) {
            for (int x = 0; x < field_w; x++) {
                field[x][y] = y-1 >= 0 ? field[x][y-1] : -1;
            }
        }
    }

    private void stats_remove_lines(int removed) {
        lines += removed;
        points += removed*removed*speed;
        speed = points/15 + 1;
        if (speed > 8)
            speed = 8; //max. Speed
        update_gui();
    }

    private void stats_reset() {
        lines = 0;
        points = 0;
        speed = 1;
        update_gui();
    }

    private void reset_game() {
        do_clear_field();
        stats_reset();
        currentPiece = previewPiece = PieceState.init;
        game_over = removing_lines = pause = false;
        thetime.resetTime();
        last_piece = last_piece.init;
        update_gui();
    }

    private void preview_select_piece() {
        previewPiece.piece = (rand()+1) % pieces.length;
        previewPiece.rot = rand() % pieces[previewPiece.piece].length;
    }

    private void new_piece() {
        //don't create one if it already exists
        if (currentPiece.valid)
            return;

        if (!previewPiece.valid)
            preview_select_piece();

        currentPiece = previewPiece;
        preview_select_piece();

        currentPiece.x = (field_w-PIECE_W)/2;
        currentPiece.y = 0;

        if (check_collision(currentPiece)) {
            //collision on create -> filled up -> byebye
            put_current_piece();
            game_over = true;
            update_gui();
        }
    }

    private bool moving_ok() {
        return !(game_over || pause || removing_lines);
    }

    private void move_piece(bool drop) {
        if (!moving_ok)
            return;

        if (currentPiece.valid) {
            do {
                auto down = currentPiece;
                down.y += 1;
                if (check_collision(down)) {
                    put_current_piece();
                    currentPiece = PieceState.init;
                    //how many lines got removed
                    int lines;
                    for (int y = 0; y < field_h; y++) {
                        if (is_line_full(y))
                            lines++;
                    }
                    if (lines >= 0) {
                        stats_remove_lines(lines);
                        //will trigger some animation, until it's finally removed
                        removing_lines = true;
                        remove_state = 0;
                        //reset relative time to simplify animation
                        last_piece = thetime.current;
                    }
                    break;
                } else {
                    currentPiece = down;
                }
            } while (drop);
        }
    }

    private void sim(Time cur, Time diff) {
        if (moving_ok && !currentPiece.valid) {
            new_piece();
        }

        if ((cur - last_piece).msecs >= PIECE_STEP_MS) {
            last_piece = cur;
            if (removing_lines) {
                if (remove_state == 0) {
                    //let one timeslice for blinking *g*
                    remove_state = 1;
                } else if (remove_state == 1) {
                    //kill lines (by moving... line by line)
                    kill_line = find_complete_line();

                    if (kill_line < 0) {
                        remove_state = 0;
                        removing_lines = false;
                    } else {
                        remove_line(kill_line);
                    }
                }
            } else {
                //normal move-down
                move_piece(false);
            }
        }
    }

    override protected void onFrame() {
        thetime.update();
        sim(thetime.current, thetime.difference);
    }

    private void createGui() {
        auto contain = new BoxContainer(true, false, 10);
        msg_parent = new SimpleContainer();
        contain.add(msg_parent);

        msg_parent.add(new GameView(), WidgetLayout.Noexpand);

        //added or removed on demand, see update_gui()
        msg = new GuiLabel();
        msg.zorder = 1;

        auto side = new BoxContainer(false, false, 10);
        contain.add(side, WidgetLayout.Border(Vector2i(5)));

        side.add(new Preview(), WidgetLayout.Noexpand);

        auto table = new TableContainer(2, 3, Vector2i(10));
        side.add(table, WidgetLayout());

        SetText addfield(int y, char[] name) {
            auto label = new GuiLabel();
            label.drawBorder = false;
            label.text = name;
            label.font = getFramework.getFont("fps");
            table.add(label, 0, y, WidgetLayout.Aligned(-1, 0));
            auto label2 = new GuiLabel();
            label2.drawBorder = false;
            label2.font = label.font;
            table.add(label2, 1, y, WidgetLayout.Aligned(1, 0));
            return &label2.text;
        }

        set_lines = addfield(0, "Lines:");
        set_points = addfield(1, "Points:");
        set_speed = addfield(2, "Speed:");

        thegui = contain;
    }

    private void update_gui() {
         set_lines(format("%s", lines));
         set_points(format("%s", points));
         set_speed(format("%s", speed));

         bool msg_active;

         if (game_over) {
            msg.text = "Game over! 'n' for new game.";
            msg_active = true;
         } else if (pause) {
            msg.text = "Paused.";
            msg_active = true;
         }

         if (msg_active != (msg.parent is msg_parent)) {
            if (msg_active) {
                msg_parent.add(msg, WidgetLayout.Noexpand);
            } else {
                msg.remove();
            }
         }
    }

    this(TaskManager tm) {
        super(tm);

        thetime = new TimeSource();

        //sry for not using "resources"!
        boxes = globals.loadGraphic("wtrisboxes.png").createTexture();
        PIECE_DRAW_W = boxes.size.x / BOX_TYPE_COUNT;
        PIECE_DRAW_H = boxes.size.y;

        createGui();
        create_game();

        update_gui();

        tm.guiMain.mainFrame.add(thegui, WidgetLayout.Noexpand);
    }

    override protected void onKill() {
        thegui.remove();
    }

    static this() {
        TaskFactory.register!(typeof(this))("wtris");
    }
}