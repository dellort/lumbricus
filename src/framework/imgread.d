module framework.imgread;

import derelict.sdl.image;
import derelict.sdl.sdl;
import framework.filesystem;
import framework.surface;
import framework.sdl.rwops;
import framework.sdl.sdl;
import utils.stream;
import utils.misc;

import tango.stdc.stringz;

//this just uses SDL_image - my overengineering instincs are crying, but for now
//  it has to be as simple as this

private bool gIMGLoadInitialized = false;

//that's right, neither SDL nor SDL_Image are ever unloaded
//one could unload them each loadImage() call, but that'd be a waste of time
private void ensure_init() {
    if (gIMGLoadInitialized)
        return;

    sdlInit();
    DerelictSDLImage.load();

    gIMGLoadInitialized = true;
}

Surface loadImage(Stream source, Transparency transparency
    = Transparency.AutoDetect)
{
    ensure_init();
    SDL_RWops* ops = rwopsFromStream(source);
    SDL_Surface* surf = IMG_Load_RW(ops, 0);
    if (!surf) {
        auto err = fromStringz(IMG_GetError());
        throwError("image couldn't be loaded: {}", err);
    }

    return convertFromSDLSurface(surf, transparency, true);
}

Surface loadImage(char[] path, Transparency t = Transparency.AutoDetect) {
    //mLog("load image: {}", path);
    scope stream = gFS.open(path, File.ReadShared);
    scope(exit) stream.close();
    auto image = loadImage(stream, t);
    return image;
}
