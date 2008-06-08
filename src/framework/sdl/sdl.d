module framework.sdl.sdl;

import derelict.sdl.sdl;
import std.string;

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
            throw new Exception(format("Could not init SDL: %s",
                .toString(SDL_GetError())));
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
