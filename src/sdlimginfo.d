module sdlimginfo;

import derelict.sdl.sdl;
import derelict.sdl.image;

import tango.io.Stdout;
import str = stdx.string;

//take a filename as argument, load it with sdl_image, output pixelformat
//useful for debugging
void main(char[][] args) {
    DerelictSDL.load();
    DerelictSDLImage.load();
    SDL_Init(SDL_INIT_VIDEO);
    SDL_Surface* s = IMG_Load(str.toStringz(args[1]));
    Stdout.formatln("size: {}x{}", s.w, s.h);
    SDL_PixelFormat* f = s.format;
    Stdout.formatln("format: bits/bytes {}/{}, r/g/b/a mask {}/{}/{}/{}",
        f.BitsPerPixel, f.BytesPerPixel, f.Rmask, f.Gmask, f.Bmask, f.Amask);
    Stdout.formatln("colorkey: 0x{:x}", f.colorkey);
    Stdout.formatln("surface alpha: {}", f.alpha);
    Stdout.formatln("SRCCOLORKEY: {}", !!(s.flags & SDL_SRCCOLORKEY));
    Stdout.formatln("SRCALPHA: {}", !!(s.flags & SDL_SRCALPHA));
    Stdout.formatln("RLEACCEL: {}", !!(s.flags & SDL_RLEACCEL));
    Stdout.formatln("palette: {}", !!(f.palette));
}
