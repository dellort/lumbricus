import derelict.sdl.sdl;
import derelict.sdl.image;

import stdx.stdio;
import str = stdx.string;

//take a filename as argument, load it with sdl_image, output pixelformat
//useful for debugging
void main(char[][] args) {
    DerelictSDL.load();
    DerelictSDLImage.load();
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Surface* s = IMG_Load(str.toStringz(args[1]));
    writefln("size: %sx%s", s.w, s.h);
    SDL_PixelFormat* f = s.format;
    writefln("format: bits/bytes %s/%s, r/g/b/a mask %s/%s/%s/%s",
        f.BitsPerPixel, f.BytesPerPixel, f.Rmask, f.Gmask, f.Bmask, f.Amask);
    writefln("colorkey: %#x", f.colorkey);
    writefln("surface alpha: %s", f.alpha);
    writefln("SRCCOLORKEY: %s", !!(s.flags & SDL_SRCCOLORKEY));
    writefln("SRCALPHA: %s", !!(s.flags & SDL_SRCALPHA));
    writefln("RLEACCEL: %s", !!(s.flags & SDL_RLEACCEL));
    writefln("palette: %s", !!(f.palette));
}
