//imports all drivers etc. (not in framework.d to avoid circular dependencies)
//TODO: find better name for this module
module framework.stuff;

//factory-imports (static ctors register stuff globally)
import framework.drivers.base_sdl;
import framework.drivers.sound_openal;
import framework.drivers.font_freetype;
import framework.drivers.draw_opengl;
import framework.drivers.draw_sdl;
version(Windows) {
    //would not compile for sure, need to fix tons of windows-specific imports
    //import framework.drivers.draw_directx;
}

//--> FMOD is not perfectly GPL compatible, so you may need to comment
//    this line in some scenarios (this is all it needs to disable FMOD)
//import framework.drivers.sound_fmod;
//<--

import framework.drivers.clipboard_win32;
import framework.drivers.clipboard_x11;
