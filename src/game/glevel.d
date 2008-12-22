module game.glevel;

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
import std.math : sqrt, PI;
import physics.world;

//if deactivated, use a rectangle (which surrounds the old circle)
//circular looks better on collisions (reflecting from walls)
//rectangular should be faster and falling down from cliffs looks better
version = CircularCollision;

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

        version (CircularCollision) {
            int iradius = cast(int)radius;
            ls.mLandscape.checkAt(toVector2i(pos) - ls.mOffset,
                iradius, true, dir, pixelcount);
        } else {
            //make it a bit smaller?
            int iradius = cast(int)(radius/5*4);
            ls.mLandscape.checkAt(toVector2i(pos) - ls.mOffset,
                iradius, false, dir, pixelcount);
        }

        //no collided pixels
        if (pixelcount == 0)
            return false;

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

        //this is most likely mathematical incorrect bullsh*t, but works mostly
        //guess how deep the sphere is inside the landscape by dividing the
        //amount of collided pixel by the amount of total pixels in the circle
        float rx = cast(float)pixelcount / totalpixels;
        contact.depth = rx * radius * 2;
        //contact.calcPoint(pos, radius);

        return true;
    }
}

//these 2 functions are used by the server and client code
public void landscapeDamage(LandscapeBitmap ls, Vector2i pos, int radius) {
    //NOTE: clipping should have been done by the caller already, and the
    // blastHole function also does clip; so don't care
    ls.blastHole(pos, radius, cBlastBorder);
}
public void landscapeInsert(LandscapeBitmap ls, Vector2i pos,
    Resource!(Surface) bitmap)
{
    Surface bmp = bitmap.get();
    //whatever the size param is for
    //the metadata-handling is hardcoded, which is a shame
    //currently overwrite everything except SolidHard pixels
    ls.drawBitmap(pos, bmp, bmp.size, Lexel.SolidHard, 0, Lexel.SolidSoft);
}

//handle landscape objects, large damagable static physic objects, represented
//by a bitmap
class GameLandscape : GameObject {
    private {
        LandscapeBitmap mLandscape;
        //offset of the level bitmap inside the world coordinates
        //i.e. worldcoords = mOffset + levelcoords
        Vector2i mOffset;
        Vector2i mSize;

        LandscapeGeometry mPhysics;

        //used to display it in the client
        LandscapeGraphic mGraphic;
    }

    this(GameEngine aengine, LevelLandscape land) {
        assert(land && land.landscape);
        super(aengine, true);

        mSize = land.landscape.size;
        mOffset = land.position;

        //landscape landscape landscape landscape
        mLandscape = new LandscapeBitmap(land.landscape);

        mGraphic = engine.graphics.createLandscape(land, mLandscape);

        init();
    }

    this(GameEngine aengine, Rect2i rc) {
        super(aengine, true);

        mSize = rc.size;
        mOffset = rc.p1;

        mLandscape = new LandscapeBitmap(mSize, null);

        mGraphic = engine.graphics.createLandscape(mSize, mLandscape);

        init();
    }

    this (ReflectCtor c) {
        super(c);
    }

    void init() {
        mGraphic.setPos(mOffset);

        mPhysics = new LandscapeGeometry();
        mPhysics.ls = this;

        //to enable level-bitmap collision
        engine.physicworld.add(mPhysics);
    }

    public void damage(Vector2i pos, int radius) {
        if (radius <= 0)
            return;
        pos -= mOffset;
        auto vr = Vector2i(radius + cBlastBorder);
        if (Rect2i(mSize).intersects(Rect2i(-vr, vr) + pos)) {
            landscapeDamage(mLandscape, pos, radius);
            mPhysics.generationNo++;

            mGraphic.damage(mOffset, radius);
        }
    }

    public void insert(Vector2i pos, Resource!(Surface) bitmap) {
        //not so often called (like damage()), leave clipping to whoever
        pos -= mOffset;
        landscapeInsert(mLandscape, pos, bitmap);
        mPhysics.generationNo++; //?
        mGraphic.insert(pos, bitmap);
    }

    public Surface image() {
        return mLandscape.image;
    }

    public Vector2i offset() {
        return mOffset;
    }

    public Vector2i size() {
        return mSize;
    }

    /+public LandscapeGeometry physics() {
        return mPhysics;
    }+/

    bool activity() {
        return false;
    }
}

