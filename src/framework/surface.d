module framework.surface;

import framework.driver_base;

import utils.color;
import utils.misc;
import utils.rect2;
import utils.vector2;

import rotozoom = framework.rotozoom;
import array = utils.array;

import math = tango.math.Math;
import cstdlib = tango.stdc.stdlib;


//actual surface stored/managed in a driver specific way
//i.e. SDL_Surface for SDL, a texture in OpenGL...
//manually memory managment by the Framework and the Driver
//NOTE: must not keep any permanent references to Surface; otherwise, the GC
//  will never be able to free it
//possible way out: free the driver surface if it hasn't been used for a while
abstract class DriverSurface : DriverResource {
    //set lock flag and make sure the pixeldata is available in Surface; this
    //  simply makes sure the data is present, at least after the next
    //  unlockData() call
    //(a driver might have copied & deallocated Surface's data it before; the
    //  OpenGL driver actually does this by default)
    //the lockData and unlockData calls are only loosely matched (it's ok if
    //  lockData() is called several times without unlockData, etc.)
    void lockData() {}
    //update pixel data; it is unspecified if changes to the pixel data will
    //  be reflected immediately or only after this function is called; also,
    //  the driver may deallocate the pixel data again after this call
    void unlockData(in Rect2i rc) { }
    //notify about new SubSurface instance attached to this Surface
    //if the driver doesn't care about SubSurface, this is just unimplemented
    void newSubSurface(SubSurface ss) { }

    //this returns the actual Surface (the instance is wrapped in a weak
    //  pointer; drivers should never store the Surface directly)
    //may return null in rare cases (Surface has been free'd, but the lazy
    //  notification hasn't triggered destruction of the DriverSurface yet)
    final Surface getSurface() {
        return castStrict!(Surface)(getResource());
    }
}

const int cAlphaTestRef = 128;

//this function by definition returns if a pixel is considered transparent
//dear compiler, you should always inline this
//xxx as of dmd 1.062, the compiler can inline ref functions (dmd bug 2008)
bool pixelIsTransparent(Color.RGBA32* p) {
    //when comparison function is changed, check all code using cAlphaTestRef
    return p.a < cAlphaTestRef;
}

//some good (but completely random) pick for a colorkey
//should be a rarely used color, and be representable in 16 bit colors
//PNG image writer and SDL driver may use this
const Color cStdColorKey = Color(1,0,1,0);

/// a Surface
/// This is used by the user and this also can survive framework driver
/// reinitialization
/// NOTE: this class is used for garbage collection of surfaces (bad idea, but
///       we need it), so be careful with pointers to it
final class Surface : ResourceT!(DriverSurface) {
    private {
        //convert Surface to display format and/or possibly allow stealing
        bool mEnableCache = true;
        bool mLocked;
        Vector2i mSize;
        //if allocated, its .ptr is always !is null, even if size is (0,0)
        //it is null if uninitialized or if surface data has been stolen
        //this field is null if the surface has been completely free'd
        array.BigArray!(Color.RGBA32) mAllocator;

        //the driver can set this
        //the Surface code will call its methods to update the bitmap and so on
        DriverSurface mDriverSurface;

        //indexed by SubSurface.index()
        SubSurface[] mSubsurfaces;

        SubSurface mFullSubSurface;
    }

    ///"best" size for a large texture
    //just needed because OpenGL has an unknown max texture size
    //actually, it doesn't make sense at all
    const cStdSize = Vector2i(512, 512);

    this(Vector2i size) {
        argcheck(size.x >= 0 && size.y >= 0);

        mAllocator = new typeof(mAllocator)();

        mSize = size;

        _pixelsAlloc();

        mFullSubSurface = createSubSurface(rect);
    }

    //trivial accessors
    final SubSurface fullSubSurface() { return mFullSubSurface; }
    final Vector2i size() { return mSize; }
    final Rect2i rect() { return Rect2i(mSize); }

    //--- driver interface

