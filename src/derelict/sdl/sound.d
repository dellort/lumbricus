module derelict.sdl.sound;

import derelict.util.loader;
import derelict.sdl.sdl;

extern(C):

const SOUND_VER_MAJOR = 1;
const SOUND_VER_MINOR = 0;
const SOUND_VER_PATCH = 3;

typedef int Sound_SampleFlags;
enum : Sound_SampleFlags {
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


void function(Sound_Version *ver) Sound_GetLinkedVersion;
int function() Sound_Init;
int function() Sound_Quit;
Sound_DecoderInfo** function() Sound_AvailableDecoders;
char* function() Sound_GetError;
void function() Sound_ClearError;
Sound_Sample* function(SDL_RWops *rw, char *ext,
    Sound_AudioInfo *desired, uint bufferSize) Sound_NewSample;
Sound_Sample* function(char *fname,
    Sound_AudioInfo *desired, uint bufferSize) Sound_NewSampleFromFile;
int function(Sound_Sample *sample) Sound_GetDuration;
void function(Sound_Sample *sample) Sound_FreeSample;
int function(Sound_Sample *sample, uint new_size) Sound_SetBufferSize;
uint function(Sound_Sample *sample) Sound_Decode;
uint function(Sound_Sample *sample) Sound_DecodeAll;
int function(Sound_Sample *sample) Sound_Rewind;
int function(Sound_Sample *sample, uint ms) Sound_Seek;


extern(D):

private void load(SharedLib lib) {
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

GenericLoader DerelictSDLSound;
static this() {
    DerelictSDLSound.setup(
        "SDL_sound.dll",
        "libSDL_sound.so, libSDL_sound.so.0",
        "",
        &load
    );
}
