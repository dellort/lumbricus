module framework.texturepack;

import framework.framework;
import utils.array;
import utils.boxpacker;
import utils.rect2;
import utils.vector2;

///part of a Surface, also returned by TexturePack
struct TextureRef {
    Surface surface;
    Vector2i origin, size;

    bool valid() {
        return surface !is null;
    }

    Rect2i rect() {
        return Rect2i(origin, origin + size);
    }

    void draw(Canvas c, Vector2i at) {
        c.draw(surface, at, origin, size);
    }
}

///add small surfaces to bigger textures
///like utils.BoxPacker (and internally uses it), but with Surfaces
///new surfaces are created with caching ddisabled (.enableCaching(false))
class TexturePack {
    private {
        Packer[TexTypeKey] mPackers;
        Vector2i mDefaultSize;

        struct TexTypeKey {
            Transparency transparency;
            Color colorkey;
        }
    }

    ///the size is the minimum size of each page, c.f. add()
    this(Vector2i minsize = Surface.cStdSize) {
        mDefaultSize = minsize;
    }

    ///find/create free space on any Surface managed by this class, and copy the
    ///Surface s on it. the function returns the surface it was on and its
    ///position.
    TextureRef add(Surface s) {
        auto k = TexTypeKey(s.transparency, s.getColorkey());
        Packer packer = aaIfIn(mPackers, k);
        if (!packer) {
            packer = new Packer();
            mPackers[k] = packer;
        }
        return packer.add(s);
    }

    //remove and explicitly free (!) all surfaces returned by add()
    void free() {
        foreach (p; mPackers) {
            p.free();
        }
        mPackers = null;
    }

    int pages() {
        int sum;
        foreach (p; mPackers) {
            sum += p.mSurfaces.length;
        }
        return sum;
    }

    private class Packer {
        BoxPacker mPacker;
        Surface[] mSurfaces;

        this() {
            mPacker = new BoxPacker();
            mPacker.pageSize = mDefaultSize;
        }

        TextureRef add(Surface s) {
            auto size = s.size;
            if (size.x > mPacker.pageSize.x || size.y > mPacker.pageSize.y) {
                //too big, make an exception
                //don't add the Surface to mSurfaces, because when we add the
                //original Surface s, it will get free'd with free()
                //xxx: or should we copy them...? I think we should (who cares)
                return TextureRef(s, Vector2i(0), size);
            }
            Block* b = mPacker.getBlock(size);
            assert(!!b);  //never happens?
            //check if the BoxPacker added a page and possibly create it
            while (mPacker.pages.length > mSurfaces.length) {
                auto cur = mSurfaces.length;
                auto surface = gFramework.createSurface(mDefaultSize,
                    s.transparency, s.getColorkey());
                surface.enableCaching = false;
                mSurfaces ~= surface;
            }
            auto dest = mSurfaces[b.page];
            dest.copyFrom(s, b.origin, Vector2i(0), size);
            return TextureRef(dest, b.origin, size);
        }

        void free() {
            mPacker = null;
            foreach (s; mSurfaces) {
                s.free();
            }
            mSurfaces = null;
        }
    }
}
