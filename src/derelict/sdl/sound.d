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
    bindFunc(Sound_GetLinkedVersion)("Sound_GetLinkedVersion",lib);
    bindFunc(Sound_Init)("Sound_Init",lib);
    bindFunc(Sound_Quit)("Sound_Quit",lib);
    bindFunc(Sound_AvailableDecoders)("Sound_AvailableDecoders",lib);
    bindFunc(Sound_GetError)("Sound_GetError",lib);
    bindFunc(Sound_ClearError)("Sound_ClearError",lib);
    bindFunc(Sound_NewSample)("Sound_NewSample",lib);
    bindFunc(Sound_NewSampleFromFile)("Sound_NewSampleFromFile",lib);
    bindFunc(Sound_GetDuration)("Sound_GetDuration",lib);
    bindFunc(Sound_FreeSample)("Sound_FreeSample",lib);
    bindFunc(Sound_SetBufferSize)("Sound_SetBufferSize",lib);
    bindFunc(Sound_Decode)("Sound_Decode",lib);
    bindFunc(Sound_DecodeAll)("Sound_DecodeAll",lib);
    bindFunc(Sound_Rewind)("Sound_Rewind",lib);
    bindFunc(Sound_Seek)("Sound_Seek",lib);
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
