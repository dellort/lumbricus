module derelict.fmod.fmodfuncs;

/* ========================================================================================== */
/* FUNCTION PROTOTYPES                                                                        */
/* ========================================================================================== */

//How to convert fmod.h functions (POSIX Extended RE):
//  S: FMOD_RESULT F_API (\w+)\s*\(([^\)]+)\);
//  R1: FMOD_RESULT function\(\2\) \1;
//  R2: *cast(void**)&\1 = Derelict_GetProc(lib, "\1");

private {
    import derelict.fmod.fmodtypes;
    import derelict.fmod.fmodcodec;
    import derelict.fmod.fmoddsp;
    import derelict.fmod.fmodmemory;

    import derelict.util.loader;
}

extern(System):

/*
    FMOD global system functions (optional).
*/

FMOD_RESULT function(void *poolmem, int poollen, FMOD_MEMORY_ALLOCCALLBACK useralloc, FMOD_MEMORY_REALLOCCALLBACK userrealloc, FMOD_MEMORY_FREECALLBACK userfree, FMOD_MEMORY_TYPE memtypeflags) FMOD_Memory_Initialize;
FMOD_RESULT function(int *currentalloced, int *maxalloced, FMOD_BOOL blocking) FMOD_Memory_GetStats;
FMOD_RESULT function(FMOD_DEBUGLEVEL level) FMOD_Debug_SetLevel;
FMOD_RESULT function(FMOD_DEBUGLEVEL *level) FMOD_Debug_GetLevel;
FMOD_RESULT function(int busy) FMOD_File_SetDiskBusy;
FMOD_RESULT function(int *busy) FMOD_File_GetDiskBusy;

/*
    FMOD System factory functions.  Use this to create an FMOD System Instance.  below you will see FMOD_System_Init/Close to get started.
*/

FMOD_RESULT function(FMOD_SYSTEM **system) FMOD_System_Create;
FMOD_RESULT function(FMOD_SYSTEM *system) FMOD_System_Release;


/*
    'System' API
*/

/*
     Pre-init functions.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_OUTPUTTYPE output) FMOD_System_SetOutput;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_OUTPUTTYPE *output) FMOD_System_GetOutput;
FMOD_RESULT function(FMOD_SYSTEM *system, int *numdrivers) FMOD_System_GetNumDrivers;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, char *name, int namelen, FMOD_GUID *guid) FMOD_System_GetDriverInfo;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, short *name, int namelen, FMOD_GUID *guid) FMOD_System_GetDriverInfoW;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, FMOD_CAPS *caps, int *minfrequency, int *maxfrequency, FMOD_SPEAKERMODE *controlpanelspeakermode) FMOD_System_GetDriverCaps;
FMOD_RESULT function(FMOD_SYSTEM *system, int driver) FMOD_System_SetDriver;
FMOD_RESULT function(FMOD_SYSTEM *system, int *driver) FMOD_System_GetDriver;
FMOD_RESULT function(FMOD_SYSTEM *system, int min2d, int max2d, int min3d, int max3d) FMOD_System_SetHardwareChannels;
FMOD_RESULT function(FMOD_SYSTEM *system, int numsoftwarechannels) FMOD_System_SetSoftwareChannels;
FMOD_RESULT function(FMOD_SYSTEM *system, int *numsoftwarechannels) FMOD_System_GetSoftwareChannels;
FMOD_RESULT function(FMOD_SYSTEM *system, int samplerate, FMOD_SOUND_FORMAT format, int numoutputchannels, int maxinputchannels, FMOD_DSP_RESAMPLER resamplemethod) FMOD_System_SetSoftwareFormat;
FMOD_RESULT function(FMOD_SYSTEM *system, int *samplerate, FMOD_SOUND_FORMAT *format, int *numoutputchannels, int *maxinputchannels, FMOD_DSP_RESAMPLER *resamplemethod, int *bits) FMOD_System_GetSoftwareFormat;
FMOD_RESULT function(FMOD_SYSTEM *system, uint bufferlength, int numbuffers) FMOD_System_SetDSPBufferSize;
FMOD_RESULT function(FMOD_SYSTEM *system, uint *bufferlength, int *numbuffers) FMOD_System_GetDSPBufferSize;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_FILE_OPENCALLBACK useropen, FMOD_FILE_CLOSECALLBACK userclose, FMOD_FILE_READCALLBACK userread, FMOD_FILE_SEEKCALLBACK userseek, int blockalign) FMOD_System_SetFileSystem;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_FILE_OPENCALLBACK useropen, FMOD_FILE_CLOSECALLBACK userclose, FMOD_FILE_READCALLBACK userread, FMOD_FILE_SEEKCALLBACK userseek) FMOD_System_AttachFileSystem;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_ADVANCEDSETTINGS *settings) FMOD_System_SetAdvancedSettings;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_ADVANCEDSETTINGS *settings) FMOD_System_GetAdvancedSettings;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SPEAKERMODE speakermode) FMOD_System_SetSpeakerMode;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SPEAKERMODE *speakermode) FMOD_System_GetSpeakerMode;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SYSTEM_CALLBACK callback) FMOD_System_SetCallback;

/*
     Plug-in support
*/

FMOD_RESULT function(FMOD_SYSTEM *system, char *path) FMOD_System_SetPluginPath;
FMOD_RESULT function(FMOD_SYSTEM *system, char *filename, uint *handle, uint priority) FMOD_System_LoadPlugin;
FMOD_RESULT function(FMOD_SYSTEM *system, uint handle) FMOD_System_UnloadPlugin;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_PLUGINTYPE plugintype, int *numplugins) FMOD_System_GetNumPlugins;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_PLUGINTYPE plugintype, int index, uint *handle) FMOD_System_GetPluginHandle;
FMOD_RESULT function(FMOD_SYSTEM *system, uint handle, FMOD_PLUGINTYPE *plugintype, char *name, int namelen, uint *_version) FMOD_System_GetPluginInfo;
FMOD_RESULT function(FMOD_SYSTEM *system, uint handle) FMOD_System_SetOutputByPlugin;
FMOD_RESULT function(FMOD_SYSTEM *system, uint *handle) FMOD_System_GetOutputByPlugin;
FMOD_RESULT function(FMOD_SYSTEM *system, uint handle, FMOD_DSP **dsp) FMOD_System_CreateDSPByPlugin;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_CODEC_DESCRIPTION *description, uint priority) FMOD_System_CreateCodec;

/*
     Init/Close
*/

FMOD_RESULT function(FMOD_SYSTEM *system, int maxchannels, FMOD_INITFLAGS flags, void *extradriverdata) FMOD_System_Init;
FMOD_RESULT function(FMOD_SYSTEM *system) FMOD_System_Close;

/*
     General post-init system functions
*/

FMOD_RESULT function(FMOD_SYSTEM *system) FMOD_System_Update;

FMOD_RESULT function(FMOD_SYSTEM *system, float dopplerscale, float distancefactor, float rolloffscale) FMOD_System_Set3DSettings;
FMOD_RESULT function(FMOD_SYSTEM *system, float *dopplerscale, float *distancefactor, float *rolloffscale) FMOD_System_Get3DSettings;
FMOD_RESULT function(FMOD_SYSTEM *system, int numlisteners) FMOD_System_Set3DNumListeners;
FMOD_RESULT function(FMOD_SYSTEM *system, int *numlisteners) FMOD_System_Get3DNumListeners;
FMOD_RESULT function(FMOD_SYSTEM *system, int listener, FMOD_VECTOR *pos, FMOD_VECTOR *vel, FMOD_VECTOR *forward, FMOD_VECTOR *up) FMOD_System_Set3DListenerAttributes;
FMOD_RESULT function(FMOD_SYSTEM *system, int listener, FMOD_VECTOR *pos, FMOD_VECTOR *vel, FMOD_VECTOR *forward, FMOD_VECTOR *up) FMOD_System_Get3DListenerAttributes;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_3D_ROLLOFFCALLBACK callback) FMOD_System_Set3DRolloffCallback;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SPEAKER speaker, float x, float y, FMOD_BOOL active) FMOD_System_Set3DSpeakerPosition;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SPEAKER speaker, float *x, float *y, FMOD_BOOL *active) FMOD_System_Get3DSpeakerPosition;

FMOD_RESULT function(FMOD_SYSTEM *system, uint filebuffersize, FMOD_TIMEUNIT filebuffersizetype) FMOD_System_SetStreamBufferSize;
FMOD_RESULT function(FMOD_SYSTEM *system, uint *filebuffersize, FMOD_TIMEUNIT *filebuffersizetype) FMOD_System_GetStreamBufferSize;

/*
     System information functions.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, uint *_version) FMOD_System_GetVersion;
FMOD_RESULT function(FMOD_SYSTEM *system, void **handle) FMOD_System_GetOutputHandle;
FMOD_RESULT function(FMOD_SYSTEM *system, int *channels) FMOD_System_GetChannelsPlaying;
FMOD_RESULT function(FMOD_SYSTEM *system, int *num2d, int *num3d, int *total) FMOD_System_GetHardwareChannels;
FMOD_RESULT function(FMOD_SYSTEM *system, float *dsp, float *stream, float *geometry, float *update, float *total) FMOD_System_GetCPUUsage;
FMOD_RESULT function(FMOD_SYSTEM *system, int *currentalloced, int *maxalloced, int *total) FMOD_System_GetSoundRAM;
FMOD_RESULT function(FMOD_SYSTEM *system, int *numdrives) FMOD_System_GetNumCDROMDrives;
FMOD_RESULT function(FMOD_SYSTEM *system, int drive, char *drivename, int drivenamelen, char *scsiname, int scsinamelen, char *devicename, int devicenamelen) FMOD_System_GetCDROMDriveName;
FMOD_RESULT function(FMOD_SYSTEM *system, float *spectrumarray, int numvalues, int channeloffset, FMOD_DSP_FFT_WINDOW windowtype) FMOD_System_GetSpectrum;
FMOD_RESULT function(FMOD_SYSTEM *system, float *wavearray, int numvalues, int channeloffset) FMOD_System_GetWaveData;

/*
     Sound/DSP/Channel/FX creation and retrieval.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, char *name_or_data, FMOD_MODE mode, FMOD_CREATESOUNDEXINFO *exinfo, FMOD_SOUND **sound) FMOD_System_CreateSound;
FMOD_RESULT function(FMOD_SYSTEM *system, char *name_or_data, FMOD_MODE mode, FMOD_CREATESOUNDEXINFO *exinfo, FMOD_SOUND **sound) FMOD_System_CreateStream;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_DSP_DESCRIPTION *description, FMOD_DSP **dsp) FMOD_System_CreateDSP;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_DSP_TYPE type, FMOD_DSP **dsp) FMOD_System_CreateDSPByType;
FMOD_RESULT function(FMOD_SYSTEM *system, char *name, FMOD_CHANNELGROUP **channelgroup) FMOD_System_CreateChannelGroup;
FMOD_RESULT function(FMOD_SYSTEM *system, char *name, FMOD_SOUNDGROUP **soundgroup) FMOD_System_CreateSoundGroup;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_REVERB **reverb) FMOD_System_CreateReverb;

FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_CHANNELINDEX channelid, FMOD_SOUND *sound, FMOD_BOOL paused, FMOD_CHANNEL **channel) FMOD_System_PlaySound;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_CHANNELINDEX channelid, FMOD_DSP *dsp, FMOD_BOOL paused, FMOD_CHANNEL **channel) FMOD_System_PlayDSP;
FMOD_RESULT function(FMOD_SYSTEM *system, int channelid, FMOD_CHANNEL **channel) FMOD_System_GetChannel;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_CHANNELGROUP **channelgroup) FMOD_System_GetMasterChannelGroup;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_SOUNDGROUP **soundgroup) FMOD_System_GetMasterSoundGroup;

/*
     Reverb API
*/

FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_REVERB_PROPERTIES *prop) FMOD_System_SetReverbProperties;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_REVERB_PROPERTIES *prop) FMOD_System_GetReverbProperties;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_REVERB_PROPERTIES *prop) FMOD_System_SetReverbAmbientProperties;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_REVERB_PROPERTIES *prop) FMOD_System_GetReverbAmbientProperties;

/*
     System level DSP access.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_DSP **dsp) FMOD_System_GetDSPHead;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_DSP *dsp, FMOD_DSPCONNECTION **connection) FMOD_System_AddDSP;
FMOD_RESULT function(FMOD_SYSTEM *system) FMOD_System_LockDSP;
FMOD_RESULT function(FMOD_SYSTEM *system) FMOD_System_UnlockDSP;
FMOD_RESULT function(FMOD_SYSTEM *system, uint *hi, uint *lo) FMOD_System_GetDSPClock;

/*
     Recording API.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, int *numdrivers) FMOD_System_GetRecordNumDrivers;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, char *name, int namelen, FMOD_GUID *guid) FMOD_System_GetRecordDriverInfo;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, short *name, int namelen, FMOD_GUID *guid) FMOD_System_GetRecordDriverInfoW;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, FMOD_CAPS *caps, int *minfrequency, int *maxfrequency) FMOD_System_GetRecordDriverCaps;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, uint *position) FMOD_System_GetRecordPosition;

FMOD_RESULT function(FMOD_SYSTEM *system, int id, FMOD_SOUND *sound, FMOD_BOOL loop) FMOD_System_RecordStart;
FMOD_RESULT function(FMOD_SYSTEM *system, int id) FMOD_System_RecordStop;
FMOD_RESULT function(FMOD_SYSTEM *system, int id, FMOD_BOOL *recording) FMOD_System_IsRecording;

/*
     Geometry API.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, int maxpolygons, int maxvertices, FMOD_GEOMETRY **geometry) FMOD_System_CreateGeometry;
FMOD_RESULT function(FMOD_SYSTEM *system, float maxworldsize) FMOD_System_SetGeometrySettings;
FMOD_RESULT function(FMOD_SYSTEM *system, float *maxworldsize) FMOD_System_GetGeometrySettings;
FMOD_RESULT function(FMOD_SYSTEM *system, void *data, int datasize, FMOD_GEOMETRY **geometry) FMOD_System_LoadGeometry;
FMOD_RESULT function(FMOD_SYSTEM *system, FMOD_VECTOR *listener, FMOD_VECTOR *source, float *direct, float *reverb) FMOD_System_GetGeometryOcclusion;

/*
     Network functions.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, char *proxy) FMOD_System_SetNetworkProxy;
FMOD_RESULT function(FMOD_SYSTEM *system, char *proxy, int proxylen) FMOD_System_GetNetworkProxy;
FMOD_RESULT function(FMOD_SYSTEM *system, int timeout) FMOD_System_SetNetworkTimeout;
FMOD_RESULT function(FMOD_SYSTEM *system, int *timeout) FMOD_System_GetNetworkTimeout;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_SYSTEM *system, void *userdata) FMOD_System_SetUserData;
FMOD_RESULT function(FMOD_SYSTEM *system, void **userdata) FMOD_System_GetUserData;

FMOD_RESULT function(FMOD_SYSTEM *system, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_System_GetMemoryInfo;

/*
    'Sound' API
*/

FMOD_RESULT function(FMOD_SOUND *sound) FMOD_Sound_Release;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SYSTEM **system) FMOD_Sound_GetSystemObject;

/*
     Standard sound manipulation functions.
*/

FMOD_RESULT function(FMOD_SOUND *sound, uint offset, uint length, void **ptr1, void **ptr2, uint *len1, uint *len2) FMOD_Sound_Lock;
FMOD_RESULT function(FMOD_SOUND *sound, void *ptr1, void *ptr2, uint len1, uint len2) FMOD_Sound_Unlock;
FMOD_RESULT function(FMOD_SOUND *sound, float frequency, float volume, float pan, int priority) FMOD_Sound_SetDefaults;
FMOD_RESULT function(FMOD_SOUND *sound, float *frequency, float *volume, float *pan, int *priority) FMOD_Sound_GetDefaults;
FMOD_RESULT function(FMOD_SOUND *sound, float frequencyvar, float volumevar, float panvar) FMOD_Sound_SetVariations;
FMOD_RESULT function(FMOD_SOUND *sound, float *frequencyvar, float *volumevar, float *panvar) FMOD_Sound_GetVariations;
FMOD_RESULT function(FMOD_SOUND *sound, float min, float max) FMOD_Sound_Set3DMinMaxDistance;
FMOD_RESULT function(FMOD_SOUND *sound, float *min, float *max) FMOD_Sound_Get3DMinMaxDistance;
FMOD_RESULT function(FMOD_SOUND *sound, float insideconeangle, float outsideconeangle, float outsidevolume) FMOD_Sound_Set3DConeSettings;
FMOD_RESULT function(FMOD_SOUND *sound, float *insideconeangle, float *outsideconeangle, float *outsidevolume) FMOD_Sound_Get3DConeSettings;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_VECTOR *points, int numpoints) FMOD_Sound_Set3DCustomRolloff;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_VECTOR **points, int *numpoints) FMOD_Sound_Get3DCustomRolloff;
FMOD_RESULT function(FMOD_SOUND *sound, int index, FMOD_SOUND *subsound) FMOD_Sound_SetSubSound;
FMOD_RESULT function(FMOD_SOUND *sound, int index, FMOD_SOUND **subsound) FMOD_Sound_GetSubSound;
FMOD_RESULT function(FMOD_SOUND *sound, int *subsoundlist, int numsubsounds) FMOD_Sound_SetSubSoundSentence;
FMOD_RESULT function(FMOD_SOUND *sound, char *name, int namelen) FMOD_Sound_GetName;
FMOD_RESULT function(FMOD_SOUND *sound, uint *length, FMOD_TIMEUNIT lengthtype) FMOD_Sound_GetLength;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SOUND_TYPE *type, FMOD_SOUND_FORMAT *format, int *channels, int *bits) FMOD_Sound_GetFormat;
FMOD_RESULT function(FMOD_SOUND *sound, int *numsubsounds) FMOD_Sound_GetNumSubSounds;
FMOD_RESULT function(FMOD_SOUND *sound, int *numtags, int *numtagsupdated) FMOD_Sound_GetNumTags;
FMOD_RESULT function(FMOD_SOUND *sound, char *name, int index, FMOD_TAG *tag) FMOD_Sound_GetTag;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_OPENSTATE *openstate, uint *percentbuffered, FMOD_BOOL *starving) FMOD_Sound_GetOpenState;
FMOD_RESULT function(FMOD_SOUND *sound, void *buffer, uint lenbytes, uint *read) FMOD_Sound_ReadData;
FMOD_RESULT function(FMOD_SOUND *sound, uint pcm) FMOD_Sound_SeekData;

FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SOUNDGROUP *soundgroup) FMOD_Sound_SetSoundGroup;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SOUNDGROUP **soundgroup) FMOD_Sound_GetSoundGroup;

/*
     Synchronization point API.  These points can come from markers embedded in wav files, and can also generate channel callbacks.
*/

FMOD_RESULT function(FMOD_SOUND *sound, int *numsyncpoints) FMOD_Sound_GetNumSyncPoints;
FMOD_RESULT function(FMOD_SOUND *sound, int index, FMOD_SYNCPOINT **point) FMOD_Sound_GetSyncPoint;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SYNCPOINT *point, char *name, int namelen, uint *offset, FMOD_TIMEUNIT offsettype) FMOD_Sound_GetSyncPointInfo;
FMOD_RESULT function(FMOD_SOUND *sound, uint offset, FMOD_TIMEUNIT offsettype, char *name, FMOD_SYNCPOINT **point) FMOD_Sound_AddSyncPoint;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_SYNCPOINT *point) FMOD_Sound_DeleteSyncPoint;

/*
     Functions also in Channel class but here they are the 'default' to save having to change it in Channel all the time.
*/

FMOD_RESULT function(FMOD_SOUND *sound, FMOD_MODE mode) FMOD_Sound_SetMode;
FMOD_RESULT function(FMOD_SOUND *sound, FMOD_MODE *mode) FMOD_Sound_GetMode;
FMOD_RESULT function(FMOD_SOUND *sound, int loopcount) FMOD_Sound_SetLoopCount;
FMOD_RESULT function(FMOD_SOUND *sound, int *loopcount) FMOD_Sound_GetLoopCount;
FMOD_RESULT function(FMOD_SOUND *sound, uint loopstart, FMOD_TIMEUNIT loopstarttype, uint loopend, FMOD_TIMEUNIT loopendtype) FMOD_Sound_SetLoopPoints;
FMOD_RESULT function(FMOD_SOUND *sound, uint *loopstart, FMOD_TIMEUNIT loopstarttype, uint *loopend, FMOD_TIMEUNIT loopendtype) FMOD_Sound_GetLoopPoints;

/*
     For MOD/S3M/XM/IT/MID sequenced formats only.
*/

FMOD_RESULT function(FMOD_SOUND *sound, int *numchannels) FMOD_Sound_GetMusicNumChannels;
FMOD_RESULT function(FMOD_SOUND *sound, int channel, float volume) FMOD_Sound_SetMusicChannelVolume;
FMOD_RESULT function(FMOD_SOUND *sound, int channel, float *volume) FMOD_Sound_GetMusicChannelVolume;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_SOUND *sound, void *userdata) FMOD_Sound_SetUserData;
FMOD_RESULT function(FMOD_SOUND *sound, void **userdata) FMOD_Sound_GetUserData;

