module game.glevel;

import common.resset;
import common.scene;
import framework.drawing;
import framework.surface;
import game.core;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.temp : GameZOrder;
import physics.all;
import utils.vector2;
import utils.log;
import utils.misc;

import drawing = utils.drawing;
import tango.math.Math : sqrt, PI;

//if deactivated, use a rectangle (which surrounds the old circle)
//circular looks better on collisions (reflecting from walls)
//rectangular should be faster and falling down from cliffs looks better
version = CircularCollision;

//red border around bitmap
//version = DebugShowLandscape;

//const cLandscapeSnowBit = Lexel.Type_Bit_Min << 0;

uint Landscape_ID;

struct LandscapeData {
    LandscapeGeometry geo;
}

static this() {
    Landscape_ID = getShapeID!(LandscapeData)();
    collidefn!(Circle, LandscapeData)(&collide_circle2ls);
}

private bool collide_circle2ls(void* s1, void* s2, ref Contact contact) {
    Circle* c = cast(Circle*)s1;
    LandscapeData* ls = cast(LandscapeData*)s2;
    return ls.geo.collide(c.pos, c.radius, contact);
}

//collision handling
class LandscapeGeometry : PhysicObject {
    LandscapeBitmap ls;
    LandscapeData data;

    this (LandscapeBitmap a_ls) {
        super(&data, Landscape_ID);
        data.geo = this;
        argcheck(a_ls);
        ls = a_ls;
    }

    private bool collide(Vector2f at, float radius, ref Contact contact) {
        Vector2i dir;
        int pixelcount;
        uint collide_bits;

        auto iat = toVector2i(at);
        auto ioffset = toVector2i(pos);
        version (CircularCollision) {
            int iradius = cast(int)radius;
            ls.checkAt(iat - ioffset, iradius, true, dir, pixelcount,
                collide_bits);
        } else {
            //make it a bit smaller?
            int iradius = cast(int)(radius/5*4);
            ls.checkAt(iat - ioffset, iradius, false, dir, pixelcount,
                collide_bits);
        }

        //Trace.formatln("dir={} pix={}", dir, pixelcount);

        //no collided pixels
        if (pixelcount == 0)
            return false;

        assert (!!collide_bits);

        //collided pixels, but no normal -> stuck
        //there's a hack in physic.d which handles this (the current collide()
        //interface is too restricted, can't handle it directly
        if (dir.x == 0 && dir.y == 0) {
            contact.depth = float.infinity;
            return true;
        }

        //auto len = sqrt(cast(float)n_len);
        //auto normal = toVector2f(dir) / len;
        contact.normal = toVector2f(dir).normal;

        auto realradius = iradius+0.5f; //checkAt checks -radius <= p <= +radius
        version (CircularCollision) {
            auto totalpixels = realradius*realradius*PI;
        } else {
            auto totalpixels = realradius*realradius*4;
        }

        assert (totalpixels == totalpixels);

        //this is most likely mathematical incorrect bullsh*t, but works mostly
        //guess how deep the sphere is inside the landscape by dividing the
        //amount of collided pixel by the amount of total pixels in the circle
        float rx = cast(float)pixelcount / totalpixels;
        contact.depth = rx * radius * 2;
        //contact.calcPoint(at, radius);

        return true;
    }

    override void updatePos() {
        //yyy ls can be null because PhysicObject ctor calls this
        if (ls)
            mBB = Rect2f(pos.x, pos.y, pos.x + ls.size.x, pos.y + ls.size.y);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);
        c.drawRect(toRect2i(mBB), Color(0,1,0));
    }
}

//only point of this indirection: keep zorder; could "solve" this by making
//  GameObject renderable, and assigning them a zorder
//xxx: why is GameLandscape a GameObject anyway?
class RenderLandscape : SceneObject {
    GameLandscape source;
    this(GameLandscape s) {
        source = s;
        zorder = GameZOrder.Landscape;
    }
    override void draw(Canvas c) {
        source.draw(c);
    }
}

//handle landscape objects, large damagable static physic objects, represented
//by a bitmap
class GameLandscape : GameObject {
    private {
        LandscapeBitmap mLandscape;
        LevelLandscape mOriginal;

        LandscapeGeometry mPhysics;

        Surface mBorderSegment;

        Wall[] mWalls;

        struct Wall {
            Vector2i from, to;
        }
    }

    this(GameCore a_engine, LevelLandscape land) {
        assert(land && land.landscape);
        this(a_engine);

        mOriginal = land;

        //landscape landscape landscape
        mLandscape = land.landscape.copy();
        mBorderSegment = engine.resources.get!(Surface)("border_segment");

        init(land.position);
    }

    this(GameCore a_engine, Rect2i rc) {
        this(a_engine);

        mLandscape = new LandscapeBitmap(rc.size);

        init(rc.p1);
    }

    private this(GameCore a_engine) {
        super(a_engine, "landscape");
        internal_active = true;
    }

