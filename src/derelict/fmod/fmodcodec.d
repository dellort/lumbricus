module derelict.fmod.fmodcodec;

private import derelict.fmod.fmodtypes;

/*
    Codec callbacks
*/

extern(System) {

alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, FMOD_MODE usermode, FMOD_CREATESOUNDEXINFO *userexinfo)FMOD_CODEC_OPENCALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state)FMOD_CODEC_CLOSECALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, void *buffer, uint sizebytes, uint *bytesread)FMOD_CODEC_READCALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, uint *length, FMOD_TIMEUNIT lengthtype)FMOD_CODEC_GETLENGTHCALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, int subsound, uint position, FMOD_TIMEUNIT postype)FMOD_CODEC_SETPOSITIONCALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, uint *position, FMOD_TIMEUNIT postype)FMOD_CODEC_GETPOSITIONCALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, int subsound, FMOD_SOUND *sound)FMOD_CODEC_SOUNDCREATECALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, FMOD_TAGTYPE tagtype, char *name, void *data, uint datalen, FMOD_TAGDATATYPE datatype, int unique)FMOD_CODEC_METADATACALLBACK;
alias FMOD_RESULT  function(FMOD_CODEC_STATE *codec_state, int index, FMOD_CODEC_WAVEFORMAT *waveformat)FMOD_CODEC_GETWAVEFORMAT;

}

struct FMOD_CODEC_DESCRIPTION
{
    char *name;
    uint _version;
    int defaultasstream;
    FMOD_TIMEUNIT timeunits;
    FMOD_CODEC_OPENCALLBACK open;
    FMOD_CODEC_CLOSECALLBACK close;
    FMOD_CODEC_READCALLBACK read;
    FMOD_CODEC_GETLENGTHCALLBACK getlength;
    FMOD_CODEC_SETPOSITIONCALLBACK setposition;
    FMOD_CODEC_GETPOSITIONCALLBACK getposition;
    FMOD_CODEC_SOUNDCREATECALLBACK soundcreate;
    FMOD_CODEC_GETWAVEFORMAT getwaveformat;
}


struct FMOD_CODEC_WAVEFORMAT
{
    char [256]name;
    FMOD_SOUND_FORMAT format;
    int channels;
    int frequency;
    uint lengthbytes;
    uint lengthpcm;
    int blockalign;
    int loopstart;
    int loopend;
    FMOD_MODE mode;
    uint channelmask;
}


struct FMOD_CODEC_STATE
{
    int numsubsounds;
    FMOD_CODEC_WAVEFORMAT *waveformat;
    void *plugindata;
    void *filehandle;
    uint filesize;
    FMOD_FILE_READCALLBACK fileread;
    FMOD_FILE_SEEKCALLBACK fileseek;
    FMOD_CODEC_METADATACALLBACK metadata;
}


