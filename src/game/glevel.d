module game.glevel;

import framework.framework;
import levelgen.level;
import utils.vector2;
import utils.log;

//per pixel metadata (cf. level.level.Lexel)
enum GLexel : ubyte {
    Free,
    SolidSoft,
    SolidHard,
}

//in-game ("loaded") version of levelgen.level.Level
class GameLevel {
    private int mWidth, mHeight;
    private GLexel[] mPixels;
    private int[][uint] mCircles;
    //in a cave, the level borders are solid
    private bool mIsCave;
    //offset of the level bitmap inside the world coordinates
    //i.e. worldcoords = mOffset + levelcoords
    private Vector2i mOffset;
    //current water level (may rise during game)
    private uint mWaterLevel;
    package Surface mImage;

    this(Level level, Vector2i at) {
        assert(level !is null);
        mWidth = level.width;
        mHeight = level.height;
        mIsCave = level.isCave;
        mWaterLevel = level.waterLevel;
        mImage = level.image;
        mOffset = at;
        //copy data array (no one knows why)
        mPixels.length = mWidth*mHeight;
        Lexel[] data = level.data;
        foreach (int n, Lexel x; data) {
            GLexel gl;
            switch (x) {
                case Lexel.FREE: gl = GLexel.Free; break;
                case Lexel.LAND: gl = GLexel.SolidSoft; break;
                case Lexel.SOLID_LAND: gl = GLexel.SolidHard; break;
                default:
                    assert(false);
            }
            mPixels[n] = gl;
        }
    }

    //calculate normal at that position
    //this is (very?) expensive
    Vector2i normalAt(Vector2i pos, int radius) {
        assert(radius >= 0);
        //xxx: maybe add a non-clipping fast path, if it should be needed
        //also could do tricks to avoid clipping at all...!
        auto st = pos + mOffset;
        int[] circle = getCircle(radius);

        Vector2i res; //init with 0, 0

        for (int y = -radius; y <= radius; y++) {
            int xoffs = radius - circle[y+radius];
            for (int x = -xoffs; x <= xoffs; x++) {
                int lx = st.x + x;
                int ly = st.y + y;
                bool isset = mIsCave;
                if (lx >= 0 && lx < mWidth && ly >= 0 && ly < mHeight) {
                    isset = (mPixels[ly*mWidth + lx] != GLexel.Free);
                }
                if (!isset) {
                    res += Vector2i(x, y);
                }
            }
        }

        return res;
    }

    /*
     * Return an array, which contains in for each Y-value the X-value of the
     * first point of a filled circle... The Y-value is the index into the
     * array.
     * The circle has the diameter 1+radius*2
     */
    private int[] getCircle(uint radius) {
        if (radius in mCircles)
            return mCircles[radius];

        if (radius == 0)
            return null;

        //copied from sdl_gfx (and modified)
        //original: sdlgfx-2.0.9, SDL_gfxPrimitives.c: filledCircleColor()
        void circle(int x, int y, int r,
            void delegate(int x1, int x2, int y) cb)
        {
            if (r <= 0)
                return;

            int cx = 0, cy = r;
            int ocx = cx-1, ocy = cy+1;
            int df = r - 1;
            int d_e = 3;
            int d_se = -2 * r + 5;

            bool draw = true;

            do {
                if (draw) {
                    if (cy > 0) {
                        cb(x - cx, x + cx, y + cy);
                        cb(x - cx, x + cx, y - cy);
                    } else {
                        cb(x - cx, x + cx, y);
                    }
                    //ocy = cy;
                    draw = false;
                }
                if (cx != cy) {
                    if (cx) {
                        cb(x - cy, x + cy, y - cx);
                        cb(x - cy, x + cy, y + cx);
                    } else {
                        cb(x - cy, x + cy, y);
                    }
                }
                if (df < 0) {
                    df += d_e;
                    d_e += 2;
                    d_se += 2;
                } else {
                    df += d_se;
                    d_e += 2;
                    d_se += 4;
                    cy--;
                    draw = true;
                }
                cx++;
            } while (cx <= cy);
        }

        int[] stuff = new int[radius*2+1];
        circle(radius, radius, radius,
            (int x1, int x2, int y) {
                stuff[y] = x1;
            });
        mCircles[radius] = stuff;
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
}
