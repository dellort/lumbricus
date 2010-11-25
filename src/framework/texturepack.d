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
        return do_add(s, s.size);
    }

    ///reserve a region with a specific size
    ///image data covered by SubSurface may be uninitialized
    SubSurface add(Vector2i s) {
        return do_add(null, s);
    }

    //surf can be null (to avoid useless copies in some cases)
    private SubSurface do_add(Surface surf, Vector2i size) {
        Block* b = mPacker.getBlock(size);
        if (!b) {
            //too big, make an exception
            //adhere to copy semantics even here, although it seems extra
            //work (but the caller might free surf after adding it)
            Surface surface;
            if (surf) {
                surface = surf.clone();
            } else {
                surface = new Surface(size);
            }
            mSurfaces ~= surface;
            return surface.createSubSurface(Rect2i(size));
        }
        //check if the BoxPacker added a page and possibly create it
        while (mPacker.pages.length > mPages.length) {
            auto cur = mPages.length;
            auto surface = new Surface(mDefaultSize);
            surface.enableCaching = false;
            mSurfaces ~= surface;
            mPages ~= surface;
        }
        auto dest = mPages[b.page];
        if (surf) {
            dest.copyFrom(surf, b.origin, Vector2i(0), size);
        }
        return dest.createSubSurface(Rect2i.Span(b.origin, size));
    }

    //remove and explicitly free (!) all surfaces returned by add()
    void free() {
        delete mPacker;
        foreach (s; mSurfaces) {
            s.free();
        }
        delete mSurfaces;
    }

    override void dispose() {
        free();
    }

    //all surfaces that have been returned by add()
    //this includes "exceptions" (oversized images)
    Surface[] surfaces() {
        return mSurfaces;
    }

    //enable caches for all surfaces; normally caching (= optimize surface for
    //  read-only access and display rendering) is disabled, because it is
    //  assumed that add() is often called. add() triggers write accesses to
    //  pages, so it's better to have caching disabled.
    //xxx maybe that caching stuff should work automatically (in surface.d)
    void enableCaching() {
        foreach (s; mSurfaces) {
            s.enableCaching = true;
        }
    }
}
