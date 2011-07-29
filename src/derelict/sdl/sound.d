module derelict.sdl.sound;

import derelict.util.loader;
import derelict.util.sharedlib;
import derelict.sdl.sdl;

enum SOUND_VER_MAJOR = 1;
enum SOUND_VER_MINOR = 0;
enum SOUND_VER_PATCH = 3;

alias int Sound_SampleFlags;
enum {
    SOUND_SAMPLEFLAG_NONE    = 0,
    SOUND_SAMPLEFLAG_CANSEEK = 1,
    SOUND_SAMPLEFLAG_EOF     = 1 << 29,
    SOUND_SAMPLEFLAG_ERROR   = 1 << 30,
    SOUND_SAMPLEFLAG_EAGAIN  = 1 << 31
}

struct Sound_AudioInfo {
    ushort format;
    ubyte channels;
    uint rate;
}

struct Sound_DecoderInfo {
    char **extensions;
    char *description;
    char *author;
    char *url;
}

struct Sound_Sample {
    void *opaque;
    Sound_DecoderInfo *decoder;
    Sound_AudioInfo desired;
    Sound_AudioInfo actual;
    void *buffer;
    uint buffer_size;
    Sound_SampleFlags flags;
}

struct Sound_Version {
    int major;
    int minor;
    int patch;
}

void SOUND_VERSION(out Sound_Version ver) {
    ver.major = SOUND_VER_MAJOR;
    ver.minor = SOUND_VER_MINOR;
    ver.patch = SOUND_VER_PATCH;
}


private extern(C) {
    alias void function(Sound_Version *ver) pfSound_GetLinkedVersion;
    alias int function() pfSound_Init;
    alias int function() pfSound_Quit;
    alias Sound_DecoderInfo** function() pfSound_AvailableDecoders;
    alias char* function() pfSound_GetError;
    alias void function() pfSound_ClearError;
    alias Sound_Sample* function(SDL_RWops *rw, const char *ext,
        Sound_AudioInfo *desired, uint bufferSize) pfSound_NewSample;
    alias Sound_Sample* function(char *fname,
        Sound_AudioInfo *desired, uint bufferSize) pfSound_NewSampleFromFile;
    alias int function(Sound_Sample *sample) pfSound_GetDuration;
    alias void function(Sound_Sample *sample) pfSound_FreeSample;
    alias int function(Sound_Sample *sample, uint new_size) pfSound_SetBufferSize;
    alias uint function(Sound_Sample *sample) pfSound_Decode;
    alias uint function(Sound_Sample *sample) pfSound_DecodeAll;
    alias int function(Sound_Sample *sample) pfSound_Rewind;
    alias int function(Sound_Sample *sample, uint ms) pfSound_Seek;
}

__gshared {
    pfSound_GetLinkedVersion Sound_GetLinkedVersion;
    pfSound_Init Sound_Init;
    pfSound_Quit Sound_Quit;
    pfSound_AvailableDecoders Sound_AvailableDecoders;
    pfSound_GetError Sound_GetError;
    pfSound_ClearError Sound_ClearError;
    pfSound_NewSample Sound_NewSample;
    pfSound_NewSampleFromFile Sound_NewSampleFromFile;
    pfSound_GetDuration Sound_GetDuration;
    pfSound_FreeSample Sound_FreeSample;
    pfSound_SetBufferSize Sound_SetBufferSize;
    pfSound_Decode Sound_Decode;
    pfSound_DecodeAll Sound_DecodeAll;
    pfSound_Rewind Sound_Rewind;
    pfSound_Seek Sound_Seek;
}

private void load_ssound(SharedLib lib) {
    void * Derelict_GetProc(SharedLib lib, string name) {
        return lib.loadSymbol(name);
    }
    *cast(void**)&Sound_GetLinkedVersion = Derelict_GetProc(lib, "Sound_GetLinkedVersion");
    *cast(void**)&Sound_Init = Derelict_GetProc(lib, "Sound_Init");
    *cast(void**)&Sound_Quit = Derelict_GetProc(lib, "Sound_Quit");
    *cast(void**)&Sound_AvailableDecoders = Derelict_GetProc(lib, "Sound_AvailableDecoders");
    *cast(void**)&Sound_GetError = Derelict_GetProc(lib, "Sound_GetError");
    *cast(void**)&Sound_ClearError = Derelict_GetProc(lib, "Sound_ClearError");
    *cast(void**)&Sound_NewSample = Derelict_GetProc(lib, "Sound_NewSample");
    *cast(void**)&Sound_NewSampleFromFile = Derelict_GetProc(lib, "Sound_NewSampleFromFile");
    *cast(void**)&Sound_GetDuration = Derelict_GetProc(lib, "Sound_GetDuration");
    *cast(void**)&Sound_FreeSample = Derelict_GetProc(lib, "Sound_FreeSample");
    *cast(void**)&Sound_SetBufferSize = Derelict_GetProc(lib, "Sound_SetBufferSize");
    *cast(void**)&Sound_Decode = Derelict_GetProc(lib, "Sound_Decode");
    *cast(void**)&Sound_DecodeAll = Derelict_GetProc(lib, "Sound_DecodeAll");
    *cast(void**)&Sound_Rewind = Derelict_GetProc(lib, "Sound_Rewind");
    *cast(void**)&Sound_Seek = Derelict_GetProc(lib, "Sound_Seek");
}

class DerelictSDLSoundLoader : SharedLibLoader {
    this() {
        super("SDL_sound.dll", "libSDL_sound.so, libSDL_sound.so.0, libSDL_sound-1.0.so.1",
            "TODO: add mac");
    }

    protected override void loadSymbols() {
        load_ssound(lib());
    }
}

__gshared DerelictSDLSoundLoader DerelictSDLSound;
static this()
{
    DerelictSDLSound = new DerelictSDLSoundLoader;
}
static ~this()
{
    DerelictSDLSound.unload();
}