    //alloc/set data
    //size must be set before calling this
    //must only be called internally or by the driver
    void _pixelsAlloc() {
        assert(mAllocator.ptr is null);

        size_t len = mSize.y*mSize.x;

        //make sure mAllocator.ptr will be not null
        if (len == 0) {
            len = 1;
        }

        mAllocator.length = len;
    }

    //free data, but leave everything else intact
    //note that this may be used by the driver to "steal" data (move the data
    //  into the display driver, and free the Surface allocated pixel array)
    //must only be called internally or by the driver
    void _pixelsFree() {
        assert(mAllocator.ptr !is null);

        mAllocator.length = 0;
    }

    //may only be used by driver
    //driver may use _rawPixels().ptr is null to see if data has been "stolen"
    Color.RGBA32[] _rawPixels() {
        return mAllocator[];
    }

    //--- driver interface end

    /// to avoid memory leaks
    override void dispose() {
        //per definition, GC references are still valid when this is called
        //=> unlike in ~this(), can call free() here
        super.dispose();
        assert(!driverResource);
        if (mAllocator)
            mAllocator.length = 0;
        delete mAllocator;
        delete mSubsurfaces;
        mFullSubSurface = null;
    }

    alias dispose free;

    //this is the finalizer (not destructor), usually called by the GC
    //according to D's rules, you must not access other GC references here!
    //this includes mAllocator, driverSurface(), mSubsurfaces...
    ~this() {
        assert(!mLocked, "finalizer called for locked surface!");
    }

    //return null if no DriverSurface is allocated
    final DriverSurface driverSurface() {
        return driverResource();
    }

    //kill driver's surface, probably copy data back
    //this is often used to force recreation of the driver surface when static
    //  surface properties have changed (=> no need to worry about driver)
    final void passivate() {
        unload();
    }

    //see SubSurface
    final SubSurface createSubSurface(Rect2i rc) {
        auto ss = new SubSurface();
        ss.mSurface = this;
        ss.mRect = rc;
        ss.mIndex = mSubsurfaces.length;
        mSubsurfaces ~= ss;
        //notify the driver of the new SubSurface entry
        if (driverSurface) {
            driverSurface.newSubSurface(ss);
        }
        return ss;
    }

    final size_t subsurfaceCount() {
        return mSubsurfaces.length;
    }
    final SubSurface subsurfaceGet(size_t idx) {
        argcheck(indexValid(mSubsurfaces, idx));
        return mSubsurfaces[idx];
    }

    /// accessing pixels with lockPixelsRGBA32() will be S.L.O.W. (depending
    /// from the driver)
    /// if this is true (default value), then:
    /// - OpenGL: will steal data => even reading pixels is extremely slow
    /// - SDL: will convert surface to display format and will RLE compress
    ///   the image data, but reading is still fast (no stealing)
    /// after enabling caching, you can use preload() to do the driver specific
    /// surface conversion as mentioned above (or it will be done on next draw)
    bool enableCaching() {
        return mEnableCache;
    }
    void enableCaching(bool s) {
        if (mEnableCache == s)
            return;
        passivate();
        mEnableCache = s;
    }

    /// direct access to pixels (in Color.RGBA32 format)
    /// must not call any other surface functions (except size()) between this
    ///     and unlockPixels()
    /// pitch is now number of Color.RGBA32 units to advance by 1 line vetically
    /// why not just use size.x? I thought this would provide a simple way to
    ///     represent sub-surfaces (so that a Surface can reference a part of a
    ///     larger Surface), but maybe that idea is already dead...
    //xxx: add a "Rect2i area" parameter to return the pixels for a subrect?
    void lockPixelsRGBA32(out Color.RGBA32* pixels, out uint pitch) {
        assert(!mLocked, "surface already locked!");
        mLocked = true;
        if (driverSurface)
            driverSurface.lockData();
        pixels = mAllocator.ptr;
        assert(!!pixels);
        pitch = mSize.x;
    }
    /// must be called after done with lockPixelsRGBA32()
    /// "rc" is for the offset and size of the region to update
    void unlockPixels(in Rect2i rc) {
        assert(mLocked, "unlock called on unlocked surface");
        mLocked = false;
        if (driverSurface)
            driverSurface.unlockData(rc);
    }

