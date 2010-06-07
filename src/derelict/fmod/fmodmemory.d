module derelict.fmod.fmodmemory;

struct FMOD_MEMORY_USAGE_DETAILS
{
    uint other;
    uint string;
    uint system;
    uint plugins;
    uint output;
    uint channel;
    uint channelgroup;
    uint codec;
    uint file;
    uint sound;
    uint secondaryram;
    uint soundgroup;
    uint streambuffer;
    uint dspconnection;
    uint dsp;
    uint dspcodec;
    uint profile;
    uint recordbuffer;
    uint reverb;
    uint reverbchannelprops;
    uint geometry;
    uint syncpoint;
    uint eventsystem;
    uint musicsystem;
    uint fev;
    uint memoryfsb;
    uint eventproject;
    uint eventgroupi;
    uint soundbankclass;
    uint soundbanklist;
    uint streaminstance;
    uint sounddefclass;
    uint sounddefdefclass;
    uint sounddefpool;
    uint reverbdef;
    uint eventreverb;
    uint userproperty;
    uint eventinstance;
    uint eventinstance_complex;
    uint eventinstance_simple;
    uint eventinstance_layer;
    uint eventinstance_sound;
    uint eventenvelope;
    uint eventenvelopedef;
    uint eventparameter;
    uint eventcategory;
    uint eventenvelopepoint;
    uint eventinstancepool;
}

enum {
    FMOD_MEMBITS_OTHER = 0x00000001,
    FMOD_MEMBITS_STRING = 0x00000002,

    FMOD_MEMBITS_SYSTEM = 0x00000004,
    FMOD_MEMBITS_PLUGINS = 0x00000008,
    FMOD_MEMBITS_OUTPUT = 0x00000010,
    FMOD_MEMBITS_CHANNEL = 0x00000020,
    FMOD_MEMBITS_CHANNELGROUP = 0x00000040,
    FMOD_MEMBITS_CODEC = 0x00000080,
    FMOD_MEMBITS_FILE = 0x00000100,
    FMOD_MEMBITS_SOUND = 0x00000200,
    FMOD_MEMBITS_SOUND_SECONDARYRAM = 0x00000400,
    FMOD_MEMBITS_SOUNDGROUP = 0x00000800,
    FMOD_MEMBITS_STREAMBUFFER = 0x00001000,
    FMOD_MEMBITS_DSPCONNECTION = 0x00002000,
    FMOD_MEMBITS_DSP = 0x00004000,
    FMOD_MEMBITS_DSPCODEC = 0x00008000,
    FMOD_MEMBITS_PROFILE = 0x00010000,
    FMOD_MEMBITS_RECORDBUFFER = 0x00020000,
    FMOD_MEMBITS_REVERB = 0x00040000,
    FMOD_MEMBITS_REVERBCHANNELPROPS = 0x00080000,
    FMOD_MEMBITS_GEOMETRY = 0x00100000,
    FMOD_MEMBITS_SYNCPOINT = 0x00200000,
    FMOD_MEMBITS_ALL = 0xffffffff,
}

enum {
    FMOD_EVENT_MEMBITS_EVENTSYSTEM = 0x00000001,
    FMOD_EVENT_MEMBITS_MUSICSYSTEM = 0x00000002,
    FMOD_EVENT_MEMBITS_FEV = 0x00000004,
    FMOD_EVENT_MEMBITS_MEMORYFSB = 0x00000008,
    FMOD_EVENT_MEMBITS_EVENTPROJECT = 0x00000010,
    FMOD_EVENT_MEMBITS_EVENTGROUPI = 0x00000020,
    FMOD_EVENT_MEMBITS_SOUNDBANKCLASS = 0x00000040,
    FMOD_EVENT_MEMBITS_SOUNDBANKLIST = 0x00000080,
    FMOD_EVENT_MEMBITS_STREAMINSTANCE = 0x00000100,
    FMOD_EVENT_MEMBITS_SOUNDDEFCLASS = 0x00000200,
    FMOD_EVENT_MEMBITS_SOUNDDEFDEFCLASS = 0x00000400,
    FMOD_EVENT_MEMBITS_SOUNDDEFPOOL = 0x00000800,
    FMOD_EVENT_MEMBITS_REVERBDEF = 0x00001000,
    FMOD_EVENT_MEMBITS_EVENTREVERB = 0x00002000,
    FMOD_EVENT_MEMBITS_USERPROPERTY = 0x00004000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCE = 0x00008000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCE_COMPLEX = 0x00010000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCE_SIMPLE = 0x00020000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCE_LAYER = 0x00040000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCE_SOUND = 0x00080000,
    FMOD_EVENT_MEMBITS_EVENTENVELOPE = 0x00100000,
    FMOD_EVENT_MEMBITS_EVENTENVELOPEDEF = 0x00200000,
    FMOD_EVENT_MEMBITS_EVENTPARAMETER = 0x00400000,
    FMOD_EVENT_MEMBITS_EVENTCATEGORY = 0x00800000,
    FMOD_EVENT_MEMBITS_EVENTENVELOPEPOINT = 0x01000000,
    FMOD_EVENT_MEMBITS_EVENTINSTANCEPOOL = 0x02000000,
    FMOD_EVENT_MEMBITS_ALL = 0xffffffff,

    FMOD_EVENT_MEMBITS_EVENTINSTANCE_GROUP = (FMOD_EVENT_MEMBITS_EVENTINSTANCE |
                                              FMOD_EVENT_MEMBITS_EVENTINSTANCE_COMPLEX |
                                              FMOD_EVENT_MEMBITS_EVENTINSTANCE_SIMPLE |
                                              FMOD_EVENT_MEMBITS_EVENTINSTANCE_LAYER |
                                              FMOD_EVENT_MEMBITS_EVENTINSTANCE_SOUND),

    FMOD_EVENT_MEMBITS_SOUNDDEF_GROUP = (FMOD_EVENT_MEMBITS_SOUNDDEFCLASS |
                                         FMOD_EVENT_MEMBITS_SOUNDDEFDEFCLASS |
                                         FMOD_EVENT_MEMBITS_SOUNDDEFPOOL),
}
