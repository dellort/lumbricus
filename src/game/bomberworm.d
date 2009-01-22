module game.bomberworm;

import framework.framework;
import framework.event;
import framework.timesource;
import framework.keybindings;
import common.task;
import gui.widget;
import gui.container;
import gui.label;
import gui.wm;
import utils.configfile;
import utils.random;
import utils.time;
import utils.vector2;

import stdx.string;
import stdx.math : abs;

//Pyro clone, which again was a bomberman clone
class BomberWorm : Task {
private:
    const cW = 19, cH = 13;
    const cTileSize = 32;
    const TILE_SIZE = Vector2i(cTileSize);
    const cTileStopWindow = 1; //no movement here
    const Vector2i PLAYER_SIZE = Vector2i(15, 15);
    //how long it takes the player to move one pixel
    const cPlayerSpeed = timeMsecs(10);

    TimeSource mTime;

    GameObject[] mObjects;

    Cell[][] mCells; //addressed mCells[x][y]

    class Cell {
        bool impwall; //impenetrable wall
        bool wall; //blastable one
        //count of flames from all directions
        //temporary during simulation loop
        //directions: (towards) east, north, west, south
        //for each of this, it gives how many flames are going in or out in each
        //flame
        int[4] flames_in;
        int[4] flames_out;

        void killWall() {
            wall = false;
        }
    }

    //position => tile address; returns offset
    Vector2i toTile(Vector2i pos, out int x, out int y) {
        auto p = pos / cTileSize;
        x = p.x;
        y = p.y;
        return pos % cTileSize;
    }
    Vector2i fromTile(int x, int y) {
        return Vector2i(x,y)*cTileSize;
    }

    //typical Pyro grid movement (movement allowed only on the grid lines)
    static Vector2i checkMovement(Vector2i pos, Vector2i dir) {
        //every 2nd grid line is walkable, starting with 1st grid line
        //so work with a double sized tile and move center to (0,0)
        Vector2i offs = ((pos+TILE_SIZE/2*3)%(TILE_SIZE*2))-TILE_SIZE;
        Vector2i npos = pos-offs;
        //fixup incorrect position
        if (offs.x != 0 && offs.y != 0) {
            offs.x = offs.y = 0;
            assert(false);
        }
        //movement into the correct direction?
        if (offs.y == 0 && dir.x) {
            offs.x += dir.x;
        } else if (offs.x == 0 && dir.y) {
            offs.y += dir.y;
        } else if (offs.x == 0 && offs.y == 0) {
            //doesn't matter
            offs.x += dir.x;
        } else {
            //forced side-movement
            int d = offs.x != 0 ? 0 : 1;
            //small "window" with no movement
            if (abs(offs[d]) < cTileSize-cTileStopWindow) {
                static int isign(int i) {
                    if (i>0) return 1; else if (i<0) return -1; return 0;
                }
                offs[d] = offs[d] - abs(dir[!d])*isign(offs[d]);
            }
        }
        return npos+offs;
    }

    class GameObject {
        bool mDead;

        void die() {
            mDead = true;
        }

        void simulate() {
        }

        void draw(Canvas c) {
        }
    }

    class Entity : GameObject {
        Vector2i mPos, mMoveDir;
        Time mMoveSpeed;
        Time mLastMove;
        Vector2i mSize;
        Vector2i mLastDir;

        this(Vector2i size) {
            mLastMove = mTime.current;
            mSize = size;
            mMoveSpeed = cPlayerSpeed;
        }

        void setMove(Vector2i dir) {
            mMoveDir = dir;
        }

        override void simulate() {
            //sry, it requires to walk pixel wise
            while (mTime.current - mLastMove > mMoveSpeed) {
                Vector2i nPos = checkMovement(mPos, mMoveDir);
                //get the new cell, look if walkable
                bool move_ok = true;
                int[2] p;
                int dir = -1;
                Vector2i offs = toTile(nPos, p[0], p[1]);
                offs -= TILE_SIZE/2;
                if (offs.x != 0) {
                    dir = 0;
                } else if (offs.y != 0) {
                    dir = 1;
                }
                if (dir >= 0) {
                    p[dir] += offs[dir] > 0 ? +1 : -1;
                    //p[] is the new cell position, look what's there
                    Cell c = mCells[p[0]][p[1]];
                    move_ok &= !c.impwall && !c.wall;
                }
                Vector2i mv;
                if (move_ok) {
                    mv = nPos-mPos;
                    mPos = nPos;
                }
                if (mv == Vector2i(0))
                    mv = mMoveDir; //attempted movement if no movement
                if (mv != Vector2i(0)) {
                    mLastDir = mv;
                }
                mLastMove += mMoveSpeed;
            }
        }

        override void draw(Canvas c) {
            auto p = mPos - mSize/2;
            c.drawRect(p, p+mSize, Color(0,0,1));
            drawArrow(c, mPos, mLastDir);
        }
    }