    final Surface clone() {
        return subrect(rect());
    }

    //return a Surface with a copy of a subrectangle of this
    final Surface subrect(Rect2i rc) {
        rc.fitInsideB(rect());
        if (!rc.isNormal()) {
            //completely outside, simply create a 0-sized surface
            //xxx don't know if SDL or OpenGL are ok with this
            rc = Rect2i.init;
        }
        auto sz = rc.size();
        auto s = new Surface(sz);
        s.copyFrom(this, Vector2i(0), rc.p1, sz);
        return s;
    }

    //special thingy needed for SDLFont
    void scaleAlpha(float scale) {
        mapColorChannels((Color c) {
            c.a *= scale;
            return c;
        });
    }

    //see Color.applyBCG()
    void applyBCG(float brightness, float contrast, float gamma) {
        mapColorChannels((Color c) {
            return c.applyBCG(brightness, contrast, gamma);
        });
    }

    ///for each pixel (and color channel) change the color to fn(original_color)
    ///because really doing that for each Color would be too slow, this is only
    ///done per channel (fn() is used to contruct the lookup table)
    void mapColorChannels(Color delegate(Color c) fn) {
        ubyte[256][4] map;
        for (int n = 0; n < 256; n++) {
            Color c;
            c.r = c.g = c.b = c.a = Color.fromByte(n);
            c = fn(c);
            c.clamp();
            Color.RGBA32 c32 = c.toRGBA32();
            map[0][n] = c32.r;
            map[1][n] = c32.g;
            map[2][n] = c32.b;
            map[3][n] = c32.a;
        }
        mapColorChannels(map);
    }

    //change each colorchannel according to colormap
    //channels are r=0, g=1, b=2, a=3
    //xxx is awfully slow
    void mapColorChannels(ubyte[256][4] colormap) {
        Color.RGBA32* data; uint pitch;
        lockPixelsRGBA32(data, pitch);
        for (int y = 0; y < size.y; y++) {
            Color.RGBA32* ptr = data + y*pitch;
            auto w = size.x;
            for (int x = 0; x < w; x++) {
                //if (!isTransparent(*cast(int*)ptr)) {
                    //avoiding bounds checking: array[index] => *(array.ptr + index)
                    ptr.r = *(colormap[0].ptr + ptr.r); //colormap[0][ptr.r];
                    ptr.g = *(colormap[1].ptr + ptr.g); //colormap[1][ptr.g];
                    ptr.b = *(colormap[2].ptr + ptr.b); //colormap[2][ptr.b];
                    ptr.a = *(colormap[3].ptr + ptr.a); //colormap[3][ptr.a];
                //}
                ptr++;
            }
        }
        unlockPixels(rect());
    }

    ///works like Canvas.draw, but doesn't do any blending
    ///xxx bitmap memory must not overlap
    void copyFrom(Surface source, Vector2i destPos, Vector2i sourcePos,
        Vector2i sourceSize)
    {
        //xxx and to avoid blending, I do it manually (Canvas would blend)
        //  some day, this will be a complete SDL clone (that was sarcasm)
        //also, renderer.d has sth. similar
        //SORRY for this implementation
        Rect2i dest = Rect2i(destPos, destPos + sourceSize);
        Rect2i src = Rect2i(sourcePos, sourcePos + sourceSize);
        dest.fitInsideB(rect());
        src.fitInsideB(source.rect());
        if (!dest.isNormal() || !src.isNormal())
            return; //no overlap
        //check memory overlap (slice copying must not overlap, uses memcpy)
        argcheck(!(source is this && dest.intersects(src)),
            "copyFrom(): overlapping memory");
        auto sz = dest.size.min(src.size);
        assert(sz.x >= 0 && sz.y >= 0);
        Color.RGBA32* pdest; uint destpitch;
        Color.RGBA32* psrc; uint srcpitch;
        lockPixelsRGBA32(pdest, destpitch);
        source.lockPixelsRGBA32(psrc, srcpitch);
        pdest += destpitch*dest.p1.y + dest.p1.x;
        psrc += srcpitch*src.p1.y + src.p1.x;
        int adv = sz.x;
        for (int y = 0; y < sz.y; y++) {
            pdest[0 .. adv] = psrc[0 .. adv];
            pdest += destpitch;
            psrc += srcpitch;
        }
        source.unlockPixels(Rect2i.init);
        unlockPixels(Rect2i(dest.p1, dest.p1 + sz));
    }

