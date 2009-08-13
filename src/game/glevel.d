module game.glevel;

import common.resset;
import framework.framework;
import game.gamepublic;
import game.game;
import game.gobject;
import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import utils.vector2;
import utils.log;
import utils.misc;
import utils.reflection;
import drawing = utils.drawing;
import tango.math.Math : sqrt, PI;
import physics.world;

//if deactivated, use a rectangle (which surrounds the old circle)
//circular looks better on collisions (reflecting from walls)
//rectangular should be faster and falling down from cliffs looks better
version = CircularCollision;

const cLandscapeSnowBit = Lexel.Type_Bit_Min << 0;

//collision handling
class LandscapeGeometry : PhysicGeometry {
    GameLandscape ls;

    this (ReflectCtor c) {
    }
    this () {
    }

    bool collide(Vector2f pos, float radius, out GeomContact contact) {
        Vector2i dir;
        int pixelcount;
        uint collide_bits;

        version (CircularCollision) {
            int iradius = cast(int)radius;
            ls.mLandscape.checkAt(toVector2i(pos) - ls.mOffset,
                iradius, true, dir, pixelcount, collide_bits);
        } else {
            //make it a bit smaller?
            int iradius = cast(int)(radius/5*4);
            ls.mLandscape.checkAt(toVector2i(pos) - ls.mOffset,
                iradius, false, dir, pixelcount, collide_bits);
        }

        //no collided pixels
        if (pixelcount == 0)
            return false;

        assert (!!collide_bits);

        //xxx: hardcoded physics properties
        if (collide_bits & cLandscapeSnowBit) {
            //this means snow removes all friction (?)
            contact.friction = 0.0f;
        }

        //collided pixels, but no normal -> stuck
        //there's a hack in physic.d which handles this (the current collide()
        //interface is too restricted, can't handle it directly
        int n_len = dir.quad_length();
        if (n_len == 0) {
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
        //contact.calcPoint(pos, radius);

        return true;
    }
}

//these 2 functions are used by the server and client code (network case)
public int landscapeDamage(LandscapeBitmap ls, Vector2i pos, int radius,
    LandscapeTheme theme)
{
    //NOTE: clipping should have been done by the caller already, and the
    // blastHole function also does clip; so don't care
    return ls.blastHole(pos, radius, cBlastBorder, theme);
}
public void landscapeInsert(LandscapeBitmap ls, Vector2i pos, Surface bitmap,
    Lexel bits)
{
    //whatever the size param is for
    //the metadata-handling is hardcoded, which is a shame
    //currently overwrite everything except SolidHard pixels
    ls.drawBitmap(pos, bitmap, bitmap.size, Lexel.SolidHard, 0, bits);
}

//handle landscape objects, large damagable static physic objects, represented
//by a bitmap
class GameLandscape : GameObject {
    private {
        LandscapeBitmap mLandscape;
        LevelLandscape mOriginal;
        //offset of the level bitmap inside the world coordinates
        //i.e. worldcoords = mOffset + levelcoords
        Vector2i mOffset;
        Vector2i mSize;

        LandscapeGeometry mPhysics;

        //used to display it in the client
        LandscapeGraphic mGraphic;
        Surface mBorderSegment;
    }

    this(GameEngine aengine, LevelLandscape land) {
        assert(land && land.landscape);
        super(aengine, true);

        mOriginal = land;
        mSize = land.landscape.size;
        mOffset = land.position;

        //landscape landscape landscape
        mLandscape = land.landscape.copy();
        mBorderSegment = engine.gfx.resources.get!(Surface)("border_segment");

        init();
    }

    this(GameEngine aengine, Rect2i rc) {
        super(aengine, true);

        mSize = rc.size;
        mOffset = rc.p1;

        mLandscape = new LandscapeBitmap(mSize);

        init();
    }

    this (ReflectCtor c) {
        super(c);
    }

    void init() {
        mGraphic = new LandscapeGraphic(mOffset, mLandscape);
        engine.graphics.add(mGraphic);

        mPhysics = new LandscapeGeometry();
        mPhysics.ls = this;

        //to enable level-bitmap collision
        engine.physicworld.add(mPhysics);

        if (!mOriginal)
            return;

        //add borders, sadly they are invisible right now
        void add_wall(Vector2i from, Vector2i to) {
            auto wall = new PlaneGeometry(toVector2f(to), toVector2f(from));
            engine.physicworld.add(wall);

            auto border = new LineGraphic();
            border.setColor(Color(0.5));
            border.setWidth(5);
            border.setTexture(mBorderSegment);
            border.setPos(from, to);
            engine.graphics.add(border);
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
        pos -= mOffset;
        auto vr = Vector2i(radius + cBlastBorder);
        if (Rect2i(mSize).intersects(Rect2i(-vr, vr) + pos)) {
            count = landscapeDamage(mLandscape, pos, radius,
                mOriginal ? mOriginal.landscape_theme : null);
            mPhysics.generationNo++;

            //this was for replication of the bitmap over network
            //mGraphic.damage(mOffset, radius);
        }
        return count;
    }

    public void insert(Vector2i pos, Surface bitmap, Lexel bits) {
        //not so often called (like damage()), leave clipping to whoever
        pos -= mOffset;
        landscapeInsert(mLandscape, pos, bitmap, bits);
        mPhysics.generationNo++; //?
        //mGraphic.insert(pos, bitmap);
    }

    public Surface image() {
        return mLandscape.image;
    }

    public LandscapeBitmap landscape_bitmap() {
        return mLandscape;
    }

    final Vector2i offset() {
        return mOffset;
    }

    final Vector2i size() {
        return mSize;
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

    override void debug_draw(Canvas c) {
        //c.drawRect(rect, Color(1,0,0));
    }
}