    void init(Vector2i at) {
        engine.scene.add(new RenderLandscape(this));

        mLandscape.prepareForRendering();

        //to enable level-bitmap collision
        mPhysics = new LandscapeGeometry(mLandscape);
        mPhysics.setPos(toVector2f(at), false);
        mPhysics.isStatic = true;
        engine.physicWorld.add(mPhysics);

        if (!mOriginal)
            return;

        //add borders, sadly they are invisible right now
        void add_wall(Vector2i from, Vector2i to) {
            //worms are "sunken" into the landscape a bit for whatever reason,
            //  have to take this into account for line width
            Line line;
            line.defineStartEnd(toVector2f(to), toVector2f(from), 5);
            auto wall = new PhysicObjectLine(line);
            wall.isStatic = true;
            engine.physicWorld.add(wall);

            mWalls ~= Wall(from, to);
        }

        auto rc = Rect2i.Span(offset, size);
        auto walls = mOriginal.impenetrable;
        if (walls[0]) add_wall(rc.p1, rc.pA);
        if (walls[1]) add_wall(rc.pA, rc.p2);
        if (walls[2]) add_wall(rc.p2, rc.pB);
        if (walls[3]) add_wall(rc.pB, rc.p1);
    }

    public int damage(Vector2i pos, int radius) {
        if (radius <= 0)
            return 0;
        int count;
        pos -= offset;
        auto vr = Vector2i(radius + cBlastBorder);
        if (Rect2i(size).intersects(Rect2i(-vr, vr) + pos)) {
            count = mLandscape.blastHole(pos, radius, cBlastBorder,
                mOriginal ? mOriginal.landscape_theme : null);
        }
        return count;
    }

    public bool lexelTypeAt(Vector2i pos, int radius, Lexel bits) {
        Vector2i tmp1;
        int tmp2;
        uint collide_bits;
        pos -= offset;
        mLandscape.checkAt(pos, radius, true, tmp1, tmp2, collide_bits);
        return (collide_bits & bits) > 0;
    }

    public void insert(Vector2i pos, Surface bitmap, Lexel bits) {
        //not so often called (like damage()), leave clipping to whoever
        pos -= offset;
        mLandscape.drawBitmap(pos, bitmap, bitmap.size, Lexel.SolidHard, 0,
            bits);
    }

    private void draw(Canvas c) {
        mLandscape.draw(c, offset);

        foreach (w; mWalls) {
            c.drawTexLine(w.from, w.to, mBorderSegment, 0, Color(1, 0, 0));
        }

        version (DebugShowLandscape)
            c.drawRect(rect(), Color(1, 0, 0));
    }

    final Vector2i offset() {
        return toVector2i(mPhysics.pos);
    }

    final Vector2i size() {
        return mLandscape.size;
    }

    final Rect2i rect() {
        return Rect2i.Span(offset, size);
    }

    /+public LandscapeGeometry physics() {
        return mPhysics;
    }+/

    bool activity() {
        return false;
    }

    void activate() {
    }

    LandscapeBitmap landscape() {
        return mLandscape;
    }

    override void debug_draw(Canvas c) {
        //c.drawRect(rect, Color(1,0,0));
    }
}

/+

import common.task;
import framework.imgread;
import gui.widget;
import gui.window;

class LevelColTest : Widget {
    LandscapeGeometry geo;
    LandscapeBitmap ls;
    Surface blue, black;

    float fscale = 10;

    this() {
        ls = new LandscapeBitmap(loadImage("ltest.png"));
        geo = new LandscapeGeometry(Vector2f(0), ls);
        Surface colorpix(Color col) {
            auto s = new Surface(Vector2i(1));
            s.fill(s.rect, col);
            return s;
        }
        blue = colorpix(Color(0,0,1));
        black = colorpix(Color(0,0,0));
    }

    override void onDraw(Canvas c) {
        c.pushState();
        c.setScale(Vector2f(fscale));

        ls.draw(c, Vector2i(0));

        void pixcircle(Vector2i at, int radius, Surface pixel) {
            int[] circle = ls.getCircle(radius);
            for (int y = -radius; y <= radius; y++) {
                int xoffs = radius - circle[y+radius];
                int lx1 = at.x - xoffs;
                int lx2 = at.x + xoffs + 1;
                if (!(lx1 < lx2))
                    continue;
                int max_x = lx2;
                for (int x = lx1; x < max_x; x++) {
                    c.draw(pixel, Vector2i(x, y + at.y));
                }
            }
        }

        Vector2i mp = mousePos;
        auto p = toVector2f(mp) / fscale;
        float r = 4;
        pixcircle(toVector2i(p), cast(int)r, black);
        GeomContact contact;
        if (geo.collide(p, r, contact)) {
            auto pn = p + contact.normal * contact.depth;
            c.drawCircle(toVector2i(pn), cast(int)r, Color(0,1,0));
        }
        c.draw(blue, toVector2i(p));

        c.popState();

        c.drawCircle(mp, cast(int)(r*fscale), Color(1,0,0));
    }
}

static this() {
    registerTask("levelcoltest", function(char[] args) {
        gWindowFrame.createWindowFullscreen(new LevelColTest(), "coltest");
    });
}

+/
