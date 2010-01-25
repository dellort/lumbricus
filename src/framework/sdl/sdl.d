module framework.sdl.sdl;

import derelict.sdl.sdl;
import tango.stdc.stringz;
import utils.misc;
import framework.framework;
import utils.vector2;
import utils.color;

//this is not really needed; it's just here to make framework.sdl.framework
//more independent from soundmixer.d, so sdl_mixer can be kept out more easily
private static int gSDLLoadCount = 0;

void sdlInit() {
    gSDLLoadCount++;
    if (gSDLLoadCount == 1) {
        //the following calls are not recursive

        DerelictSDL.load();

        //probably really needed, don't know
        if (SDL_Init(0) < 0) {
            throw new FrameworkException(myformat("Could not init SDL: {}",
                fromStringz(SDL_GetError())));
        }
    }
}

void sdlQuit() {
    gSDLLoadCount--;
    assert(gSDLLoadCount >= 0);
    if (gSDLLoadCount == 0) {
        SDL_Quit();
        DerelictSDL.unload();
    }
}

//additional utility functions

char[] pixelFormatToString(SDL_PixelFormat* fmt) {
    return myformat("bits={} R/G/B/A={:x8}/{:x8}/{:x8}/{:x8}",
        fmt.BitsPerPixel, fmt.Rmask, fmt.Gmask, fmt.Bmask, fmt.Amask);
}

//convert SDL color to our Color struct; do _not_ try to check the colorkey
//to convert it to a transparent color, and also throw away the alpha value
//there doesn't seem to be a SDL version for this, I hate SDL!!!
Color fromSDLColor(SDL_PixelFormat* fmt, uint c) {
    Color r;
    if (!fmt.palette) {
        //warning, untested (I think, maybe)
        float conv(uint mask, uint shift, uint loss) {
            return (((c & mask) >> shift) << loss)/255.0f;
        }
        r.r = conv(fmt.Rmask, fmt.Rshift, fmt.Rloss);
        r.g = conv(fmt.Gmask, fmt.Gshift, fmt.Gloss);
        r.b = conv(fmt.Bmask, fmt.Bshift, fmt.Bloss);
    } else {
        //palette... sigh!
        assert(c < fmt.palette.ncolors, "WHAT THE SHIT");
        SDL_Color s = fmt.palette.colors[c];
        r.r = s.r/255.0f;
        r.g = s.g/255.0f;
        r.b = s.b/255.0f;
        r.a = s.unused/255.0f;
        assert(ColorToSDLColor(r) == s);
    }
    return r;
}

//warning: modifies the source surface! (changes transparency modes)
Surface convertFromSDLSurface(SDL_Surface* surf, Transparency transparency,
    bool free_surf)
{
    if (transparency == Transparency.AutoDetect) {
        //guess by looking at the alpha channel
        if (sdlIsAlpha(surf)) {
            transparency = Transparency.Alpha;
        } else if (surf.flags & SDL_SRCCOLORKEY) {
            transparency = Transparency.Colorkey;
        } else {
            transparency = Transparency.None;
        }
    }

    bool hascc = transparency == Transparency.Colorkey;
    Color colorkey = Color(0);

    if (hascc) {
        //NOTE: the png loader from SDL_Image sometimes uses the colorkey
        colorkey = fromSDLColor(surf.format, surf.format.colorkey);
    }

    Surface res = new Surface(Vector2i(surf.w, surf.h), transparency,
        colorkey);

    Color.RGBA32* ptr;
    uint pitch;

    res.lockPixelsRGBA32(ptr, pitch);
    assert(pitch == res.size.x); //lol, for block copy

    bool not_crap = !!(surf.flags & SDL_SRCALPHA);

    //possibly convert it to RGBA32 (except if it is already)
    //if there's a colorkey, always convert, hoping the alpha channel gets
    //fixed (setting the alpha according to colorkey)
    auto rgba32 = sdlpfRGBA32();
    if (!(not_crap && cmpPixelFormat(surf.format, &rgba32))) {
        SDL_Surface* ns = SDL_CreateRGBSurfaceFrom(ptr,
            surf.w, surf.h, rgba32.BitsPerPixel, pitch*Color.RGBA32.sizeof,
            rgba32.Rmask, rgba32.Gmask, rgba32.Bmask, rgba32.Amask);
        if (!ns)
            throw new FrameworkException("out of memory?");
        SDL_SetAlpha(surf, 0, 0);  //lol SDL, disable all transparencies
        //not sure about this, but commenting this seems to work better with
        //paletted+transparent png files (but only in OpenGL mode lol)
        //by the way, using SDL_ConvertSurface worked even worse
        //SDL_SetColorKey(surf, 0, 0);
        SDL_FillRect(ns, null, 0); //transparent background
        SDL_BlitSurface(surf, null, ns, null);
        SDL_FreeSurface(ns);
        //xxx: need to restore for surf what was destroyed by SDL_SetAlpha
    } else {
        //just copy the data
        SDL_LockSurface(surf);
        ptr[0..res.size.x*res.size.y] = cast(Color.RGBA32[])
            (surf.pixels[0 .. surf.w*surf.h*surf.format.BytesPerPixel]);
        SDL_UnlockSurface(surf);
    }

    res.unlockPixels(res.rect());

    if (free_surf) {
        SDL_FreeSurface(surf);
    }

    return res;
}

//ignore_a_alpha_bla = ignore alpha, if there's no alpha channel for a
bool cmpPixelFormat(SDL_PixelFormat* a, SDL_PixelFormat* b,
    bool ignore_a_alpha_bla = false)
{
    return (a.BitsPerPixel == b.BitsPerPixel
        && a.Rmask == b.Rmask
        && a.Gmask == b.Gmask
        && a.Bmask == b.Bmask
        && (ignore_a_alpha_bla && a.Amask == 0
            ? true : a.Amask == b.Amask));
}

uint simpleColorToSDLColor(SDL_Surface* s, Color color) {
    auto c = color.toRGBA32();
    return SDL_MapRGBA(s.format, c.r, c.g, c.b, c.a);
}

SDL_Color ColorToSDLColor(Color color) {
    auto c = color.toRGBA32();
    SDL_Color col;
    col.r = c.r;
    col.g = c.g;
    col.b = c.b;
    col.unused = c.a;
    return col;
}

bool sdlIsAlpha(SDL_Surface* s) {
    return s.format.Amask != 0 && (s.flags & SDL_SRCALPHA);
}

//valid fields: BitsPerPixel, Rmask, Gmask, Bmask, Amask
//return value corresponds bit-by-bit to Color.RGBA32
SDL_PixelFormat sdlpfRGBA32() {
    SDL_PixelFormat rRGBA32;
    rRGBA32.BitsPerPixel = 32;
    rRGBA32.Rmask = Color.cMaskR;
    rRGBA32.Gmask = Color.cMaskG;
    rRGBA32.Bmask = Color.cMaskB;
    rRGBA32.Amask = Color.cMaskA;
    return rRGBA32;
}

