module game.glevel;

import framework.framework;
import levelgen.level;
import utils.vector2;
import utils.log;
import drawing = utils.drawing;
import std.math : sqrt;
import game.physic;

//per pixel metadata (cf. level.level.Lexel)
//collection of flags
//0 currently means pixel is free
enum GLexel : ubyte {
    Null = 0,
    SolidSoft = 1, // destroyable ground
    SolidHard = 2, // undestroyable ground
}

//collision handling
class LevelGeometry : PhysicGeometry {
    GameLevel level;

    bool collide(inout Vector2f pos, float radius) {
        Vector2i dir;
        int pixelcount;

        int iradius = cast(int)radius;

        level.checkAt(toVector2i(pos), iradius, dir, pixelcount);

        //no collided pixels
        if (pixelcount == 0)
            return false;

        //xxx: ??? collided pixels, but no normal -> stuck?
        int n_len = dir.quad_length();
        if (n_len == 0)
            return false;

        //auto len = sqrt(cast(float)n_len);
        //auto normal = toVector2f(dir) / len;
        auto normal = toVector2f(dir).normal;

        //this is most likely mathematical incorrect bullsh*t, but works mostly
        //guess how deep the sphere is inside the landscape by dividing the
        //amount of collided pixel by the amount of total pixels in the circle
        float rx = cast(float)pixelcount / (radius*radius*3.14159);
        auto nf = normal * (rx * radius * 2);

        //the new hopefully less-colliding sphere center
        pos += nf;

        return true;
    }
}

//in-game ("loaded") version of levelgen.level.Level
class GameLevel {
    private int mWidth, mHeight;
    private GLexel[] mPixels;
    private int[][int] mCircles;
    //private int[int] mPixelSum; //don't ask
    //in a cave, the level borders are solid
    private bool mIsCave;
    //offset of the level bitmap inside the world coordinates
    //i.e. worldcoords = mOffset + levelcoords
    private Vector2i mOffset;
    //current water level (may rise during game)
    private uint mWaterLevel;

    package Surface mImage;
    private LevelGeometry mPhysics;

    this(Level level, Vector2i at) {
        assert(level !is null);
        mWidth = level.width;
        mHeight = level.height;
        mIsCave = level.isCave;
        mWaterLevel = level.waterLevel;
        mImage = level.image;
        mImage.forcePixelFormat(gFramework.findPixelFormat(DisplayFormat.RGBA32));
        mOffset = at;
        //copy data array (no one knows why)
        mPixels.length = mWidth*mHeight;
        Lexel[] data = level.data;
        foreach (int n, Lexel x; data) {
            GLexel gl;
            switch (x) {
                case Lexel.FREE: gl = GLexel.Null; break;
                case Lexel.LAND: gl = GLexel.SolidSoft; break;
                case Lexel.SOLID_LAND: gl = GLexel.SolidHard; break;
                default:
                    assert(false);
            }
            mPixels[n] = gl;
        }

        mPhysics = new LevelGeometry();
        mPhysics.level = this;
    }

    private void doDamage(Vector2i pos, int radius) {
        assert(radius >= 0);
        //xxx: see comments for checkAt()... actually it's almost the same code
        auto st = pos - mOffset;
        int[] circle = getCircle(radius);

        for (int y = -radius; y <= radius; y++) {
            int xoffs = radius - circle[y+radius];
            for (int x = -xoffs; x <= xoffs; x++) {
                int lx = st.x + x;
                int ly = st.y + y;
                if (lx >= 0 && lx < mWidth && ly >= 0 && ly < mHeight) {
                    //clear that bit
                    mPixels[ly*mWidth + lx] &= ~GLexel.SolidSoft;
                }
            }
        }
    }

