module game.glevel;

import framework.framework;
import levelgen.level;
import levelgen.renderer;
import utils.vector2;
import utils.log;
import utils.misc;
import drawing = utils.drawing;
import std.math : sqrt, PI;
import game.physic;

//if deactivated, use a rectangle (which surrounds the old circle)
//circular looks better on collisions (reflecting from walls)
//rectangular should be faster and falling down from cliffs looks better
version = CircularCollision;

//collision handling
class LevelGeometry : PhysicGeometry {
    GameLevel level;

    bool collide(inout Vector2f pos, float radius) {
        Vector2i dir;
        int pixelcount;

        version (CircularCollision) {
            int iradius = cast(int)radius;
            level.mLevel.checkAt(toVector2i(pos) - level.mOffset,
                iradius, true, dir, pixelcount);
        } else {
            //make it a bit smaller?
            int iradius = cast(int)(radius/5*4);
            level.mLevel.checkAt(toVector2i(pos) - level.mOffset,
                iradius, false, dir, pixelcount);
        }

        //no collided pixels
        if (pixelcount == 0)
            return false;

        //collided pixels, but no normal -> stuck
        //there's a hack in physic.d which handles this (the current collide()
        //interface is too restricted, can't handle it directly
        int n_len = dir.quad_length();
        if (n_len == 0)
            return true;

        //auto len = sqrt(cast(float)n_len);
        //auto normal = toVector2f(dir) / len;
        auto normal = toVector2f(dir).normal;

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
        auto nf = normal * (rx * radius * 2);

        //the new hopefully less-colliding sphere center
        pos += nf;

        return true;
    }
}

//in-game ("loaded") version of levelgen.level.Level
class GameLevel {
    private LevelBitmap mLevel;
    //private int[int] mPixelSum; //don't ask
    //in a cave, the level borders are solid
    private bool mIsCave;
    //offset of the level bitmap inside the world coordinates
    //i.e. worldcoords = mOffset + levelcoords
    private Vector2i mOffset;
    private Vector2i mSize;
    //initial water level
    private uint mWaterLevel;

    private LevelGeometry mPhysics;

    this(Level level, Vector2i at) {
        assert(level !is null);
        mSize = level.size;
        mIsCave = level.isCave;
        mWaterLevel = level.waterLevel;
        mOffset = at;

        mLevel = new LevelBitmap(level);

        mPhysics = new LevelGeometry();
        mPhysics.level = this;
    }

    public void damage(Vector2i pos, int radius) {
        if (radius <= 0)
            return;
        mLevel.blastHole(pos - mOffset, radius);
        mPhysics.generationNo++;
    }

    public uint waterLevelInit() {
        return mWaterLevel;
    }

    public Surface image() {
        return mLevel.image;
    }

    public Vector2i offset() {
        return mOffset;
    }

    public Vector2i size() {
        return mSize;
    }

    public LevelGeometry physics() {
        return mPhysics;
    }
}