    static void drawArrow(Canvas c, Vector2i p, Vector2i d) {
        if (d.length == 0)
            return;
        auto col = Color(0);
        auto x = p+d*10;
        auto b = p+d*7;
        c.drawLine(p, x, col);
        auto x1 = b+d.orthogonal()*3;
        auto x2 = b-d.orthogonal()*3;
        c.drawLine(x, x1, col);
        c.drawLine(x, x2, col);
    }

    class Player : Entity {
        KeyBindings bindings;
        Vector2i state_a, state_b;
        bool drop_bomb;

        this() {
            super(PLAYER_SIZE);
            bindings = new KeyBindings();
        }

        void updateKey(char[] k, bool down) {
            int v = down ? 1 : 0;
            switch (k) {
                case "up": state_a.y = -v; break;
                case "left": state_a.x = -v; break;
                case "down": state_b.y = v; break;
                case "right": state_b.x = v; break;
                case "bomb":
                    if (down)
                        drop_bomb = true;
                    break;
                default:
            }
        }

        override void simulate() {
            auto dir = state_a + state_b;
            setMove(dir);
            if (drop_bomb) {
                drop_bomb = false;
                auto b = new Bomb();
                int x, y;
                toTile(mPos, x, y);
                b.mPos = fromTile(x, y) + TILE_SIZE/2;
                mObjects ~= b;
            }
            super.simulate();
        }
    }

    class Bomb : Entity {
        int strength = 5;
        Time mDropTime;

        this() {
            super(PLAYER_SIZE);
            mDropTime = mTime.current;
        }

        override void simulate() {
            if (mTime.current - mDropTime > timeSecs(1)) {
                //drop explosion and bye
                mObjects ~= new Explosion(mPos, strength>=1 ? strength : 1);
                die();
            }
        }
    }

    class Explosion : GameObject {
        int[2] at;
        int mLength;
        int[4] mStop = [int.max,int.max,int.max,int.max];
        Time mStarted;

        const cDuration = timeMsecs(1000);

        this(Vector2i pos, int strength) {
            assert(strength >= 1);
            mLength = strength;
            mStarted = mTime.current;
            toTile(pos, at[0], at[1]);
        }

        override void simulate() {
            if (mTime.current - mStarted > cDuration) {
                die();
                return;
            }
            //enter explosion flames, they go until they meet a wall
            void drawFlame(int index, int axis, int dir) {
                int[2] add;
                for (int n = 0; n < mLength; n++) {
                    Cell cur = mCells[at[0]+add[0]][at[1]+add[1]];
                    add[axis] += dir;
                    Cell next = mCells[at[0]+add[0]][at[1]+add[1]];
                    int d_in = dir > 0 ? 0 : 2;
                    int d_out = 2 - d_in;
                    if (n > 0) {
                        cur.flames_in[axis+d_in]++;
                    }
                    //walls stop it always
                    if (n == mStop[index])
                        break;
                    if (cur.wall) {
                        cur.killWall();
                        //breakable wall stops it until there
                        mStop[index] = n;
                        break;
                    }
                    if (next.impwall)
                        break;
                    if (n == mLength - 1)
                        break;
                    cur.flames_out[axis+d_out]++;
                }
            }
            drawFlame(0, 0, -1);
            drawFlame(1, 0, +1);
            drawFlame(2, 1, -1);
            drawFlame(3, 1, +1);
            super.simulate();
        }
    }

    class IO : Widget {
        this() {
            //setLayout(WidgetLayout.Aligned(0,0));
        }