FMOD_RESULT function(FMOD_SOUND *sound, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_Sound_GetMemoryInfo;

/*
    'Channel' API
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_SYSTEM **system) FMOD_Channel_GetSystemObject;

FMOD_RESULT function(FMOD_CHANNEL *channel) FMOD_Channel_Stop;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL paused) FMOD_Channel_SetPaused;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL *paused) FMOD_Channel_GetPaused;
FMOD_RESULT function(FMOD_CHANNEL *channel, float volume) FMOD_Channel_SetVolume;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *volume) FMOD_Channel_GetVolume;
FMOD_RESULT function(FMOD_CHANNEL *channel, float frequency) FMOD_Channel_SetFrequency;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *frequency) FMOD_Channel_GetFrequency;
FMOD_RESULT function(FMOD_CHANNEL *channel, float pan) FMOD_Channel_SetPan;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *pan) FMOD_Channel_GetPan;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_DELAYTYPE delaytype, uint delayhi, uint delaylo) FMOD_Channel_SetDelay;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_DELAYTYPE delaytype, uint *delayhi, uint *delaylo) FMOD_Channel_GetDelay;
FMOD_RESULT function(FMOD_CHANNEL *channel, float frontleft, float frontright, float center, float lfe, float backleft, float backright, float sideleft, float sideright) FMOD_Channel_SetSpeakerMix;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *frontleft, float *frontright, float *center, float *lfe, float *backleft, float *backright, float *sideleft, float *sideright) FMOD_Channel_GetSpeakerMix;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_SPEAKER speaker, float *levels, int numlevels) FMOD_Channel_SetSpeakerLevels;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_SPEAKER speaker, float *levels, int numlevels) FMOD_Channel_GetSpeakerLevels;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *levels, int numlevels) FMOD_Channel_SetInputChannelMix;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *levels, int numlevels) FMOD_Channel_GetInputChannelMix;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL mute) FMOD_Channel_SetMute;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL *mute) FMOD_Channel_GetMute;
FMOD_RESULT function(FMOD_CHANNEL *channel, int priority) FMOD_Channel_SetPriority;
FMOD_RESULT function(FMOD_CHANNEL *channel, int *priority) FMOD_Channel_GetPriority;
FMOD_RESULT function(FMOD_CHANNEL *channel, uint position, FMOD_TIMEUNIT postype) FMOD_Channel_SetPosition;
FMOD_RESULT function(FMOD_CHANNEL *channel, uint *position, FMOD_TIMEUNIT postype) FMOD_Channel_GetPosition;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_REVERB_CHANNELPROPERTIES *prop) FMOD_Channel_SetReverbProperties;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_REVERB_CHANNELPROPERTIES *prop) FMOD_Channel_GetReverbProperties;
FMOD_RESULT function(FMOD_CHANNEL *channel, float gain) FMOD_Channel_SetLowPassGain;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *gain) FMOD_Channel_GetLowPassGain;

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_CHANNELGROUP *channelgroup) FMOD_Channel_SetChannelGroup;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_CHANNELGROUP **channelgroup) FMOD_Channel_GetChannelGroup;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_CHANNEL_CALLBACK callback) FMOD_Channel_SetCallback;

/*
     3D functionality.
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR *pos, FMOD_VECTOR *vel) FMOD_Channel_Set3DAttributes;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR *pos, FMOD_VECTOR *vel) FMOD_Channel_Get3DAttributes;
FMOD_RESULT function(FMOD_CHANNEL *channel, float mindistance, float maxdistance) FMOD_Channel_Set3DMinMaxDistance;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *mindistance, float *maxdistance) FMOD_Channel_Get3DMinMaxDistance;
FMOD_RESULT function(FMOD_CHANNEL *channel, float insideconeangle, float outsideconeangle, float outsidevolume) FMOD_Channel_Set3DConeSettings;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *insideconeangle, float *outsideconeangle, float *outsidevolume) FMOD_Channel_Get3DConeSettings;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR *orientation) FMOD_Channel_Set3DConeOrientation;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR *orientation) FMOD_Channel_Get3DConeOrientation;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR *points, int numpoints) FMOD_Channel_Set3DCustomRolloff;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_VECTOR **points, int *numpoints) FMOD_Channel_Get3DCustomRolloff;
FMOD_RESULT function(FMOD_CHANNEL *channel, float directocclusion, float reverbocclusion) FMOD_Channel_Set3DOcclusion;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *directocclusion, float *reverbocclusion) FMOD_Channel_Get3DOcclusion;
FMOD_RESULT function(FMOD_CHANNEL *channel, float angle) FMOD_Channel_Set3DSpread;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *angle) FMOD_Channel_Get3DSpread;
FMOD_RESULT function(FMOD_CHANNEL *channel, float level) FMOD_Channel_Set3DPanLevel;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *level) FMOD_Channel_Get3DPanLevel;
FMOD_RESULT function(FMOD_CHANNEL *channel, float level) FMOD_Channel_Set3DDopplerLevel;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *level) FMOD_Channel_Get3DDopplerLevel;

/*
     DSP functionality only for channels playing sounds created with FMOD_SOFTWARE.
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_DSP **dsp) FMOD_Channel_GetDSPHead;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_DSP *dsp, FMOD_DSPCONNECTION **connection) FMOD_Channel_AddDSP;

/*
     Information only functions.
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL *isplaying) FMOD_Channel_IsPlaying;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_BOOL *isvirtual) FMOD_Channel_IsVirtual;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *audibility) FMOD_Channel_GetAudibility;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_SOUND **sound) FMOD_Channel_GetCurrentSound;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *spectrumarray, int numvalues, int channeloffset, FMOD_DSP_FFT_WINDOW windowtype) FMOD_Channel_GetSpectrum;
FMOD_RESULT function(FMOD_CHANNEL *channel, float *wavearray, int numvalues, int channeloffset) FMOD_Channel_GetWaveData;
FMOD_RESULT function(FMOD_CHANNEL *channel, int *index) FMOD_Channel_GetIndex;

/*
     Functions also found in Sound class but here they can be set per channel.
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_MODE mode) FMOD_Channel_SetMode;
FMOD_RESULT function(FMOD_CHANNEL *channel, FMOD_MODE *mode) FMOD_Channel_GetMode;
FMOD_RESULT function(FMOD_CHANNEL *channel, int loopcount) FMOD_Channel_SetLoopCount;
FMOD_RESULT function(FMOD_CHANNEL *channel, int *loopcount) FMOD_Channel_GetLoopCount;
FMOD_RESULT function(FMOD_CHANNEL *channel, uint loopstart, FMOD_TIMEUNIT loopstarttype, uint loopend, FMOD_TIMEUNIT loopendtype) FMOD_Channel_SetLoopPoints;
FMOD_RESULT function(FMOD_CHANNEL *channel, uint *loopstart, FMOD_TIMEUNIT loopstarttype, uint *loopend, FMOD_TIMEUNIT loopendtype) FMOD_Channel_GetLoopPoints;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_CHANNEL *channel, void *userdata) FMOD_Channel_SetUserData;
FMOD_RESULT function(FMOD_CHANNEL *channel, void **userdata) FMOD_Channel_GetUserData;

FMOD_RESULT function(FMOD_CHANNEL *channel, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_Channel_GetMemoryInfo;

/*
    'ChannelGroup' API
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup) FMOD_ChannelGroup_Release;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_SYSTEM **system) FMOD_ChannelGroup_GetSystemObject;

/*
     Channelgroup scale values.  (changes attributes relative to the channels, doesn't overwrite them)
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float volume) FMOD_ChannelGroup_SetVolume;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float *volume) FMOD_ChannelGroup_GetVolume;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float pitch) FMOD_ChannelGroup_SetPitch;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float *pitch) FMOD_ChannelGroup_GetPitch;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float directocclusion, float reverbocclusion) FMOD_ChannelGroup_Set3DOcclusion;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float *directocclusion, float *reverbocclusion) FMOD_ChannelGroup_Get3DOcclusion;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_BOOL paused) FMOD_ChannelGroup_SetPaused;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_BOOL *paused) FMOD_ChannelGroup_GetPaused;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_BOOL mute) FMOD_ChannelGroup_SetMute;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_BOOL *mute) FMOD_ChannelGroup_GetMute;

/*
     Channelgroup override values.  (recursively overwrites whatever settings the channels had)
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup) FMOD_ChannelGroup_Stop;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float volume) FMOD_ChannelGroup_OverrideVolume;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float frequency) FMOD_ChannelGroup_OverrideFrequency;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float pan) FMOD_ChannelGroup_OverridePan;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_REVERB_CHANNELPROPERTIES *prop) FMOD_ChannelGroup_OverrideReverbProperties;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_VECTOR *pos, FMOD_VECTOR *vel) FMOD_ChannelGroup_Override3DAttributes;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float frontleft, float frontright, float center, float lfe, float backleft, float backright, float sideleft, float sideright) FMOD_ChannelGroup_OverrideSpeakerMix;

/*
     Nested channel groups.
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_CHANNELGROUP *group) FMOD_ChannelGroup_AddGroup;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, int *numgroups) FMOD_ChannelGroup_GetNumGroups;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, int index, FMOD_CHANNELGROUP **group) FMOD_ChannelGroup_GetGroup;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_CHANNELGROUP **group) FMOD_ChannelGroup_GetParentGroup;

/*
     DSP functionality only for channel groups playing sounds created with FMOD_SOFTWARE.
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_DSP **dsp) FMOD_ChannelGroup_GetDSPHead;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, FMOD_DSP *dsp, FMOD_DSPCONNECTION **connection) FMOD_ChannelGroup_AddDSP;

/*
     Information only functions.
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, char *name, int namelen) FMOD_ChannelGroup_GetName;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, int *numchannels) FMOD_ChannelGroup_GetNumChannels;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, int index, FMOD_CHANNEL **channel) FMOD_ChannelGroup_GetChannel;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float *spectrumarray, int numvalues, int channeloffset, FMOD_DSP_FFT_WINDOW windowtype) FMOD_ChannelGroup_GetSpectrum;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, float *wavearray, int numvalues, int channeloffset) FMOD_ChannelGroup_GetWaveData;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, void *userdata) FMOD_ChannelGroup_SetUserData;
FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, void **userdata) FMOD_ChannelGroup_GetUserData;

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_ChannelGroup_GetMemoryInfo;

/*
    'SoundGroup' API
*/

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup) FMOD_SoundGroup_Release;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, FMOD_SYSTEM **system) FMOD_SoundGroup_GetSystemObject;

/*
     SoundGroup control functions.
*/

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, int maxaudible) FMOD_SoundGroup_SetMaxAudible;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, int *maxaudible) FMOD_SoundGroup_GetMaxAudible;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, FMOD_SOUNDGROUP_BEHAVIOR behavior) FMOD_SoundGroup_SetMaxAudibleBehavior;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, FMOD_SOUNDGROUP_BEHAVIOR *behavior) FMOD_SoundGroup_GetMaxAudibleBehavior;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, float speed) FMOD_SoundGroup_SetMuteFadeSpeed;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, float *speed) FMOD_SoundGroup_GetMuteFadeSpeed;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, float volume) FMOD_SoundGroup_SetVolume;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, float *volume) FMOD_SoundGroup_GetVolume;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup) FMOD_SoundGroup_Stop;

/*
     Information only functions.
*/

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, char *name, int namelen) FMOD_SoundGroup_GetName;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, int *numsounds) FMOD_SoundGroup_GetNumSounds;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, int index, FMOD_SOUND **sound) FMOD_SoundGroup_GetSound;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, int *numplaying) FMOD_SoundGroup_GetNumPlaying;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, void *userdata) FMOD_SoundGroup_SetUserData;
FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, void **userdata) FMOD_SoundGroup_GetUserData;

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_SoundGroup_GetMemoryInfo;

/*
    'DSP' API
*/

FMOD_RESULT function(FMOD_DSP *dsp) FMOD_DSP_Release;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_SYSTEM **system) FMOD_DSP_GetSystemObject;

/*
     Connection / disconnection / input and output enumeration.
*/