    ///blit a solid color, non-blending and copying
    void fill(Rect2i rc, Color color) {
        rc.fitInsideB(Rect2i(size));
        if (!rc.isNormal())
            return;
        auto c = color.toRGBA32();
        Color.RGBA32* px; uint pitch;
        lockPixelsRGBA32(px, pitch);
        for (int y = rc.p1.y; y < rc.p2.y; y++) {
            auto dest = px + pitch*y;
            dest[rc.p1.x .. rc.p2.x] = c;
        }
        unlockPixels(rc);
    }

    Surface rotated(float angle, bool interpolate) {
        return rotoscaled(angle, 1.0f, interpolate);
    }

    Surface rotoscaled(float angle, float scale, bool interpolate = true) {
        static rotozoom.Pixels lockpixels(Surface s) {
            rotozoom.Pixels r;
            r.w = s.size.x;
            r.h = s.size.y;
            Color.RGBA32* pixels;
            uint pitch32;
            s.lockPixelsRGBA32(pixels, pitch32);
            r.pitch = pitch32*Color.RGBA32.sizeof;
            r.pixels = pixels;
            return r;
        }
        Surface n;
        void doalloc(out rotozoom.Pixels dst, int w, int h) {
            n = new Surface(Vector2i(w, h));
            n.fill(n.rect, Color.Transparent);
            dst = lockpixels(n);
        }
        //looks like rotozoom uses a reversed rotation direction
        rotozoom.rotozoomSurface(lockpixels(this), -angle/math.PI*180, scale,
            interpolate, &doalloc);
        unlockPixels(Rect2i.init);
        n.unlockPixels(n.rect);
        return n;
    }

    //mirror around x/y-axis
    void mirror(bool x, bool y) {
        Color.RGBA32* data;
        uint pitch;
        lockPixelsRGBA32(data, pitch);
        if (x) pixelsMirrorX(data, pitch, size);
        if (y) pixelsMirrorY(data, pitch, size);
        unlockPixels(rect);
    }
}

//represents a sub rectangle of a Surface
//used to speed up drawing (HOPEFULLY)
final class SubSurface {
    private {
        int mIndex;
        Surface mSurface;
        Rect2i mRect;
    }

    Surface surface() { return mSurface; }
    Vector2i origin() { return mRect.p1; }
    Vector2i size() { return mRect.size; }
    Rect2i rect() { return mRect; }

    //index into the corresponding Surface's SubSurface array
    //can be used by the framework driver to lookup driver specific stuff
    int index() {
        return mIndex;
    }
}

//pixel operations; these are just relatively slow helpers

//copy, and while doing this, convert alpha to colorkey
//src_ptr[] = convert-transparent-to-colorkey(ckey, dst_ptr[])
void blitWithColorkey(Color.RGBA32 ckey, Color.RGBA32[] src, Color.RGBA32[] dst)
{
    assert(src.length == dst.length);
    auto src_ptr = src.ptr;
    auto src_end = src_ptr + src.length;
    auto pix_dst = dst.ptr;
    while (src_ptr < src_end) {
        if (pixelIsTransparent(src_ptr)) {
            *pix_dst = ckey;
        } else {
            *pix_dst = *src_ptr;
        }
        src_ptr++;
        pix_dst++;
    }
}

