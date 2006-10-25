module level.placeobjects;

import level.level;
import framework.framework;

debug import std.stdio;

public class PlaceObjects {
    /// Number of border where the object should be rooted into the landscape
    /// Side.None means the object is placed within the landscape
    public enum Side {
        North, West, South, East, None
    }

    private byte[] mCollide;
    private Surface mTexture;
    private Side mSide;
    private uint mWidth;
    private uint mHeight;
    private uint mDepth;
    private Level mLevel;
    private Vector2i mDir;

    public this(Level level) {
        mLevel = level;
    }

    public Surface objectImage() {
        return mTexture;
    }

    /// Load an object, that should be placed into the object
    /// depth is the amount of pixels, that should be hidden into the land
    /// note that depth is only "approximate"!
    public void loadObject(Surface texture, Side side, uint depth) {
        mCollide = texture.convertToMask();
        mTexture = texture;
        mWidth = texture.size.x;
        mHeight = texture.size.y;
        mSide = side;
        mDepth = depth;
        if (depth > mHeight)
            depth = mHeight;
        switch (side) {
            case Side.North: mDir = Vector2i(0,-1); break;
            case Side.South: mDir = Vector2i(0,1); break;
            case Side.East: mDir = Vector2i(1,0); break;
            case Side.West: mDir = Vector2i(1,0); break;
            default:
                mDir = Vector2i(0,0);
        }
    }

    bool checkCollide(Vector2i at, out Vector2i dir, out uint collisions) {
        Vector2i sp = at - Vector2i(mWidth, mHeight) / 2;
        for (int y = sp.y; y < sp.y+cast(int)mHeight; y++) {
            for (int x = sp.x; x < sp.x+cast(int)mWidth; x++) {
                bool col = true;
                if (x >= 0 && x < mLevel.width && y >= 0 && y < mLevel.height) {
                    col = (mCollide[(y-sp.y)*mWidth+(x-sp.x)] != 0)
                        && (mLevel[x, y] != Lexel.FREE);
                }
                if (col) {
                    collisions++;
                    dir = dir + Vector2i(x, y) - at;
                }
            }
        }

        return (collisions == 0);
    }

    public void placeObject(Vector2i at) {
        auto pos = at - Vector2i(mWidth, mHeight) / 2;

        //create a new surface, draw the object, then the level
        //the level should cover the object, where the level isn't transparent
        //this is hopelessly inefficient (again)
        Surface newlevel = getFramework.createSurface(mLevel.image.size,
            DisplayFormat.Best, Transparency.Colorkey);
        auto canvas2 = newlevel.startDraw();
        canvas2.clear(Color(0, 0, 0, 1.0f));
        canvas2.draw(mTexture, pos);
        canvas2.draw(mLevel.image, Vector2i(0, 0));
        canvas2.endDraw();
        auto canvas = mLevel.image.startDraw();
        //overwrite teh suxors
        canvas.draw(newlevel, Vector2i(0, 0));
        canvas.endDraw();

        //after the image is done, adjust the mask (same task as above, sigh)
        for (uint y = 0; y < mHeight; y++) {
            for (uint x = 0; x < mWidth; x++) {
                if (mCollide[y*mWidth+x]) {
                    uint tx = x+pos.x, ty = y+pos.y;
                    if (tx >= 0 && tx < mLevel.width && ty >= 0 &&
                        ty < mLevel.height)
                    {
                        if (mLevel[tx, ty] == Lexel.FREE) {
                            mLevel[tx, ty] = Lexel.LAND;
                        }
                    }
                }
            }
        }
    }
    
}