        override protected void onDraw(Canvas c) {
            //first draw the static thingies
            for (int x = 0; x < cW; x++) {
                for (int y = 0; y < cH; y++) {
                    Cell cell = mCells[x][y];
                    auto offs = fromTile(x, y);
                    if (cell.impwall) {
                        c.drawFilledRect(offs, offs+TILE_SIZE, Color(1,0,0));
                    } else if (cell.wall) {
                        c.drawFilledRect(offs, offs+TILE_SIZE, Color(0.7));
                    }
                }
            }
            //grid lines for debugging
            auto cGrid = Color(0,1,0);
            for (int x = 0; x < cW/2; x++) {
                auto p1 = fromTile(x*2+1, 1) + TILE_SIZE/2;
                auto p2 = fromTile(x*2+1, cH-2) + TILE_SIZE/2;
                c.drawLine(p1, p2, cGrid);
            }
            for (int y = 0; y < cH/2; y++) {
                auto p1 = fromTile(1, y*2+1) + TILE_SIZE/2;
                auto p2 = fromTile(cW-2, y*2+1) + TILE_SIZE/2;
                c.drawLine(p1, p2, cGrid);
            }
            //entities
            foreach (e; mObjects) {
                e.draw(c);
            }
            //render flames
            for (int x = 0; x < cW; x++) {
                for (int y = 0; y < cH; y++) {
                    Cell cell = mCells[x][y];
                    auto pos = fromTile(x, y) + TILE_SIZE/2;
                    //for each side, there are two types of segments: closing
                    //and continuing
                    //also, there are three middle textures: vertical, horiz.,
                    //or both (where vert and horiz cross)
                    int[4] sidetype; //0 nothing, 1 open, 2 closing
                    int middletype; //0 nothing, 1 horiz, 2 vert, 3 both
                    for (int n = 0; n < 4; n++) {
                        if (cell.flames_in[n] || cell.flames_out[n]) {
                            sidetype[n] = 1;
                        } else if (cell.flames_in[(n+2)%4]
                            || cell.flames_out[(n+2)%4])
                        {
                            sidetype[n] = 2;
                        }
                    }
                    middletype |= (sidetype[0] || sidetype[2]) ? 1 : 0;
                    middletype |= (sidetype[1] || sidetype[3]) ? 2 : 0;
                    //drawing...
                    //quadratic, middle segment is (cSizeH,cSizeH)*2
                    const cSizeH = 5;
                    void drawSide(int index, int axis, int dir) {
                        if (!sidetype[index])
                            return;
                        auto col = Color(0);
                        Vector2i d;
                        d[axis] = dir*cSizeH;
                        auto sp = pos-d;
                        auto p1 = sp-d.orthogonal();
                        auto p2 = sp+d.orthogonal();
                        if (sidetype[(index+2)%4] == 1) {
                            auto p3 = p1, p4 = p2;
                            p3[axis] = pos[axis] - dir * cTileSize/2;
                            p4[axis] = pos[axis] - dir * cTileSize/2;
                            c.drawLine(p1, p3, col);
                            c.drawLine(p2, p4, col);
                        } else {
                            auto p3 = sp;
                            p3[axis] = pos[axis] - dir * cTileSize/2;
                            c.drawLine(p2, p3, col);
                            c.drawLine(p3, p1, col);
                        }
                    }
                    drawSide(0, 0, -1);
                    drawSide(1, 1, -1);
                    drawSide(2, 0, +1);
                    drawSide(3, 1, +1);
                    if (middletype) {
                        auto rc = Rect2i(pos - Vector2i(cSizeH),
                            pos + Vector2i(cSizeH));
                        auto mcol = Color(0);
                        //c.drawRect(m1, m2, mcol);
                        if (middletype == 3) {
                            c.drawCircle(pos, cSizeH, mcol);
                        } else if (middletype == 1) {
                            c.drawLine(rc.p1, rc.pA, mcol);
                            c.drawLine(rc.pB, rc.p2, mcol);
                        } else if (middletype == 2) {
                            c.drawLine(rc.p1, rc.pB, mcol);
                            c.drawLine(rc.pA, rc.p2, mcol);
                        }
                    }
                }
            }
        }

        override protected void onKeyEvent(KeyInfo info) {
            foreach (e; mObjects) {
                auto p = cast(Player)e;
                if (!p)
                    continue;
                char[] bind = p.bindings.findBinding(info);
                if (bind.length) {
                    if (!info.isPress)
                        p.updateKey(bind, info.isDown);
                    return;
                }
            }
        }

        bool canHaveFocus() {
            return true;
        }
        bool greedyFocus() {
            return true;
        }

        Vector2i layoutSizeRequest() {
            return TILE_SIZE ^ Vector2i(cW, cH);
        }
    }

    public this(TaskManager mgr) {
        super(mgr);

        mTime = new TimeSource();
        mTime.update();

        auto window = gWindowManager.createWindow(this, new IO(), "BomberWorm");

        ConfigNode config = gFramework.loadConfig("bomberworm");
        const nPlayers = 1;
        for (int n = 0; n < nPlayers; n++) {
            auto p = new Player();
            p.bindings.loadFrom(config.getSubNode("bindings")
                .getSubNode(format("player%s", n)));
            p.mPos = fromTile(1, 1) + TILE_SIZE/2;
            mObjects ~= p;
        }

        mCells.length = cW;
        for (int x = 0; x < cW; x++) {
            mCells[x].length = cH;
            for (int y = 0; y < cH; y++) {
                mCells[x][y] = new Cell();
            }
        }

        //walls around the level / the wall pieces in between
        for (int y = 0; y < cH; y++) {
            for (int x = 0; x < cW; x++) {
                if (x == 0 || x == cW-1 || y == 0 || y == cH-1) {
                    mCells[x][y].impwall = true;
                } else if ((x%2) == 0 && (y%2) == 0) {
                    mCells[x][y].impwall = true;
                }
            }
        }

        //random blastable walls
        for (int n = 0; n < 100; n++) {
            uint x = rand() % cW;
            uint y = rand() % cH;
            if (!mCells[x][y].impwall) {
                mCells[x][y].wall = true;
            }
        }
    }

    override protected void onFrame() {
        mTime.update();

        for (int x = 0; x < cW; x++) {
            for (int y = 0; y < cH; y++) {
                Cell cell = mCells[x][y];
                cell.flames_in[] = 0;
                cell.flames_out[] = 0;
            }
        }

        foreach (e; mObjects) {
            e.simulate();
        }
        //kill dead ones
        for (int n = mObjects.length - 1; n >= 0; n--) {
            if (mObjects[n].mDead) {
                mObjects = mObjects[0..n] ~ mObjects[n+1..$];
            }
        }
    }

    static this() {
        TaskFactory.register!(typeof(this))("bomberworm");
    }
}