//pitch is in pixels (4 byte units)
void pixelsMirrorY(Color.RGBA32* data, size_t pitch, Vector2i size) {
    for (uint y = 0; y < size.y; y++) {
        Color.RGBA32* src = data+y*pitch+size.x;
        Color.RGBA32* dst = data+y*pitch;
        for (uint x = 0; x < size.x/2; x++) {
            src--;
            swap(*dst, *src);
            dst++;
        }
    }
}

//pitch is in pixels (4 byte units)
void pixelsMirrorX(Color.RGBA32* data, size_t pitch, Vector2i size) {
    //could be clever and avoid memory allocation; but it isn't worth it
    Color.RGBA32[] tmp = new Color.RGBA32[pitch];
    for (int y = 0; y < size.y/2; y++) {
        int ym = size.y - y - 1;
        tmp[] = data[y*pitch..(y+1)*pitch];
        data[y*pitch..(y+1)*pitch] =
            data[ym*pitch..(ym+1)*pitch];
        data[ym*pitch..(ym+1)*pitch] = tmp;
    }
    delete tmp;
}

enum Transparency : uint {
    None = 0,
    Colorkey = 1,
    Alpha = 2,
}

Transparency mergeTransparency(Transparency base, Transparency part) {
    return base >= part ? base : part;
}

//check that the colorkey isn't used by the image
//if this returns true, blitWithColorkey can be used
//otherwise, you have to find an unique colorkey, or use alpha transparency
bool checkColorkey(Color.RGBA32 ckey, Color.RGBA32[] data) {
    const uint cColorMask = Color.cMaskR | Color.cMaskG | Color.cMaskB;

    uint ckeyval = ckey.uint_val;
    auto pcur = data.ptr;
    auto pend = data.ptr + data.length;
    while (pcur < pend) {
        if ((pcur.uint_val & cColorMask) == ckeyval)
            return false;
        pcur++;
    }
    return true;
}

//check if there are any non/half-transparent areas in the image
//return values:
//  Transparency.None: 100% opaque
//  Transparency.Colorkey: only pixels with 0% or 100% transparency
//  Transparency.Alpha: any alpha values are in use
Transparency checkAlphaness(Color.RGBA32[] data) {
    const uint cAlphaMask = Color.cMaskA;
    const uint cAlphaOpaque = cAlphaMask;
    const uint cAlphaNone = 0;

    auto pcur = data.ptr;
    auto pend = data.ptr + data.length;
    Transparency type;
    while (pcur < pend) {
        uint pixel = pcur.uint_val;
        uint alpha = pixel & cAlphaMask;
        //xxx this is probably too much for a loop that's supposed to be tight?
        if (type == Transparency.None && alpha != cAlphaOpaque)
            type = Transparency.Colorkey;
        if (alpha != cAlphaOpaque && alpha != cAlphaNone) {
            type = Transparency.Alpha;
            break;
        }
        pcur++;
    }
    return type;
}

//analyze the image data and find the "tightest" transparency mode that can be
//  used without damaging the image
//colorkey is only valid if transparency == Transparency.Colorkey
//pitch is in pixels
void checkTransparency(Color.RGBA32[] data, size_t pitch, Vector2i size,
    out Transparency transparency, out Color.RGBA32 colorkey)
{
    transparency = Transparency.None;
    //(putting more effort into finding a colorkey probably doesn't pay off)
    //xxx: some code doesn't react good if the returned colorkey actually
    //  changes, so revisit that if you change it (have fun)
    colorkey = cStdColorKey.toRGBA32();

    for (int y = 0; y < size.y; y++) {
        auto scanline = data[y*pitch .. y*pitch + size.x];
        transparency = mergeTransparency(transparency, checkAlphaness(scanline));
        if (transparency == Transparency.Colorkey) {
            //binary transparency detected; need to find/verify a colorkey
            if (!checkColorkey(colorkey, scanline))
                transparency = Transparency.Alpha;
        }
    }
}