FMOD_RESULT function(FMOD_DSP *dsp, FMOD_DSP *target, FMOD_DSPCONNECTION **connection) FMOD_DSP_AddInput;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_DSP *target) FMOD_DSP_DisconnectFrom;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_BOOL inputs, FMOD_BOOL outputs) FMOD_DSP_DisconnectAll;
FMOD_RESULT function(FMOD_DSP *dsp) FMOD_DSP_Remove;
FMOD_RESULT function(FMOD_DSP *dsp, int *numinputs) FMOD_DSP_GetNumInputs;
FMOD_RESULT function(FMOD_DSP *dsp, int *numoutputs) FMOD_DSP_GetNumOutputs;
FMOD_RESULT function(FMOD_DSP *dsp, int index, FMOD_DSP **input, FMOD_DSPCONNECTION **inputconnection) FMOD_DSP_GetInput;
FMOD_RESULT function(FMOD_DSP *dsp, int index, FMOD_DSP **output, FMOD_DSPCONNECTION **outputconnection) FMOD_DSP_GetOutput;

/*
     DSP unit control.
*/

FMOD_RESULT function(FMOD_DSP *dsp, FMOD_BOOL active) FMOD_DSP_SetActive;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_BOOL *active) FMOD_DSP_GetActive;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_BOOL bypass) FMOD_DSP_SetBypass;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_BOOL *bypass) FMOD_DSP_GetBypass;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_SPEAKER speaker, FMOD_BOOL active) FMOD_DSP_SetSpeakerActive;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_SPEAKER speaker, FMOD_BOOL *active) FMOD_DSP_GetSpeakerActive;
FMOD_RESULT function(FMOD_DSP *dsp) FMOD_DSP_Reset;

/*
     DSP parameter control.
*/

FMOD_RESULT function(FMOD_DSP *dsp, int index, float value) FMOD_DSP_SetParameter;
FMOD_RESULT function(FMOD_DSP *dsp, int index, float *value, char *valuestr, int valuestrlen) FMOD_DSP_GetParameter;
FMOD_RESULT function(FMOD_DSP *dsp, int *numparams) FMOD_DSP_GetNumParameters;
FMOD_RESULT function(FMOD_DSP *dsp, int index, char *name, char *label, char *description, int descriptionlen, float *min, float *max) FMOD_DSP_GetParameterInfo;
FMOD_RESULT function(FMOD_DSP *dsp, void *hwnd, FMOD_BOOL show) FMOD_DSP_ShowConfigDialog;

/*
     DSP attributes.
*/

FMOD_RESULT function(FMOD_DSP *dsp, char *name, uint *_version, int *channels, int *configwidth, int *configheight) FMOD_DSP_GetInfo;
FMOD_RESULT function(FMOD_DSP *dsp, FMOD_DSP_TYPE *type) FMOD_DSP_GetType;
FMOD_RESULT function(FMOD_DSP *dsp, float frequency, float volume, float pan, int priority) FMOD_DSP_SetDefaults;
FMOD_RESULT function(FMOD_DSP *dsp, float *frequency, float *volume, float *pan, int *priority) FMOD_DSP_GetDefaults;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_DSP *dsp, void *userdata) FMOD_DSP_SetUserData;
FMOD_RESULT function(FMOD_DSP *dsp, void **userdata) FMOD_DSP_GetUserData;

FMOD_RESULT function(FMOD_DSP *dsp, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_DSP_GetMemoryInfo;

/*
    'DSPConnection' API
*/

FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, FMOD_DSP **input) FMOD_DSPConnection_GetInput;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, FMOD_DSP **output) FMOD_DSPConnection_GetOutput;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, float volume) FMOD_DSPConnection_SetMix;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, float *volume) FMOD_DSPConnection_GetMix;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, FMOD_SPEAKER speaker, float *levels, int numlevels) FMOD_DSPConnection_SetLevels;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, FMOD_SPEAKER speaker, float *levels, int numlevels) FMOD_DSPConnection_GetLevels;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, void *userdata) FMOD_DSPConnection_SetUserData;
FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, void **userdata) FMOD_DSPConnection_GetUserData;

FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_DSPConnection_GetMemoryInfo;

/*
    'Geometry' API
*/

FMOD_RESULT function(FMOD_GEOMETRY *geometry) FMOD_Geometry_Release;

/*
     Polygon manipulation.
*/

FMOD_RESULT function(FMOD_GEOMETRY *geometry, float directocclusion, float reverbocclusion, FMOD_BOOL doublesided, int numvertices, FMOD_VECTOR *vertices, int *polygonindex) FMOD_Geometry_AddPolygon;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int *numpolygons) FMOD_Geometry_GetNumPolygons;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int *maxpolygons, int *maxvertices) FMOD_Geometry_GetMaxPolygons;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int index, int *numvertices) FMOD_Geometry_GetPolygonNumVertices;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int index, int vertexindex, FMOD_VECTOR *vertex) FMOD_Geometry_SetPolygonVertex;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int index, int vertexindex, FMOD_VECTOR *vertex) FMOD_Geometry_GetPolygonVertex;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int index, float directocclusion, float reverbocclusion, FMOD_BOOL doublesided) FMOD_Geometry_SetPolygonAttributes;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, int index, float *directocclusion, float *reverbocclusion, FMOD_BOOL *doublesided) FMOD_Geometry_GetPolygonAttributes;

/*
     Object manipulation.
*/

FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_BOOL active) FMOD_Geometry_SetActive;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_BOOL *active) FMOD_Geometry_GetActive;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *forward, FMOD_VECTOR *up) FMOD_Geometry_SetRotation;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *forward, FMOD_VECTOR *up) FMOD_Geometry_GetRotation;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *position) FMOD_Geometry_SetPosition;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *position) FMOD_Geometry_GetPosition;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *scale) FMOD_Geometry_SetScale;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, FMOD_VECTOR *scale) FMOD_Geometry_GetScale;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, void *data, int *datasize) FMOD_Geometry_Save;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_GEOMETRY *geometry, void *userdata) FMOD_Geometry_SetUserData;
FMOD_RESULT function(FMOD_GEOMETRY *geometry, void **userdata) FMOD_Geometry_GetUserData;

FMOD_RESULT function(FMOD_GEOMETRY *geometry, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_Geometry_GetMemoryInfo;

/*
    'Reverb' API
*/

FMOD_RESULT function(FMOD_REVERB *reverb) FMOD_Reverb_Release;

/*
     Reverb manipulation.
*/

FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_VECTOR *position, float mindistance, float maxdistance) FMOD_Reverb_Set3DAttributes;
FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_VECTOR *position, float *mindistance, float *maxdistance) FMOD_Reverb_Get3DAttributes;
FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_REVERB_PROPERTIES *properties) FMOD_Reverb_SetProperties;
FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_REVERB_PROPERTIES *properties) FMOD_Reverb_GetProperties;
FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_BOOL active) FMOD_Reverb_SetActive;
FMOD_RESULT function(FMOD_REVERB *reverb, FMOD_BOOL *active) FMOD_Reverb_GetActive;

/*
     Userdata set/get.
*/

FMOD_RESULT function(FMOD_REVERB *reverb, void *userdata) FMOD_Reverb_SetUserData;
FMOD_RESULT function(FMOD_REVERB *reverb, void **userdata) FMOD_Reverb_GetUserData;

FMOD_RESULT function(FMOD_REVERB *reverb, uint memorybits, uint event_memorybits, uint *memoryused, FMOD_MEMORY_USAGE_DETAILS *memoryused_details) FMOD_Reverb_GetMemoryInfo;


extern(D):

