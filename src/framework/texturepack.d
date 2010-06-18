module framework.texturepack;

import framework.surface;
import utils.array;
import utils.boxpacker;
import utils.color;
import utils.rect2;
import utils.vector2;

///add small surfaces to bigger textures
///like utils.BoxPacker (and internally uses it), but with Surfaces
///new surfaces are created with caching disabled (.enableCaching(false))
class TexturePack {
    private {
        BoxPacker mPacker;
        Surface[] mPages, mSurfaces; //mSurfaces = all of mPages + "exceptions"
        Vector2i mDefaultSize;
    }

    ///the size is the minimum size of each page, c.f. add()
    this(Vector2i minsize = Surface.cStdSize) {
        mDefaultSize = minsize;
        mPacker = new BoxPacker();
        mPacker.pageSize = mDefaultSize;
    }

    ///find/create free space on any Surface managed by this class, and copy the
    ///Surface s on it. the function returns the surface it was on and its
    ///position.
    SubSurface add(Surface s) {
        auto size = s.size;
        Block* b = mPacker.getBlock(size);
        if (!b) {
            //too big, make an exception
            //adhere to copy semantics even here, although it seems extra
            //work (but the caller might free s after adding it)
            auto surface = s.clone();
            mSurfaces ~= s;
            return surface.createSubSurface(Rect2i(size));
        }
        //check if the BoxPacker added a page and possibly create it
        while (mPacker.pages.length > mPages.length) {
            auto cur = mPages.length;
            auto surface = new Surface(mDefaultSize,
                s.transparency, s.colorkey());
            surface.enableCaching = false;
            mSurfaces ~= surface;
            mPages ~= surface;
        }
        auto dest = mPages[b.page];
        dest.copyFrom(s, b.origin, Vector2i(0), size);
        return dest.createSubSurface(Rect2i.Span(b.origin, size));
    }

    //remove and explicitly free (!) all surfaces returned by add()
    void free() {
        mPacker = null;
        foreach (s; mSurfaces) {
            s.free();
        }
        mSurfaces = null;
    }

    override void dispose() {
        free();
    }

    int pages() {
        return mSurfaces.length;
    }
}