    //render a circle using a special color on the surface
    // blubb = if true, paint on "soft" ground, else paint on free ground
    void circle_masked(Vector2i pos, int radius, Color color, bool blubb,
        void* pixels, uint pitch)
    {
        assert(radius >= 0);
        auto st = pos - mOffset;
        int[] circle = getCircle(radius);

        uint rcolor = colorToRGBA32(color);

        //regarding clipping: could write a clipping- and a non-clipping version

        for (int y = -radius; y <= radius; y++) {
            int ly = st.y + y;
            if (ly < 0 || ly >= mHeight)
                continue;
            int xoffs = radius - circle[y+radius];
            int x1 = st.x - xoffs;
            int x2 = st.x + xoffs + 1;
            //clipping
            x1 = x1 < 0 ? 0 : x1;
            x1 = x1 > mWidth ? mWidth : x1;
            x2 = x2 < 0 ? 0 : x2;
            x2 = x2 > mWidth ? mWidth : x2;
            uint* imgptr = cast(uint*)(pixels+pitch*ly);
            imgptr += x1;
            GLexel* meta = mPixels.ptr + mWidth*ly + x1;
            for (int x = x1; x < x2; x++) {
                bool set = (((*meta & GLexel.SolidSoft) == 0) ^ blubb)
                    & !(*meta & GLexel.SolidHard);
                if (set) {
                    *imgptr = rcolor;
                }
                imgptr++;
                meta++;
            }
        }
    }

    //destroy a part of the landscape
    void damage(Vector2i pos, int radius) {
        /*Canvas c = mImage.startDraw();
        c.drawFilledCircle(pos - mOffset, radius+5, Color(0.7,0.7,0));
        c.drawFilledCircle(pos - mOffset, radius, mImage.colorkey());
        c.endDraw();*/
        doDamage(pos, radius);
        void* pixels; uint pitch;
        mImage.lockPixels(pixels, pitch);
        circle_masked(pos, radius+7, Color(0.5,0.5,0), true, pixels, pitch);
        circle_masked(pos, radius, mImage.colorkey(), false, pixels, pitch);
        mImage.unlockPixels();
    }

    //calculate normal at that position
    //this is (very?) expensive
    //maybe replace it by other methods as used by other worms clones
    // dir = not-notmalized diection which points to the outside of the level
    // count = number of colliding pixels
    void checkAt(Vector2i pos, int radius, out Vector2i dir, out int count) {
        assert(radius >= 0);
        //xxx: maybe add a non-clipping fast path, if it should be needed
        //also could do tricks to avoid clipping at all...!
        auto st = pos - mOffset;
        int[] circle = getCircle(radius);

        //dir and count are initialized with 0

        for (int y = -radius; y <= radius; y++) {
            int xoffs = radius - circle[y+radius];
            for (int x = -xoffs; x <= xoffs; x++) {
                int lx = st.x + x;
                int ly = st.y + y;
                bool isset = mIsCave;
                if (lx >= 0 && lx < mWidth && ly >= 0 && ly < mHeight) {
                    isset = (mPixels[ly*mWidth + lx] != 0);
                }
                if (isset) {
                    dir += Vector2i(x, y);
                    count++;
                }
            }
        }

        dir = -dir;
    }

    /*
     * Return an array, which contains in for each Y-value the X-value of the
     * first point of a filled circle... The Y-value is the index into the
     * array.
     * The circle has the diameter 1+radius*2
     */
    private int[] getCircle(int radius) {
        if (radius in mCircles)
            return mCircles[radius];

        assert(radius >= 0);

        int[] stuff = new int[radius*2+1];
        drawing.circle(radius, radius, radius,
            (int x1, int x2, int y) {
                stuff[y] = x1;
            });
        mCircles[radius] = stuff;
        /*int sum = 0;
        foreach (int i; stuff) {
            sum += (radius-i)*2+1;
        }
        mPixelSum[radius] = sum;*/
        return stuff;
    }

    public uint waterLevel() {
        return mWaterLevel;
    }
    public void waterLevel(uint wlevel) {
        mWaterLevel = wlevel;
    }

    public Surface image() {
        return mImage;
    }

    public Vector2i offset() {
        return mOffset;
    }

    public uint height() {
        return mHeight;
    }

    public uint width() {
        return mWidth;
    }

    public Vector2i levelsize() {
        return Vector2i(mWidth, mHeight);
    }

    public LevelGeometry physics() {
        return mPhysics;
    }
}

/+
tx = x / w
ty = y / h

ox = x % w
oy = y % w

dw=number of tiles
ts=tile size

tile =ty*dw*ts + tx*ts
px = tile + oy*w + ox

//amount of bytes per tile-row
c1=dw*ts

//cy only per scanline
cy = (y >> 5)*c1 + ((y & 31) << 5)
//on each pixel
px=cy + (x >> 5) << 10 + (x & 31)
+/