private void load(SharedLib lib) {
    /*
        FMOD global system functions (optional).
    */

    *cast(void**)&FMOD_Memory_Initialize = Derelict_GetProc(lib, "FMOD_Memory_Initialize");
    *cast(void**)&FMOD_Memory_GetStats = Derelict_GetProc(lib, "FMOD_Memory_GetStats");
    *cast(void**)&FMOD_Debug_SetLevel = Derelict_GetProc(lib, "FMOD_Debug_SetLevel");
    *cast(void**)&FMOD_Debug_GetLevel = Derelict_GetProc(lib, "FMOD_Debug_GetLevel");
    *cast(void**)&FMOD_File_SetDiskBusy = Derelict_GetProc(lib, "FMOD_File_SetDiskBusy");
    *cast(void**)&FMOD_File_GetDiskBusy = Derelict_GetProc(lib, "FMOD_File_GetDiskBusy");

    /*
        FMOD System factory functions.  Use this to create an FMOD System Instance.  below you will see FMOD_System_Init/Close to get started.
    */

    *cast(void**)&FMOD_System_Create = Derelict_GetProc(lib, "FMOD_System_Create");
    *cast(void**)&FMOD_System_Release = Derelict_GetProc(lib, "FMOD_System_Release");


    /*
        'System' API
    */

    /*
         Pre-init functions.
    */

    *cast(void**)&FMOD_System_SetOutput = Derelict_GetProc(lib, "FMOD_System_SetOutput");
    *cast(void**)&FMOD_System_GetOutput = Derelict_GetProc(lib, "FMOD_System_GetOutput");
    *cast(void**)&FMOD_System_GetNumDrivers = Derelict_GetProc(lib, "FMOD_System_GetNumDrivers");
    *cast(void**)&FMOD_System_GetDriverInfo = Derelict_GetProc(lib, "FMOD_System_GetDriverInfo");
    *cast(void**)&FMOD_System_GetDriverInfoW = Derelict_GetProc(lib, "FMOD_System_GetDriverInfoW");
    *cast(void**)&FMOD_System_GetDriverCaps = Derelict_GetProc(lib, "FMOD_System_GetDriverCaps");
    *cast(void**)&FMOD_System_SetDriver = Derelict_GetProc(lib, "FMOD_System_SetDriver");
    *cast(void**)&FMOD_System_GetDriver = Derelict_GetProc(lib, "FMOD_System_GetDriver");
    *cast(void**)&FMOD_System_SetHardwareChannels = Derelict_GetProc(lib, "FMOD_System_SetHardwareChannels");
    *cast(void**)&FMOD_System_SetSoftwareChannels = Derelict_GetProc(lib, "FMOD_System_SetSoftwareChannels");
    *cast(void**)&FMOD_System_GetSoftwareChannels = Derelict_GetProc(lib, "FMOD_System_GetSoftwareChannels");
    *cast(void**)&FMOD_System_SetSoftwareFormat = Derelict_GetProc(lib, "FMOD_System_SetSoftwareFormat");
    *cast(void**)&FMOD_System_GetSoftwareFormat = Derelict_GetProc(lib, "FMOD_System_GetSoftwareFormat");
    *cast(void**)&FMOD_System_SetDSPBufferSize = Derelict_GetProc(lib, "FMOD_System_SetDSPBufferSize");
    *cast(void**)&FMOD_System_GetDSPBufferSize = Derelict_GetProc(lib, "FMOD_System_GetDSPBufferSize");
    *cast(void**)&FMOD_System_SetFileSystem = Derelict_GetProc(lib, "FMOD_System_SetFileSystem");
    *cast(void**)&FMOD_System_AttachFileSystem = Derelict_GetProc(lib, "FMOD_System_AttachFileSystem");
    *cast(void**)&FMOD_System_SetAdvancedSettings = Derelict_GetProc(lib, "FMOD_System_SetAdvancedSettings");
    *cast(void**)&FMOD_System_GetAdvancedSettings = Derelict_GetProc(lib, "FMOD_System_GetAdvancedSettings");
    *cast(void**)&FMOD_System_SetSpeakerMode = Derelict_GetProc(lib, "FMOD_System_SetSpeakerMode");
    *cast(void**)&FMOD_System_GetSpeakerMode = Derelict_GetProc(lib, "FMOD_System_GetSpeakerMode");
    *cast(void**)&FMOD_System_SetCallback = Derelict_GetProc(lib, "FMOD_System_SetCallback");

    /*
         Plug-in support
    */

    *cast(void**)&FMOD_System_SetPluginPath = Derelict_GetProc(lib, "FMOD_System_SetPluginPath");
    *cast(void**)&FMOD_System_LoadPlugin = Derelict_GetProc(lib, "FMOD_System_LoadPlugin");
    *cast(void**)&FMOD_System_UnloadPlugin = Derelict_GetProc(lib, "FMOD_System_UnloadPlugin");
    *cast(void**)&FMOD_System_GetNumPlugins = Derelict_GetProc(lib, "FMOD_System_GetNumPlugins");
    *cast(void**)&FMOD_System_GetPluginHandle = Derelict_GetProc(lib, "FMOD_System_GetPluginHandle");
    *cast(void**)&FMOD_System_GetPluginInfo = Derelict_GetProc(lib, "FMOD_System_GetPluginInfo");
    *cast(void**)&FMOD_System_SetOutputByPlugin = Derelict_GetProc(lib, "FMOD_System_SetOutputByPlugin");
    *cast(void**)&FMOD_System_GetOutputByPlugin = Derelict_GetProc(lib, "FMOD_System_GetOutputByPlugin");
    *cast(void**)&FMOD_System_CreateDSPByPlugin = Derelict_GetProc(lib, "FMOD_System_CreateDSPByPlugin");
    *cast(void**)&FMOD_System_CreateCodec = Derelict_GetProc(lib, "FMOD_System_CreateCodec");

    /*
         Init/Close
    */

    *cast(void**)&FMOD_System_Init = Derelict_GetProc(lib, "FMOD_System_Init");
    *cast(void**)&FMOD_System_Close = Derelict_GetProc(lib, "FMOD_System_Close");

    /*
         General post-init system functions
    */

    *cast(void**)&FMOD_System_Update = Derelict_GetProc(lib, "FMOD_System_Update");

    *cast(void**)&FMOD_System_Set3DSettings = Derelict_GetProc(lib, "FMOD_System_Set3DSettings");
    *cast(void**)&FMOD_System_Get3DSettings = Derelict_GetProc(lib, "FMOD_System_Get3DSettings");
    *cast(void**)&FMOD_System_Set3DNumListeners = Derelict_GetProc(lib, "FMOD_System_Set3DNumListeners");
    *cast(void**)&FMOD_System_Get3DNumListeners = Derelict_GetProc(lib, "FMOD_System_Get3DNumListeners");
    *cast(void**)&FMOD_System_Set3DListenerAttributes = Derelict_GetProc(lib, "FMOD_System_Set3DListenerAttributes");
    *cast(void**)&FMOD_System_Get3DListenerAttributes = Derelict_GetProc(lib, "FMOD_System_Get3DListenerAttributes");
    *cast(void**)&FMOD_System_Set3DRolloffCallback = Derelict_GetProc(lib, "FMOD_System_Set3DRolloffCallback");
    *cast(void**)&FMOD_System_Set3DSpeakerPosition = Derelict_GetProc(lib, "FMOD_System_Set3DSpeakerPosition");
    *cast(void**)&FMOD_System_Get3DSpeakerPosition = Derelict_GetProc(lib, "FMOD_System_Get3DSpeakerPosition");

    *cast(void**)&FMOD_System_SetStreamBufferSize = Derelict_GetProc(lib, "FMOD_System_SetStreamBufferSize");
    *cast(void**)&FMOD_System_GetStreamBufferSize = Derelict_GetProc(lib, "FMOD_System_GetStreamBufferSize");

    /*
         System information functions.
    */

    *cast(void**)&FMOD_System_GetVersion = Derelict_GetProc(lib, "FMOD_System_GetVersion");
    *cast(void**)&FMOD_System_GetOutputHandle = Derelict_GetProc(lib, "FMOD_System_GetOutputHandle");
    *cast(void**)&FMOD_System_GetChannelsPlaying = Derelict_GetProc(lib, "FMOD_System_GetChannelsPlaying");
    *cast(void**)&FMOD_System_GetHardwareChannels = Derelict_GetProc(lib, "FMOD_System_GetHardwareChannels");
    *cast(void**)&FMOD_System_GetCPUUsage = Derelict_GetProc(lib, "FMOD_System_GetCPUUsage");
    *cast(void**)&FMOD_System_GetSoundRAM = Derelict_GetProc(lib, "FMOD_System_GetSoundRAM");
    *cast(void**)&FMOD_System_GetNumCDROMDrives = Derelict_GetProc(lib, "FMOD_System_GetNumCDROMDrives");
    *cast(void**)&FMOD_System_GetCDROMDriveName = Derelict_GetProc(lib, "FMOD_System_GetCDROMDriveName");
    *cast(void**)&FMOD_System_GetSpectrum = Derelict_GetProc(lib, "FMOD_System_GetSpectrum");
    *cast(void**)&FMOD_System_GetWaveData = Derelict_GetProc(lib, "FMOD_System_GetWaveData");

    /*
         Sound/DSP/Channel/FX creation and retrieval.
    */

    *cast(void**)&FMOD_System_CreateSound = Derelict_GetProc(lib, "FMOD_System_CreateSound");
    *cast(void**)&FMOD_System_CreateStream = Derelict_GetProc(lib, "FMOD_System_CreateStream");
    *cast(void**)&FMOD_System_CreateDSP = Derelict_GetProc(lib, "FMOD_System_CreateDSP");
    *cast(void**)&FMOD_System_CreateDSPByType = Derelict_GetProc(lib, "FMOD_System_CreateDSPByType");
    *cast(void**)&FMOD_System_CreateChannelGroup = Derelict_GetProc(lib, "FMOD_System_CreateChannelGroup");
    *cast(void**)&FMOD_System_CreateSoundGroup = Derelict_GetProc(lib, "FMOD_System_CreateSoundGroup");
    *cast(void**)&FMOD_System_CreateReverb = Derelict_GetProc(lib, "FMOD_System_CreateReverb");

    *cast(void**)&FMOD_System_PlaySound = Derelict_GetProc(lib, "FMOD_System_PlaySound");
    *cast(void**)&FMOD_System_PlayDSP = Derelict_GetProc(lib, "FMOD_System_PlayDSP");
    *cast(void**)&FMOD_System_GetChannel = Derelict_GetProc(lib, "FMOD_System_GetChannel");
    *cast(void**)&FMOD_System_GetMasterChannelGroup = Derelict_GetProc(lib, "FMOD_System_GetMasterChannelGroup");
    *cast(void**)&FMOD_System_GetMasterSoundGroup = Derelict_GetProc(lib, "FMOD_System_GetMasterSoundGroup");

    /*
         Reverb API
    */

    *cast(void**)&FMOD_System_SetReverbProperties = Derelict_GetProc(lib, "FMOD_System_SetReverbProperties");
    *cast(void**)&FMOD_System_GetReverbProperties = Derelict_GetProc(lib, "FMOD_System_GetReverbProperties");
    *cast(void**)&FMOD_System_SetReverbAmbientProperties = Derelict_GetProc(lib, "FMOD_System_SetReverbAmbientProperties");
    *cast(void**)&FMOD_System_GetReverbAmbientProperties = Derelict_GetProc(lib, "FMOD_System_GetReverbAmbientProperties");

    /*
         System level DSP access.
    */

    *cast(void**)&FMOD_System_GetDSPHead = Derelict_GetProc(lib, "FMOD_System_GetDSPHead");
    *cast(void**)&FMOD_System_AddDSP = Derelict_GetProc(lib, "FMOD_System_AddDSP");
    *cast(void**)&FMOD_System_LockDSP = Derelict_GetProc(lib, "FMOD_System_LockDSP");
    *cast(void**)&FMOD_System_UnlockDSP = Derelict_GetProc(lib, "FMOD_System_UnlockDSP");
    *cast(void**)&FMOD_System_GetDSPClock = Derelict_GetProc(lib, "FMOD_System_GetDSPClock");

    /*
         Recording API.
    */

    *cast(void**)&FMOD_System_GetRecordNumDrivers = Derelict_GetProc(lib, "FMOD_System_GetRecordNumDrivers");
    *cast(void**)&FMOD_System_GetRecordDriverInfo = Derelict_GetProc(lib, "FMOD_System_GetRecordDriverInfo");
    *cast(void**)&FMOD_System_GetRecordDriverInfoW = Derelict_GetProc(lib, "FMOD_System_GetRecordDriverInfoW");
    *cast(void**)&FMOD_System_GetRecordDriverCaps = Derelict_GetProc(lib, "FMOD_System_GetRecordDriverCaps");
    *cast(void**)&FMOD_System_GetRecordPosition = Derelict_GetProc(lib, "FMOD_System_GetRecordPosition");

    *cast(void**)&FMOD_System_RecordStart = Derelict_GetProc(lib, "FMOD_System_RecordStart");
    *cast(void**)&FMOD_System_RecordStop = Derelict_GetProc(lib, "FMOD_System_RecordStop");
    *cast(void**)&FMOD_System_IsRecording = Derelict_GetProc(lib, "FMOD_System_IsRecording");

    /*
         Geometry API.
    */

    *cast(void**)&FMOD_System_CreateGeometry = Derelict_GetProc(lib, "FMOD_System_CreateGeometry");
    *cast(void**)&FMOD_System_SetGeometrySettings = Derelict_GetProc(lib, "FMOD_System_SetGeometrySettings");
    *cast(void**)&FMOD_System_GetGeometrySettings = Derelict_GetProc(lib, "FMOD_System_GetGeometrySettings");
    *cast(void**)&FMOD_System_LoadGeometry = Derelict_GetProc(lib, "FMOD_System_LoadGeometry");
    *cast(void**)&FMOD_System_GetGeometryOcclusion = Derelict_GetProc(lib, "FMOD_System_GetGeometryOcclusion");

    /*
         Network functions.
    */

    *cast(void**)&FMOD_System_SetNetworkProxy = Derelict_GetProc(lib, "FMOD_System_SetNetworkProxy");
    *cast(void**)&FMOD_System_GetNetworkProxy = Derelict_GetProc(lib, "FMOD_System_GetNetworkProxy");
    *cast(void**)&FMOD_System_SetNetworkTimeout = Derelict_GetProc(lib, "FMOD_System_SetNetworkTimeout");
    *cast(void**)&FMOD_System_GetNetworkTimeout = Derelict_GetProc(lib, "FMOD_System_GetNetworkTimeout");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_System_SetUserData = Derelict_GetProc(lib, "FMOD_System_SetUserData");
    *cast(void**)&FMOD_System_GetUserData = Derelict_GetProc(lib, "FMOD_System_GetUserData");

    *cast(void**)&FMOD_System_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_System_GetMemoryInfo");

    /*
        'Sound' API
    */

    *cast(void**)&FMOD_Sound_Release = Derelict_GetProc(lib, "FMOD_Sound_Release");
    *cast(void**)&FMOD_Sound_GetSystemObject = Derelict_GetProc(lib, "FMOD_Sound_GetSystemObject");

    /*
         Standard sound manipulation functions.
    */

    *cast(void**)&FMOD_Sound_Lock = Derelict_GetProc(lib, "FMOD_Sound_Lock");
    *cast(void**)&FMOD_Sound_Unlock = Derelict_GetProc(lib, "FMOD_Sound_Unlock");
    *cast(void**)&FMOD_Sound_SetDefaults = Derelict_GetProc(lib, "FMOD_Sound_SetDefaults");
    *cast(void**)&FMOD_Sound_GetDefaults = Derelict_GetProc(lib, "FMOD_Sound_GetDefaults");
    *cast(void**)&FMOD_Sound_SetVariations = Derelict_GetProc(lib, "FMOD_Sound_SetVariations");
    *cast(void**)&FMOD_Sound_GetVariations = Derelict_GetProc(lib, "FMOD_Sound_GetVariations");
    *cast(void**)&FMOD_Sound_Set3DMinMaxDistance = Derelict_GetProc(lib, "FMOD_Sound_Set3DMinMaxDistance");
    *cast(void**)&FMOD_Sound_Get3DMinMaxDistance = Derelict_GetProc(lib, "FMOD_Sound_Get3DMinMaxDistance");
    *cast(void**)&FMOD_Sound_Set3DConeSettings = Derelict_GetProc(lib, "FMOD_Sound_Set3DConeSettings");
    *cast(void**)&FMOD_Sound_Get3DConeSettings = Derelict_GetProc(lib, "FMOD_Sound_Get3DConeSettings");
    *cast(void**)&FMOD_Sound_Set3DCustomRolloff = Derelict_GetProc(lib, "FMOD_Sound_Set3DCustomRolloff");
    *cast(void**)&FMOD_Sound_Get3DCustomRolloff = Derelict_GetProc(lib, "FMOD_Sound_Get3DCustomRolloff");
    *cast(void**)&FMOD_Sound_SetSubSound = Derelict_GetProc(lib, "FMOD_Sound_SetSubSound");
    *cast(void**)&FMOD_Sound_GetSubSound = Derelict_GetProc(lib, "FMOD_Sound_GetSubSound");
    *cast(void**)&FMOD_Sound_SetSubSoundSentence = Derelict_GetProc(lib, "FMOD_Sound_SetSubSoundSentence");
    *cast(void**)&FMOD_Sound_GetName = Derelict_GetProc(lib, "FMOD_Sound_GetName");
    *cast(void**)&FMOD_Sound_GetLength = Derelict_GetProc(lib, "FMOD_Sound_GetLength");
    *cast(void**)&FMOD_Sound_GetFormat = Derelict_GetProc(lib, "FMOD_Sound_GetFormat");
    *cast(void**)&FMOD_Sound_GetNumSubSounds = Derelict_GetProc(lib, "FMOD_Sound_GetNumSubSounds");
    *cast(void**)&FMOD_Sound_GetNumTags = Derelict_GetProc(lib, "FMOD_Sound_GetNumTags");
    *cast(void**)&FMOD_Sound_GetTag = Derelict_GetProc(lib, "FMOD_Sound_GetTag");
    *cast(void**)&FMOD_Sound_GetOpenState = Derelict_GetProc(lib, "FMOD_Sound_GetOpenState");
    *cast(void**)&FMOD_Sound_ReadData = Derelict_GetProc(lib, "FMOD_Sound_ReadData");
    *cast(void**)&FMOD_Sound_SeekData = Derelict_GetProc(lib, "FMOD_Sound_SeekData");

    *cast(void**)&FMOD_Sound_SetSoundGroup = Derelict_GetProc(lib, "FMOD_Sound_SetSoundGroup");
    *cast(void**)&FMOD_Sound_GetSoundGroup = Derelict_GetProc(lib, "FMOD_Sound_GetSoundGroup");

    /*
         Synchronization point API.  These points can come from markers embedded in wav files, and can also generate channel callbacks.
    */

    *cast(void**)&FMOD_Sound_GetNumSyncPoints = Derelict_GetProc(lib, "FMOD_Sound_GetNumSyncPoints");
    *cast(void**)&FMOD_Sound_GetSyncPoint = Derelict_GetProc(lib, "FMOD_Sound_GetSyncPoint");
    *cast(void**)&FMOD_Sound_GetSyncPointInfo = Derelict_GetProc(lib, "FMOD_Sound_GetSyncPointInfo");
    *cast(void**)&FMOD_Sound_AddSyncPoint = Derelict_GetProc(lib, "FMOD_Sound_AddSyncPoint");
    *cast(void**)&FMOD_Sound_DeleteSyncPoint = Derelict_GetProc(lib, "FMOD_Sound_DeleteSyncPoint");

    /*
         Functions also in Channel class but here they are the 'default' to save having to change it in Channel all the time.
    */

    *cast(void**)&FMOD_Sound_SetMode = Derelict_GetProc(lib, "FMOD_Sound_SetMode");
    *cast(void**)&FMOD_Sound_GetMode = Derelict_GetProc(lib, "FMOD_Sound_GetMode");
    *cast(void**)&FMOD_Sound_SetLoopCount = Derelict_GetProc(lib, "FMOD_Sound_SetLoopCount");
    *cast(void**)&FMOD_Sound_GetLoopCount = Derelict_GetProc(lib, "FMOD_Sound_GetLoopCount");
    *cast(void**)&FMOD_Sound_SetLoopPoints = Derelict_GetProc(lib, "FMOD_Sound_SetLoopPoints");
    *cast(void**)&FMOD_Sound_GetLoopPoints = Derelict_GetProc(lib, "FMOD_Sound_GetLoopPoints");

    /*
         For MOD/S3M/XM/IT/MID sequenced formats only.
    */

    *cast(void**)&FMOD_Sound_GetMusicNumChannels = Derelict_GetProc(lib, "FMOD_Sound_GetMusicNumChannels");
    *cast(void**)&FMOD_Sound_SetMusicChannelVolume = Derelict_GetProc(lib, "FMOD_Sound_SetMusicChannelVolume");
    *cast(void**)&FMOD_Sound_GetMusicChannelVolume = Derelict_GetProc(lib, "FMOD_Sound_GetMusicChannelVolume");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_Sound_SetUserData = Derelict_GetProc(lib, "FMOD_Sound_SetUserData");
    *cast(void**)&FMOD_Sound_GetUserData = Derelict_GetProc(lib, "FMOD_Sound_GetUserData");

    *cast(void**)&FMOD_Sound_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_Sound_GetMemoryInfo");

    /*
        'Channel' API
    */

    *cast(void**)&FMOD_Channel_GetSystemObject = Derelict_GetProc(lib, "FMOD_Channel_GetSystemObject");

    *cast(void**)&FMOD_Channel_Stop = Derelict_GetProc(lib, "FMOD_Channel_Stop");
    *cast(void**)&FMOD_Channel_SetPaused = Derelict_GetProc(lib, "FMOD_Channel_SetPaused");
    *cast(void**)&FMOD_Channel_GetPaused = Derelict_GetProc(lib, "FMOD_Channel_GetPaused");
    *cast(void**)&FMOD_Channel_SetVolume = Derelict_GetProc(lib, "FMOD_Channel_SetVolume");
    *cast(void**)&FMOD_Channel_GetVolume = Derelict_GetProc(lib, "FMOD_Channel_GetVolume");
    *cast(void**)&FMOD_Channel_SetFrequency = Derelict_GetProc(lib, "FMOD_Channel_SetFrequency");
    *cast(void**)&FMOD_Channel_GetFrequency = Derelict_GetProc(lib, "FMOD_Channel_GetFrequency");
    *cast(void**)&FMOD_Channel_SetPan = Derelict_GetProc(lib, "FMOD_Channel_SetPan");
    *cast(void**)&FMOD_Channel_GetPan = Derelict_GetProc(lib, "FMOD_Channel_GetPan");
    *cast(void**)&FMOD_Channel_SetDelay = Derelict_GetProc(lib, "FMOD_Channel_SetDelay");
    *cast(void**)&FMOD_Channel_GetDelay = Derelict_GetProc(lib, "FMOD_Channel_GetDelay");
    *cast(void**)&FMOD_Channel_SetSpeakerMix = Derelict_GetProc(lib, "FMOD_Channel_SetSpeakerMix");
    *cast(void**)&FMOD_Channel_GetSpeakerMix = Derelict_GetProc(lib, "FMOD_Channel_GetSpeakerMix");
    *cast(void**)&FMOD_Channel_SetSpeakerLevels = Derelict_GetProc(lib, "FMOD_Channel_SetSpeakerLevels");
    *cast(void**)&FMOD_Channel_GetSpeakerLevels = Derelict_GetProc(lib, "FMOD_Channel_GetSpeakerLevels");
    *cast(void**)&FMOD_Channel_SetInputChannelMix = Derelict_GetProc(lib, "FMOD_Channel_SetInputChannelMix");
    *cast(void**)&FMOD_Channel_GetInputChannelMix = Derelict_GetProc(lib, "FMOD_Channel_GetInputChannelMix");
    *cast(void**)&FMOD_Channel_SetMute = Derelict_GetProc(lib, "FMOD_Channel_SetMute");
    *cast(void**)&FMOD_Channel_GetMute = Derelict_GetProc(lib, "FMOD_Channel_GetMute");
    *cast(void**)&FMOD_Channel_SetPriority = Derelict_GetProc(lib, "FMOD_Channel_SetPriority");
    *cast(void**)&FMOD_Channel_GetPriority = Derelict_GetProc(lib, "FMOD_Channel_GetPriority");
    *cast(void**)&FMOD_Channel_SetPosition = Derelict_GetProc(lib, "FMOD_Channel_SetPosition");
    *cast(void**)&FMOD_Channel_GetPosition = Derelict_GetProc(lib, "FMOD_Channel_GetPosition");
    *cast(void**)&FMOD_Channel_SetReverbProperties = Derelict_GetProc(lib, "FMOD_Channel_SetReverbProperties");
    *cast(void**)&FMOD_Channel_GetReverbProperties = Derelict_GetProc(lib, "FMOD_Channel_GetReverbProperties");
    *cast(void**)&FMOD_Channel_SetLowPassGain = Derelict_GetProc(lib, "FMOD_Channel_SetLowPassGain");
    *cast(void**)&FMOD_Channel_GetLowPassGain = Derelict_GetProc(lib, "FMOD_Channel_GetLowPassGain");

    *cast(void**)&FMOD_Channel_SetChannelGroup = Derelict_GetProc(lib, "FMOD_Channel_SetChannelGroup");
    *cast(void**)&FMOD_Channel_GetChannelGroup = Derelict_GetProc(lib, "FMOD_Channel_GetChannelGroup");
    *cast(void**)&FMOD_Channel_SetCallback = Derelict_GetProc(lib, "FMOD_Channel_SetCallback");

    /*
         3D functionality.
    */

    *cast(void**)&FMOD_Channel_Set3DAttributes = Derelict_GetProc(lib, "FMOD_Channel_Set3DAttributes");
    *cast(void**)&FMOD_Channel_Get3DAttributes = Derelict_GetProc(lib, "FMOD_Channel_Get3DAttributes");
    *cast(void**)&FMOD_Channel_Set3DMinMaxDistance = Derelict_GetProc(lib, "FMOD_Channel_Set3DMinMaxDistance");
    *cast(void**)&FMOD_Channel_Get3DMinMaxDistance = Derelict_GetProc(lib, "FMOD_Channel_Get3DMinMaxDistance");
    *cast(void**)&FMOD_Channel_Set3DConeSettings = Derelict_GetProc(lib, "FMOD_Channel_Set3DConeSettings");
    *cast(void**)&FMOD_Channel_Get3DConeSettings = Derelict_GetProc(lib, "FMOD_Channel_Get3DConeSettings");
    *cast(void**)&FMOD_Channel_Set3DConeOrientation = Derelict_GetProc(lib, "FMOD_Channel_Set3DConeOrientation");
    *cast(void**)&FMOD_Channel_Get3DConeOrientation = Derelict_GetProc(lib, "FMOD_Channel_Get3DConeOrientation");
    *cast(void**)&FMOD_Channel_Set3DCustomRolloff = Derelict_GetProc(lib, "FMOD_Channel_Set3DCustomRolloff");
    *cast(void**)&FMOD_Channel_Get3DCustomRolloff = Derelict_GetProc(lib, "FMOD_Channel_Get3DCustomRolloff");
    *cast(void**)&FMOD_Channel_Set3DOcclusion = Derelict_GetProc(lib, "FMOD_Channel_Set3DOcclusion");
    *cast(void**)&FMOD_Channel_Get3DOcclusion = Derelict_GetProc(lib, "FMOD_Channel_Get3DOcclusion");
    *cast(void**)&FMOD_Channel_Set3DSpread = Derelict_GetProc(lib, "FMOD_Channel_Set3DSpread");
    *cast(void**)&FMOD_Channel_Get3DSpread = Derelict_GetProc(lib, "FMOD_Channel_Get3DSpread");
    *cast(void**)&FMOD_Channel_Set3DPanLevel = Derelict_GetProc(lib, "FMOD_Channel_Set3DPanLevel");
    *cast(void**)&FMOD_Channel_Get3DPanLevel = Derelict_GetProc(lib, "FMOD_Channel_Get3DPanLevel");
    *cast(void**)&FMOD_Channel_Set3DDopplerLevel = Derelict_GetProc(lib, "FMOD_Channel_Set3DDopplerLevel");
    *cast(void**)&FMOD_Channel_Get3DDopplerLevel = Derelict_GetProc(lib, "FMOD_Channel_Get3DDopplerLevel");

    /*
         DSP functionality only for channels playing sounds created with FMOD_SOFTWARE.
    */

    *cast(void**)&FMOD_Channel_GetDSPHead = Derelict_GetProc(lib, "FMOD_Channel_GetDSPHead");
    *cast(void**)&FMOD_Channel_AddDSP = Derelict_GetProc(lib, "FMOD_Channel_AddDSP");

    /*
         Information only functions.
    */

    *cast(void**)&FMOD_Channel_IsPlaying = Derelict_GetProc(lib, "FMOD_Channel_IsPlaying");
    *cast(void**)&FMOD_Channel_IsVirtual = Derelict_GetProc(lib, "FMOD_Channel_IsVirtual");
    *cast(void**)&FMOD_Channel_GetAudibility = Derelict_GetProc(lib, "FMOD_Channel_GetAudibility");
    *cast(void**)&FMOD_Channel_GetCurrentSound = Derelict_GetProc(lib, "FMOD_Channel_GetCurrentSound");
    *cast(void**)&FMOD_Channel_GetSpectrum = Derelict_GetProc(lib, "FMOD_Channel_GetSpectrum");
    *cast(void**)&FMOD_Channel_GetWaveData = Derelict_GetProc(lib, "FMOD_Channel_GetWaveData");
    *cast(void**)&FMOD_Channel_GetIndex = Derelict_GetProc(lib, "FMOD_Channel_GetIndex");

    /*
         Functions also found in Sound class but here they can be set per channel.
    */

    *cast(void**)&FMOD_Channel_SetMode = Derelict_GetProc(lib, "FMOD_Channel_SetMode");
    *cast(void**)&FMOD_Channel_GetMode = Derelict_GetProc(lib, "FMOD_Channel_GetMode");
    *cast(void**)&FMOD_Channel_SetLoopCount = Derelict_GetProc(lib, "FMOD_Channel_SetLoopCount");
    *cast(void**)&FMOD_Channel_GetLoopCount = Derelict_GetProc(lib, "FMOD_Channel_GetLoopCount");
    *cast(void**)&FMOD_Channel_SetLoopPoints = Derelict_GetProc(lib, "FMOD_Channel_SetLoopPoints");
    *cast(void**)&FMOD_Channel_GetLoopPoints = Derelict_GetProc(lib, "FMOD_Channel_GetLoopPoints");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_Channel_SetUserData = Derelict_GetProc(lib, "FMOD_Channel_SetUserData");
    *cast(void**)&FMOD_Channel_GetUserData = Derelict_GetProc(lib, "FMOD_Channel_GetUserData");

    *cast(void**)&FMOD_Channel_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_Channel_GetMemoryInfo");

    /*
        'ChannelGroup' API
    */

    *cast(void**)&FMOD_ChannelGroup_Release = Derelict_GetProc(lib, "FMOD_ChannelGroup_Release");
    *cast(void**)&FMOD_ChannelGroup_GetSystemObject = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetSystemObject");

    /*
         Channelgroup scale values.  (changes attributes relative to the channels, doesn't overwrite them)
    */

    *cast(void**)&FMOD_ChannelGroup_SetVolume = Derelict_GetProc(lib, "FMOD_ChannelGroup_SetVolume");
    *cast(void**)&FMOD_ChannelGroup_GetVolume = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetVolume");
    *cast(void**)&FMOD_ChannelGroup_SetPitch = Derelict_GetProc(lib, "FMOD_ChannelGroup_SetPitch");
    *cast(void**)&FMOD_ChannelGroup_GetPitch = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetPitch");
    *cast(void**)&FMOD_ChannelGroup_Set3DOcclusion = Derelict_GetProc(lib, "FMOD_ChannelGroup_Set3DOcclusion");
    *cast(void**)&FMOD_ChannelGroup_Get3DOcclusion = Derelict_GetProc(lib, "FMOD_ChannelGroup_Get3DOcclusion");
    *cast(void**)&FMOD_ChannelGroup_SetPaused = Derelict_GetProc(lib, "FMOD_ChannelGroup_SetPaused");
    *cast(void**)&FMOD_ChannelGroup_GetPaused = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetPaused");
    *cast(void**)&FMOD_ChannelGroup_SetMute = Derelict_GetProc(lib, "FMOD_ChannelGroup_SetMute");
    *cast(void**)&FMOD_ChannelGroup_GetMute = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetMute");

    /*
         Channelgroup override values.  (recursively overwrites whatever settings the channels had)
    */

    *cast(void**)&FMOD_ChannelGroup_Stop = Derelict_GetProc(lib, "FMOD_ChannelGroup_Stop");
    *cast(void**)&FMOD_ChannelGroup_OverrideVolume = Derelict_GetProc(lib, "FMOD_ChannelGroup_OverrideVolume");
    *cast(void**)&FMOD_ChannelGroup_OverrideFrequency = Derelict_GetProc(lib, "FMOD_ChannelGroup_OverrideFrequency");
    *cast(void**)&FMOD_ChannelGroup_OverridePan = Derelict_GetProc(lib, "FMOD_ChannelGroup_OverridePan");
    *cast(void**)&FMOD_ChannelGroup_OverrideReverbProperties = Derelict_GetProc(lib, "FMOD_ChannelGroup_OverrideReverbProperties");
    *cast(void**)&FMOD_ChannelGroup_Override3DAttributes = Derelict_GetProc(lib, "FMOD_ChannelGroup_Override3DAttributes");
    *cast(void**)&FMOD_ChannelGroup_OverrideSpeakerMix = Derelict_GetProc(lib, "FMOD_ChannelGroup_OverrideSpeakerMix");

    /*
         Nested channel groups.
    */

    *cast(void**)&FMOD_ChannelGroup_AddGroup = Derelict_GetProc(lib, "FMOD_ChannelGroup_AddGroup");
    *cast(void**)&FMOD_ChannelGroup_GetNumGroups = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetNumGroups");
    *cast(void**)&FMOD_ChannelGroup_GetGroup = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetGroup");
    *cast(void**)&FMOD_ChannelGroup_GetParentGroup = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetParentGroup");

    /*
         DSP functionality only for channel groups playing sounds created with FMOD_SOFTWARE.
    */

    *cast(void**)&FMOD_ChannelGroup_GetDSPHead = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetDSPHead");
    *cast(void**)&FMOD_ChannelGroup_AddDSP = Derelict_GetProc(lib, "FMOD_ChannelGroup_AddDSP");

    /*
         Information only functions.
    */

    *cast(void**)&FMOD_ChannelGroup_GetName = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetName");
    *cast(void**)&FMOD_ChannelGroup_GetNumChannels = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetNumChannels");
    *cast(void**)&FMOD_ChannelGroup_GetChannel = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetChannel");
    *cast(void**)&FMOD_ChannelGroup_GetSpectrum = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetSpectrum");
    *cast(void**)&FMOD_ChannelGroup_GetWaveData = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetWaveData");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_ChannelGroup_SetUserData = Derelict_GetProc(lib, "FMOD_ChannelGroup_SetUserData");
    *cast(void**)&FMOD_ChannelGroup_GetUserData = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetUserData");

    *cast(void**)&FMOD_ChannelGroup_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_ChannelGroup_GetMemoryInfo");

    /*
        'SoundGroup' API
    */

    *cast(void**)&FMOD_SoundGroup_Release = Derelict_GetProc(lib, "FMOD_SoundGroup_Release");
    *cast(void**)&FMOD_SoundGroup_GetSystemObject = Derelict_GetProc(lib, "FMOD_SoundGroup_GetSystemObject");

    /*
         SoundGroup control functions.
    */

    *cast(void**)&FMOD_SoundGroup_SetMaxAudible = Derelict_GetProc(lib, "FMOD_SoundGroup_SetMaxAudible");
    *cast(void**)&FMOD_SoundGroup_GetMaxAudible = Derelict_GetProc(lib, "FMOD_SoundGroup_GetMaxAudible");
    *cast(void**)&FMOD_SoundGroup_SetMaxAudibleBehavior = Derelict_GetProc(lib, "FMOD_SoundGroup_SetMaxAudibleBehavior");
    *cast(void**)&FMOD_SoundGroup_GetMaxAudibleBehavior = Derelict_GetProc(lib, "FMOD_SoundGroup_GetMaxAudibleBehavior");
    *cast(void**)&FMOD_SoundGroup_SetMuteFadeSpeed = Derelict_GetProc(lib, "FMOD_SoundGroup_SetMuteFadeSpeed");
    *cast(void**)&FMOD_SoundGroup_GetMuteFadeSpeed = Derelict_GetProc(lib, "FMOD_SoundGroup_GetMuteFadeSpeed");
    *cast(void**)&FMOD_SoundGroup_SetVolume = Derelict_GetProc(lib, "FMOD_SoundGroup_SetVolume");
    *cast(void**)&FMOD_SoundGroup_GetVolume = Derelict_GetProc(lib, "FMOD_SoundGroup_GetVolume");
    *cast(void**)&FMOD_SoundGroup_Stop = Derelict_GetProc(lib, "FMOD_SoundGroup_Stop");

    /*
         Information only functions.
    */

    *cast(void**)&FMOD_SoundGroup_GetName = Derelict_GetProc(lib, "FMOD_SoundGroup_GetName");
    *cast(void**)&FMOD_SoundGroup_GetNumSounds = Derelict_GetProc(lib, "FMOD_SoundGroup_GetNumSounds");
    *cast(void**)&FMOD_SoundGroup_GetSound = Derelict_GetProc(lib, "FMOD_SoundGroup_GetSound");
    *cast(void**)&FMOD_SoundGroup_GetNumPlaying = Derelict_GetProc(lib, "FMOD_SoundGroup_GetNumPlaying");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_SoundGroup_SetUserData = Derelict_GetProc(lib, "FMOD_SoundGroup_SetUserData");
    *cast(void**)&FMOD_SoundGroup_GetUserData = Derelict_GetProc(lib, "FMOD_SoundGroup_GetUserData");

    *cast(void**)&FMOD_SoundGroup_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_SoundGroup_GetMemoryInfo");

    /*
        'DSP' API
    */

    *cast(void**)&FMOD_DSP_Release = Derelict_GetProc(lib, "FMOD_DSP_Release");
    *cast(void**)&FMOD_DSP_GetSystemObject = Derelict_GetProc(lib, "FMOD_DSP_GetSystemObject");

    /*
         Connection / disconnection / input and output enumeration.
    */

    *cast(void**)&FMOD_DSP_AddInput = Derelict_GetProc(lib, "FMOD_DSP_AddInput");
    *cast(void**)&FMOD_DSP_DisconnectFrom = Derelict_GetProc(lib, "FMOD_DSP_DisconnectFrom");
    *cast(void**)&FMOD_DSP_DisconnectAll = Derelict_GetProc(lib, "FMOD_DSP_DisconnectAll");
    *cast(void**)&FMOD_DSP_Remove = Derelict_GetProc(lib, "FMOD_DSP_Remove");
    *cast(void**)&FMOD_DSP_GetNumInputs = Derelict_GetProc(lib, "FMOD_DSP_GetNumInputs");
    *cast(void**)&FMOD_DSP_GetNumOutputs = Derelict_GetProc(lib, "FMOD_DSP_GetNumOutputs");
    *cast(void**)&FMOD_DSP_GetInput = Derelict_GetProc(lib, "FMOD_DSP_GetInput");
    *cast(void**)&FMOD_DSP_GetOutput = Derelict_GetProc(lib, "FMOD_DSP_GetOutput");

    /*
         DSP unit control.
    */

    *cast(void**)&FMOD_DSP_SetActive = Derelict_GetProc(lib, "FMOD_DSP_SetActive");
    *cast(void**)&FMOD_DSP_GetActive = Derelict_GetProc(lib, "FMOD_DSP_GetActive");
    *cast(void**)&FMOD_DSP_SetBypass = Derelict_GetProc(lib, "FMOD_DSP_SetBypass");
    *cast(void**)&FMOD_DSP_GetBypass = Derelict_GetProc(lib, "FMOD_DSP_GetBypass");
    *cast(void**)&FMOD_DSP_SetSpeakerActive = Derelict_GetProc(lib, "FMOD_DSP_SetSpeakerActive");
    *cast(void**)&FMOD_DSP_GetSpeakerActive = Derelict_GetProc(lib, "FMOD_DSP_GetSpeakerActive");
    *cast(void**)&FMOD_DSP_Reset = Derelict_GetProc(lib, "FMOD_DSP_Reset");

    /*
         DSP parameter control.
    */

    *cast(void**)&FMOD_DSP_SetParameter = Derelict_GetProc(lib, "FMOD_DSP_SetParameter");
    *cast(void**)&FMOD_DSP_GetParameter = Derelict_GetProc(lib, "FMOD_DSP_GetParameter");
    *cast(void**)&FMOD_DSP_GetNumParameters = Derelict_GetProc(lib, "FMOD_DSP_GetNumParameters");
    *cast(void**)&FMOD_DSP_GetParameterInfo = Derelict_GetProc(lib, "FMOD_DSP_GetParameterInfo");
    *cast(void**)&FMOD_DSP_ShowConfigDialog = Derelict_GetProc(lib, "FMOD_DSP_ShowConfigDialog");

    /*
         DSP attributes.
    */

    *cast(void**)&FMOD_DSP_GetInfo = Derelict_GetProc(lib, "FMOD_DSP_GetInfo");
    *cast(void**)&FMOD_DSP_GetType = Derelict_GetProc(lib, "FMOD_DSP_GetType");
    *cast(void**)&FMOD_DSP_SetDefaults = Derelict_GetProc(lib, "FMOD_DSP_SetDefaults");
    *cast(void**)&FMOD_DSP_GetDefaults = Derelict_GetProc(lib, "FMOD_DSP_GetDefaults");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_DSP_SetUserData = Derelict_GetProc(lib, "FMOD_DSP_SetUserData");
    *cast(void**)&FMOD_DSP_GetUserData = Derelict_GetProc(lib, "FMOD_DSP_GetUserData");

    *cast(void**)&FMOD_DSP_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_DSP_GetMemoryInfo");

    /*
        'DSPConnection' API
    */

    *cast(void**)&FMOD_DSPConnection_GetInput = Derelict_GetProc(lib, "FMOD_DSPConnection_GetInput");
    *cast(void**)&FMOD_DSPConnection_GetOutput = Derelict_GetProc(lib, "FMOD_DSPConnection_GetOutput");
    *cast(void**)&FMOD_DSPConnection_SetMix = Derelict_GetProc(lib, "FMOD_DSPConnection_SetMix");
    *cast(void**)&FMOD_DSPConnection_GetMix = Derelict_GetProc(lib, "FMOD_DSPConnection_GetMix");
    *cast(void**)&FMOD_DSPConnection_SetLevels = Derelict_GetProc(lib, "FMOD_DSPConnection_SetLevels");
    *cast(void**)&FMOD_DSPConnection_GetLevels = Derelict_GetProc(lib, "FMOD_DSPConnection_GetLevels");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_DSPConnection_SetUserData = Derelict_GetProc(lib, "FMOD_DSPConnection_SetUserData");
    *cast(void**)&FMOD_DSPConnection_GetUserData = Derelict_GetProc(lib, "FMOD_DSPConnection_GetUserData");

    *cast(void**)&FMOD_DSPConnection_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_DSPConnection_GetMemoryInfo");

    /*
        'Geometry' API
    */

    *cast(void**)&FMOD_Geometry_Release = Derelict_GetProc(lib, "FMOD_Geometry_Release");

    /*
         Polygon manipulation.
    */

    *cast(void**)&FMOD_Geometry_AddPolygon = Derelict_GetProc(lib, "FMOD_Geometry_AddPolygon");
    *cast(void**)&FMOD_Geometry_GetNumPolygons = Derelict_GetProc(lib, "FMOD_Geometry_GetNumPolygons");
    *cast(void**)&FMOD_Geometry_GetMaxPolygons = Derelict_GetProc(lib, "FMOD_Geometry_GetMaxPolygons");
    *cast(void**)&FMOD_Geometry_GetPolygonNumVertices = Derelict_GetProc(lib, "FMOD_Geometry_GetPolygonNumVertices");
    *cast(void**)&FMOD_Geometry_SetPolygonVertex = Derelict_GetProc(lib, "FMOD_Geometry_SetPolygonVertex");
    *cast(void**)&FMOD_Geometry_GetPolygonVertex = Derelict_GetProc(lib, "FMOD_Geometry_GetPolygonVertex");
    *cast(void**)&FMOD_Geometry_SetPolygonAttributes = Derelict_GetProc(lib, "FMOD_Geometry_SetPolygonAttributes");
    *cast(void**)&FMOD_Geometry_GetPolygonAttributes = Derelict_GetProc(lib, "FMOD_Geometry_GetPolygonAttributes");

    /*
         Object manipulation.
    */

    *cast(void**)&FMOD_Geometry_SetActive = Derelict_GetProc(lib, "FMOD_Geometry_SetActive");
    *cast(void**)&FMOD_Geometry_GetActive = Derelict_GetProc(lib, "FMOD_Geometry_GetActive");
    *cast(void**)&FMOD_Geometry_SetRotation = Derelict_GetProc(lib, "FMOD_Geometry_SetRotation");
    *cast(void**)&FMOD_Geometry_GetRotation = Derelict_GetProc(lib, "FMOD_Geometry_GetRotation");
    *cast(void**)&FMOD_Geometry_SetPosition = Derelict_GetProc(lib, "FMOD_Geometry_SetPosition");
    *cast(void**)&FMOD_Geometry_GetPosition = Derelict_GetProc(lib, "FMOD_Geometry_GetPosition");
    *cast(void**)&FMOD_Geometry_SetScale = Derelict_GetProc(lib, "FMOD_Geometry_SetScale");
    *cast(void**)&FMOD_Geometry_GetScale = Derelict_GetProc(lib, "FMOD_Geometry_GetScale");
    *cast(void**)&FMOD_Geometry_Save = Derelict_GetProc(lib, "FMOD_Geometry_Save");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_Geometry_SetUserData = Derelict_GetProc(lib, "FMOD_Geometry_SetUserData");
    *cast(void**)&FMOD_Geometry_GetUserData = Derelict_GetProc(lib, "FMOD_Geometry_GetUserData");

    *cast(void**)&FMOD_Geometry_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_Geometry_GetMemoryInfo");

    /*
        'Reverb' API
    */

    *cast(void**)&FMOD_Reverb_Release = Derelict_GetProc(lib, "FMOD_Reverb_Release");

    /*
         Reverb manipulation.
    */

    *cast(void**)&FMOD_Reverb_Set3DAttributes = Derelict_GetProc(lib, "FMOD_Reverb_Set3DAttributes");
    *cast(void**)&FMOD_Reverb_Get3DAttributes = Derelict_GetProc(lib, "FMOD_Reverb_Get3DAttributes");
    *cast(void**)&FMOD_Reverb_SetProperties = Derelict_GetProc(lib, "FMOD_Reverb_SetProperties");
    *cast(void**)&FMOD_Reverb_GetProperties = Derelict_GetProc(lib, "FMOD_Reverb_GetProperties");
    *cast(void**)&FMOD_Reverb_SetActive = Derelict_GetProc(lib, "FMOD_Reverb_SetActive");
    *cast(void**)&FMOD_Reverb_GetActive = Derelict_GetProc(lib, "FMOD_Reverb_GetActive");

    /*
         Userdata set/get.
    */

    *cast(void**)&FMOD_Reverb_SetUserData = Derelict_GetProc(lib, "FMOD_Reverb_SetUserData");
    *cast(void**)&FMOD_Reverb_GetUserData = Derelict_GetProc(lib, "FMOD_Reverb_GetUserData");

    *cast(void**)&FMOD_Reverb_GetMemoryInfo = Derelict_GetProc(lib, "FMOD_Reverb_GetMemoryInfo");
}

GenericLoader DerelictFMOD;
static this() {
    DerelictFMOD.setup(
        "fmodex.dll, fmodexp.dll",
        "libfmodex.so, libfmodexp.so",
        "",
        &load
    );
}
