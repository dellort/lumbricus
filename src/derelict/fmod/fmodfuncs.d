module derelict.fmod.fmodfuncs;

/* ========================================================================================== */
/* FUNCTION PROTOTYPES                                                                        */
/* ========================================================================================== */

//How to convert fmod.h functions (POSIX Extended RE):
//  S: FMOD_RESULT F_API (\w+)\s*\(([^\)]+)\);
//  R1: FMOD_RESULT function\(\2\) \1;
//  R2: bindFunc(\1)("\1", lib);

private {
    import derelict.fmod.fmodtypes;
    import derelict.fmod.fmodcodec;
    import derelict.fmod.fmoddsp;

    import derelict.util.loader;
}

extern(System):

/*
    FMOD global system functions (optional).
*/

FMOD_RESULT function(void *poolmem, int poollen, FMOD_MEMORY_ALLOCCALLBACK useralloc, FMOD_MEMORY_REALLOCCALLBACK userrealloc, FMOD_MEMORY_FREECALLBACK userfree, FMOD_MEMORY_TYPE memtypeflags) FMOD_Memory_Initialize;
FMOD_RESULT function(int *currentalloced, int *maxalloced) FMOD_Memory_GetStats;
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
FMOD_RESULT function(FMOD_SYSTEM *system, float *dsp, float *stream, float *update, float *total) FMOD_System_GetCPUUsage;
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

FMOD_RESULT function(FMOD_SYSTEM *system, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_System_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_SOUND *sound, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_Sound_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_CHANNEL *channel, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_Channel_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_CHANNELGROUP *channelgroup, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_ChannelGroup_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_SOUNDGROUP *soundgroup, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_SoundGroup_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_DSP *dsp, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_DSP_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_DSPCONNECTION *dspconnection, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_DSPConnection_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_GEOMETRY *geometry, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_Geometry_GetMemoryInfo;

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

FMOD_RESULT function(FMOD_REVERB *reverb, uint memorybits, uint event_memorybits, uint *memoryused, uint *memoryused_array) FMOD_Reverb_GetMemoryInfo;


extern(D):

private void load(SharedLib lib) {
    /*
        FMOD global system functions (optional).
    */

    bindFunc(FMOD_Memory_Initialize)("FMOD_Memory_Initialize", lib);
    bindFunc(FMOD_Memory_GetStats)("FMOD_Memory_GetStats", lib);
    bindFunc(FMOD_Debug_SetLevel)("FMOD_Debug_SetLevel", lib);
    bindFunc(FMOD_Debug_GetLevel)("FMOD_Debug_GetLevel", lib);
    bindFunc(FMOD_File_SetDiskBusy)("FMOD_File_SetDiskBusy", lib);
    bindFunc(FMOD_File_GetDiskBusy)("FMOD_File_GetDiskBusy", lib);

    /*
        FMOD System factory functions.  Use this to create an FMOD System Instance.  below you will see FMOD_System_Init/Close to get started.
    */

    bindFunc(FMOD_System_Create)("FMOD_System_Create", lib);
    bindFunc(FMOD_System_Release)("FMOD_System_Release", lib);


    /*
        'System' API
    */

    /*
         Pre-init functions.
    */

    bindFunc(FMOD_System_SetOutput)("FMOD_System_SetOutput", lib);
    bindFunc(FMOD_System_GetOutput)("FMOD_System_GetOutput", lib);
    bindFunc(FMOD_System_GetNumDrivers)("FMOD_System_GetNumDrivers", lib);
    bindFunc(FMOD_System_GetDriverInfo)("FMOD_System_GetDriverInfo", lib);
    bindFunc(FMOD_System_GetDriverCaps)("FMOD_System_GetDriverCaps", lib);
    bindFunc(FMOD_System_SetDriver)("FMOD_System_SetDriver", lib);
    bindFunc(FMOD_System_GetDriver)("FMOD_System_GetDriver", lib);
    bindFunc(FMOD_System_SetHardwareChannels)("FMOD_System_SetHardwareChannels", lib);
    bindFunc(FMOD_System_SetSoftwareChannels)("FMOD_System_SetSoftwareChannels", lib);
    bindFunc(FMOD_System_GetSoftwareChannels)("FMOD_System_GetSoftwareChannels", lib);
    bindFunc(FMOD_System_SetSoftwareFormat)("FMOD_System_SetSoftwareFormat", lib);
    bindFunc(FMOD_System_GetSoftwareFormat)("FMOD_System_GetSoftwareFormat", lib);
    bindFunc(FMOD_System_SetDSPBufferSize)("FMOD_System_SetDSPBufferSize", lib);
    bindFunc(FMOD_System_GetDSPBufferSize)("FMOD_System_GetDSPBufferSize", lib);
    bindFunc(FMOD_System_SetFileSystem)("FMOD_System_SetFileSystem", lib);
    bindFunc(FMOD_System_AttachFileSystem)("FMOD_System_AttachFileSystem", lib);
    bindFunc(FMOD_System_SetAdvancedSettings)("FMOD_System_SetAdvancedSettings", lib);
    bindFunc(FMOD_System_GetAdvancedSettings)("FMOD_System_GetAdvancedSettings", lib);
    bindFunc(FMOD_System_SetSpeakerMode)("FMOD_System_SetSpeakerMode", lib);
    bindFunc(FMOD_System_GetSpeakerMode)("FMOD_System_GetSpeakerMode", lib);
    bindFunc(FMOD_System_SetCallback)("FMOD_System_SetCallback", lib);

    /*
         Plug-in support
    */

    bindFunc(FMOD_System_SetPluginPath)("FMOD_System_SetPluginPath", lib);
    bindFunc(FMOD_System_LoadPlugin)("FMOD_System_LoadPlugin", lib);
    bindFunc(FMOD_System_UnloadPlugin)("FMOD_System_UnloadPlugin", lib);
    bindFunc(FMOD_System_GetNumPlugins)("FMOD_System_GetNumPlugins", lib);
    bindFunc(FMOD_System_GetPluginHandle)("FMOD_System_GetPluginHandle", lib);
    bindFunc(FMOD_System_GetPluginInfo)("FMOD_System_GetPluginInfo", lib);
    bindFunc(FMOD_System_SetOutputByPlugin)("FMOD_System_SetOutputByPlugin", lib);
    bindFunc(FMOD_System_GetOutputByPlugin)("FMOD_System_GetOutputByPlugin", lib);
    bindFunc(FMOD_System_CreateDSPByPlugin)("FMOD_System_CreateDSPByPlugin", lib);
    bindFunc(FMOD_System_CreateCodec)("FMOD_System_CreateCodec", lib);

    /*
         Init/Close
    */

    bindFunc(FMOD_System_Init)("FMOD_System_Init", lib);
    bindFunc(FMOD_System_Close)("FMOD_System_Close", lib);

    /*
         General post-init system functions
    */

    bindFunc(FMOD_System_Update)("FMOD_System_Update", lib);

    bindFunc(FMOD_System_Set3DSettings)("FMOD_System_Set3DSettings", lib);
    bindFunc(FMOD_System_Get3DSettings)("FMOD_System_Get3DSettings", lib);
    bindFunc(FMOD_System_Set3DNumListeners)("FMOD_System_Set3DNumListeners", lib);
    bindFunc(FMOD_System_Get3DNumListeners)("FMOD_System_Get3DNumListeners", lib);
    bindFunc(FMOD_System_Set3DListenerAttributes)("FMOD_System_Set3DListenerAttributes", lib);
    bindFunc(FMOD_System_Get3DListenerAttributes)("FMOD_System_Get3DListenerAttributes", lib);
    bindFunc(FMOD_System_Set3DRolloffCallback)("FMOD_System_Set3DRolloffCallback", lib);
    bindFunc(FMOD_System_Set3DSpeakerPosition)("FMOD_System_Set3DSpeakerPosition", lib);
    bindFunc(FMOD_System_Get3DSpeakerPosition)("FMOD_System_Get3DSpeakerPosition", lib);

    bindFunc(FMOD_System_SetStreamBufferSize)("FMOD_System_SetStreamBufferSize", lib);
    bindFunc(FMOD_System_GetStreamBufferSize)("FMOD_System_GetStreamBufferSize", lib);

    /*
         System information functions.
    */

    bindFunc(FMOD_System_GetVersion)("FMOD_System_GetVersion", lib);
    bindFunc(FMOD_System_GetOutputHandle)("FMOD_System_GetOutputHandle", lib);
    bindFunc(FMOD_System_GetChannelsPlaying)("FMOD_System_GetChannelsPlaying", lib);
    bindFunc(FMOD_System_GetHardwareChannels)("FMOD_System_GetHardwareChannels", lib);
    bindFunc(FMOD_System_GetCPUUsage)("FMOD_System_GetCPUUsage", lib);
    bindFunc(FMOD_System_GetSoundRAM)("FMOD_System_GetSoundRAM", lib);
    bindFunc(FMOD_System_GetNumCDROMDrives)("FMOD_System_GetNumCDROMDrives", lib);
    bindFunc(FMOD_System_GetCDROMDriveName)("FMOD_System_GetCDROMDriveName", lib);
    bindFunc(FMOD_System_GetSpectrum)("FMOD_System_GetSpectrum", lib);
    bindFunc(FMOD_System_GetWaveData)("FMOD_System_GetWaveData", lib);

    /*
         Sound/DSP/Channel/FX creation and retrieval.
    */

    bindFunc(FMOD_System_CreateSound)("FMOD_System_CreateSound", lib);
    bindFunc(FMOD_System_CreateStream)("FMOD_System_CreateStream", lib);
    bindFunc(FMOD_System_CreateDSP)("FMOD_System_CreateDSP", lib);
    bindFunc(FMOD_System_CreateDSPByType)("FMOD_System_CreateDSPByType", lib);
    bindFunc(FMOD_System_CreateChannelGroup)("FMOD_System_CreateChannelGroup", lib);
    bindFunc(FMOD_System_CreateSoundGroup)("FMOD_System_CreateSoundGroup", lib);
    bindFunc(FMOD_System_CreateReverb)("FMOD_System_CreateReverb", lib);

    bindFunc(FMOD_System_PlaySound)("FMOD_System_PlaySound", lib);
    bindFunc(FMOD_System_PlayDSP)("FMOD_System_PlayDSP", lib);
    bindFunc(FMOD_System_GetChannel)("FMOD_System_GetChannel", lib);
    bindFunc(FMOD_System_GetMasterChannelGroup)("FMOD_System_GetMasterChannelGroup", lib);
    bindFunc(FMOD_System_GetMasterSoundGroup)("FMOD_System_GetMasterSoundGroup", lib);

    /*
         Reverb API
    */

    bindFunc(FMOD_System_SetReverbProperties)("FMOD_System_SetReverbProperties", lib);
    bindFunc(FMOD_System_GetReverbProperties)("FMOD_System_GetReverbProperties", lib);
    bindFunc(FMOD_System_SetReverbAmbientProperties)("FMOD_System_SetReverbAmbientProperties", lib);
    bindFunc(FMOD_System_GetReverbAmbientProperties)("FMOD_System_GetReverbAmbientProperties", lib);

    /*
         System level DSP access.
    */

    bindFunc(FMOD_System_GetDSPHead)("FMOD_System_GetDSPHead", lib);
    bindFunc(FMOD_System_AddDSP)("FMOD_System_AddDSP", lib);
    bindFunc(FMOD_System_LockDSP)("FMOD_System_LockDSP", lib);
    bindFunc(FMOD_System_UnlockDSP)("FMOD_System_UnlockDSP", lib);
    bindFunc(FMOD_System_GetDSPClock)("FMOD_System_GetDSPClock", lib);

    /*
         Recording API.
    */

    bindFunc(FMOD_System_GetRecordNumDrivers)("FMOD_System_GetRecordNumDrivers", lib);
    bindFunc(FMOD_System_GetRecordDriverInfo)("FMOD_System_GetRecordDriverInfo", lib);
    bindFunc(FMOD_System_GetRecordDriverCaps)("FMOD_System_GetRecordDriverCaps", lib);
    bindFunc(FMOD_System_GetRecordPosition)("FMOD_System_GetRecordPosition", lib);

    bindFunc(FMOD_System_RecordStart)("FMOD_System_RecordStart", lib);
    bindFunc(FMOD_System_RecordStop)("FMOD_System_RecordStop", lib);
    bindFunc(FMOD_System_IsRecording)("FMOD_System_IsRecording", lib);

    /*
         Geometry API.
    */

    bindFunc(FMOD_System_CreateGeometry)("FMOD_System_CreateGeometry", lib);
    bindFunc(FMOD_System_SetGeometrySettings)("FMOD_System_SetGeometrySettings", lib);
    bindFunc(FMOD_System_GetGeometrySettings)("FMOD_System_GetGeometrySettings", lib);
    bindFunc(FMOD_System_LoadGeometry)("FMOD_System_LoadGeometry", lib);
    bindFunc(FMOD_System_GetGeometryOcclusion)("FMOD_System_GetGeometryOcclusion", lib);

    /*
         Network functions.
    */

    bindFunc(FMOD_System_SetNetworkProxy)("FMOD_System_SetNetworkProxy", lib);
    bindFunc(FMOD_System_GetNetworkProxy)("FMOD_System_GetNetworkProxy", lib);
    bindFunc(FMOD_System_SetNetworkTimeout)("FMOD_System_SetNetworkTimeout", lib);
    bindFunc(FMOD_System_GetNetworkTimeout)("FMOD_System_GetNetworkTimeout", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_System_SetUserData)("FMOD_System_SetUserData", lib);
    bindFunc(FMOD_System_GetUserData)("FMOD_System_GetUserData", lib);

    bindFunc(FMOD_System_GetMemoryInfo)("FMOD_System_GetMemoryInfo", lib);

    /*
        'Sound' API
    */

    bindFunc(FMOD_Sound_Release)("FMOD_Sound_Release", lib);
    bindFunc(FMOD_Sound_GetSystemObject)("FMOD_Sound_GetSystemObject", lib);

    /*
         Standard sound manipulation functions.
    */

    bindFunc(FMOD_Sound_Lock)("FMOD_Sound_Lock", lib);
    bindFunc(FMOD_Sound_Unlock)("FMOD_Sound_Unlock", lib);
    bindFunc(FMOD_Sound_SetDefaults)("FMOD_Sound_SetDefaults", lib);
    bindFunc(FMOD_Sound_GetDefaults)("FMOD_Sound_GetDefaults", lib);
    bindFunc(FMOD_Sound_SetVariations)("FMOD_Sound_SetVariations", lib);
    bindFunc(FMOD_Sound_GetVariations)("FMOD_Sound_GetVariations", lib);
    bindFunc(FMOD_Sound_Set3DMinMaxDistance)("FMOD_Sound_Set3DMinMaxDistance", lib);
    bindFunc(FMOD_Sound_Get3DMinMaxDistance)("FMOD_Sound_Get3DMinMaxDistance", lib);
    bindFunc(FMOD_Sound_Set3DConeSettings)("FMOD_Sound_Set3DConeSettings", lib);
    bindFunc(FMOD_Sound_Get3DConeSettings)("FMOD_Sound_Get3DConeSettings", lib);
    bindFunc(FMOD_Sound_Set3DCustomRolloff)("FMOD_Sound_Set3DCustomRolloff", lib);
    bindFunc(FMOD_Sound_Get3DCustomRolloff)("FMOD_Sound_Get3DCustomRolloff", lib);
    bindFunc(FMOD_Sound_SetSubSound)("FMOD_Sound_SetSubSound", lib);
    bindFunc(FMOD_Sound_GetSubSound)("FMOD_Sound_GetSubSound", lib);
    bindFunc(FMOD_Sound_SetSubSoundSentence)("FMOD_Sound_SetSubSoundSentence", lib);
    bindFunc(FMOD_Sound_GetName)("FMOD_Sound_GetName", lib);
    bindFunc(FMOD_Sound_GetLength)("FMOD_Sound_GetLength", lib);
    bindFunc(FMOD_Sound_GetFormat)("FMOD_Sound_GetFormat", lib);
    bindFunc(FMOD_Sound_GetNumSubSounds)("FMOD_Sound_GetNumSubSounds", lib);
    bindFunc(FMOD_Sound_GetNumTags)("FMOD_Sound_GetNumTags", lib);
    bindFunc(FMOD_Sound_GetTag)("FMOD_Sound_GetTag", lib);
    bindFunc(FMOD_Sound_GetOpenState)("FMOD_Sound_GetOpenState", lib);
    bindFunc(FMOD_Sound_ReadData)("FMOD_Sound_ReadData", lib);
    bindFunc(FMOD_Sound_SeekData)("FMOD_Sound_SeekData", lib);

    bindFunc(FMOD_Sound_SetSoundGroup)("FMOD_Sound_SetSoundGroup", lib);
    bindFunc(FMOD_Sound_GetSoundGroup)("FMOD_Sound_GetSoundGroup", lib);

    /*
         Synchronization point API.  These points can come from markers embedded in wav files, and can also generate channel callbacks.
    */

    bindFunc(FMOD_Sound_GetNumSyncPoints)("FMOD_Sound_GetNumSyncPoints", lib);
    bindFunc(FMOD_Sound_GetSyncPoint)("FMOD_Sound_GetSyncPoint", lib);
    bindFunc(FMOD_Sound_GetSyncPointInfo)("FMOD_Sound_GetSyncPointInfo", lib);
    bindFunc(FMOD_Sound_AddSyncPoint)("FMOD_Sound_AddSyncPoint", lib);
    bindFunc(FMOD_Sound_DeleteSyncPoint)("FMOD_Sound_DeleteSyncPoint", lib);

    /*
         Functions also in Channel class but here they are the 'default' to save having to change it in Channel all the time.
    */

    bindFunc(FMOD_Sound_SetMode)("FMOD_Sound_SetMode", lib);
    bindFunc(FMOD_Sound_GetMode)("FMOD_Sound_GetMode", lib);
    bindFunc(FMOD_Sound_SetLoopCount)("FMOD_Sound_SetLoopCount", lib);
    bindFunc(FMOD_Sound_GetLoopCount)("FMOD_Sound_GetLoopCount", lib);
    bindFunc(FMOD_Sound_SetLoopPoints)("FMOD_Sound_SetLoopPoints", lib);
    bindFunc(FMOD_Sound_GetLoopPoints)("FMOD_Sound_GetLoopPoints", lib);

    /*
         For MOD/S3M/XM/IT/MID sequenced formats only.
    */

    bindFunc(FMOD_Sound_GetMusicNumChannels)("FMOD_Sound_GetMusicNumChannels", lib);
    bindFunc(FMOD_Sound_SetMusicChannelVolume)("FMOD_Sound_SetMusicChannelVolume", lib);
    bindFunc(FMOD_Sound_GetMusicChannelVolume)("FMOD_Sound_GetMusicChannelVolume", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_Sound_SetUserData)("FMOD_Sound_SetUserData", lib);
    bindFunc(FMOD_Sound_GetUserData)("FMOD_Sound_GetUserData", lib);

    bindFunc(FMOD_Sound_GetMemoryInfo)("FMOD_Sound_GetMemoryInfo", lib);

    /*
        'Channel' API
    */

    bindFunc(FMOD_Channel_GetSystemObject)("FMOD_Channel_GetSystemObject", lib);

    bindFunc(FMOD_Channel_Stop)("FMOD_Channel_Stop", lib);
    bindFunc(FMOD_Channel_SetPaused)("FMOD_Channel_SetPaused", lib);
    bindFunc(FMOD_Channel_GetPaused)("FMOD_Channel_GetPaused", lib);
    bindFunc(FMOD_Channel_SetVolume)("FMOD_Channel_SetVolume", lib);
    bindFunc(FMOD_Channel_GetVolume)("FMOD_Channel_GetVolume", lib);
    bindFunc(FMOD_Channel_SetFrequency)("FMOD_Channel_SetFrequency", lib);
    bindFunc(FMOD_Channel_GetFrequency)("FMOD_Channel_GetFrequency", lib);
    bindFunc(FMOD_Channel_SetPan)("FMOD_Channel_SetPan", lib);
    bindFunc(FMOD_Channel_GetPan)("FMOD_Channel_GetPan", lib);
    bindFunc(FMOD_Channel_SetDelay)("FMOD_Channel_SetDelay", lib);
    bindFunc(FMOD_Channel_GetDelay)("FMOD_Channel_GetDelay", lib);
    bindFunc(FMOD_Channel_SetSpeakerMix)("FMOD_Channel_SetSpeakerMix", lib);
    bindFunc(FMOD_Channel_GetSpeakerMix)("FMOD_Channel_GetSpeakerMix", lib);
    bindFunc(FMOD_Channel_SetSpeakerLevels)("FMOD_Channel_SetSpeakerLevels", lib);
    bindFunc(FMOD_Channel_GetSpeakerLevels)("FMOD_Channel_GetSpeakerLevels", lib);
    bindFunc(FMOD_Channel_SetInputChannelMix)("FMOD_Channel_SetInputChannelMix", lib);
    bindFunc(FMOD_Channel_GetInputChannelMix)("FMOD_Channel_GetInputChannelMix", lib);
    bindFunc(FMOD_Channel_SetMute)("FMOD_Channel_SetMute", lib);
    bindFunc(FMOD_Channel_GetMute)("FMOD_Channel_GetMute", lib);
    bindFunc(FMOD_Channel_SetPriority)("FMOD_Channel_SetPriority", lib);
    bindFunc(FMOD_Channel_GetPriority)("FMOD_Channel_GetPriority", lib);
    bindFunc(FMOD_Channel_SetPosition)("FMOD_Channel_SetPosition", lib);
    bindFunc(FMOD_Channel_GetPosition)("FMOD_Channel_GetPosition", lib);
    bindFunc(FMOD_Channel_SetReverbProperties)("FMOD_Channel_SetReverbProperties", lib);
    bindFunc(FMOD_Channel_GetReverbProperties)("FMOD_Channel_GetReverbProperties", lib);
    bindFunc(FMOD_Channel_SetLowPassGain)("FMOD_Channel_SetLowPassGain", lib);
    bindFunc(FMOD_Channel_GetLowPassGain)("FMOD_Channel_GetLowPassGain", lib);

    bindFunc(FMOD_Channel_SetChannelGroup)("FMOD_Channel_SetChannelGroup", lib);
    bindFunc(FMOD_Channel_GetChannelGroup)("FMOD_Channel_GetChannelGroup", lib);
    bindFunc(FMOD_Channel_SetCallback)("FMOD_Channel_SetCallback", lib);

    /*
         3D functionality.
    */

    bindFunc(FMOD_Channel_Set3DAttributes)("FMOD_Channel_Set3DAttributes", lib);
    bindFunc(FMOD_Channel_Get3DAttributes)("FMOD_Channel_Get3DAttributes", lib);
    bindFunc(FMOD_Channel_Set3DMinMaxDistance)("FMOD_Channel_Set3DMinMaxDistance", lib);
    bindFunc(FMOD_Channel_Get3DMinMaxDistance)("FMOD_Channel_Get3DMinMaxDistance", lib);
    bindFunc(FMOD_Channel_Set3DConeSettings)("FMOD_Channel_Set3DConeSettings", lib);
    bindFunc(FMOD_Channel_Get3DConeSettings)("FMOD_Channel_Get3DConeSettings", lib);
    bindFunc(FMOD_Channel_Set3DConeOrientation)("FMOD_Channel_Set3DConeOrientation", lib);
    bindFunc(FMOD_Channel_Get3DConeOrientation)("FMOD_Channel_Get3DConeOrientation", lib);
    bindFunc(FMOD_Channel_Set3DCustomRolloff)("FMOD_Channel_Set3DCustomRolloff", lib);
    bindFunc(FMOD_Channel_Get3DCustomRolloff)("FMOD_Channel_Get3DCustomRolloff", lib);
    bindFunc(FMOD_Channel_Set3DOcclusion)("FMOD_Channel_Set3DOcclusion", lib);
    bindFunc(FMOD_Channel_Get3DOcclusion)("FMOD_Channel_Get3DOcclusion", lib);
    bindFunc(FMOD_Channel_Set3DSpread)("FMOD_Channel_Set3DSpread", lib);
    bindFunc(FMOD_Channel_Get3DSpread)("FMOD_Channel_Get3DSpread", lib);
    bindFunc(FMOD_Channel_Set3DPanLevel)("FMOD_Channel_Set3DPanLevel", lib);
    bindFunc(FMOD_Channel_Get3DPanLevel)("FMOD_Channel_Get3DPanLevel", lib);
    bindFunc(FMOD_Channel_Set3DDopplerLevel)("FMOD_Channel_Set3DDopplerLevel", lib);
    bindFunc(FMOD_Channel_Get3DDopplerLevel)("FMOD_Channel_Get3DDopplerLevel", lib);

    /*
         DSP functionality only for channels playing sounds created with FMOD_SOFTWARE.
    */

    bindFunc(FMOD_Channel_GetDSPHead)("FMOD_Channel_GetDSPHead", lib);
    bindFunc(FMOD_Channel_AddDSP)("FMOD_Channel_AddDSP", lib);

    /*
         Information only functions.
    */

    bindFunc(FMOD_Channel_IsPlaying)("FMOD_Channel_IsPlaying", lib);
    bindFunc(FMOD_Channel_IsVirtual)("FMOD_Channel_IsVirtual", lib);
    bindFunc(FMOD_Channel_GetAudibility)("FMOD_Channel_GetAudibility", lib);
    bindFunc(FMOD_Channel_GetCurrentSound)("FMOD_Channel_GetCurrentSound", lib);
    bindFunc(FMOD_Channel_GetSpectrum)("FMOD_Channel_GetSpectrum", lib);
    bindFunc(FMOD_Channel_GetWaveData)("FMOD_Channel_GetWaveData", lib);
    bindFunc(FMOD_Channel_GetIndex)("FMOD_Channel_GetIndex", lib);

    /*
         Functions also found in Sound class but here they can be set per channel.
    */

    bindFunc(FMOD_Channel_SetMode)("FMOD_Channel_SetMode", lib);
    bindFunc(FMOD_Channel_GetMode)("FMOD_Channel_GetMode", lib);
    bindFunc(FMOD_Channel_SetLoopCount)("FMOD_Channel_SetLoopCount", lib);
    bindFunc(FMOD_Channel_GetLoopCount)("FMOD_Channel_GetLoopCount", lib);
    bindFunc(FMOD_Channel_SetLoopPoints)("FMOD_Channel_SetLoopPoints", lib);
    bindFunc(FMOD_Channel_GetLoopPoints)("FMOD_Channel_GetLoopPoints", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_Channel_SetUserData)("FMOD_Channel_SetUserData", lib);
    bindFunc(FMOD_Channel_GetUserData)("FMOD_Channel_GetUserData", lib);

    bindFunc(FMOD_Channel_GetMemoryInfo)("FMOD_Channel_GetMemoryInfo", lib);

    /*
        'ChannelGroup' API
    */

    bindFunc(FMOD_ChannelGroup_Release)("FMOD_ChannelGroup_Release", lib);
    bindFunc(FMOD_ChannelGroup_GetSystemObject)("FMOD_ChannelGroup_GetSystemObject", lib);

    /*
         Channelgroup scale values.  (changes attributes relative to the channels, doesn't overwrite them)
    */

    bindFunc(FMOD_ChannelGroup_SetVolume)("FMOD_ChannelGroup_SetVolume", lib);
    bindFunc(FMOD_ChannelGroup_GetVolume)("FMOD_ChannelGroup_GetVolume", lib);
    bindFunc(FMOD_ChannelGroup_SetPitch)("FMOD_ChannelGroup_SetPitch", lib);
    bindFunc(FMOD_ChannelGroup_GetPitch)("FMOD_ChannelGroup_GetPitch", lib);
    bindFunc(FMOD_ChannelGroup_Set3DOcclusion)("FMOD_ChannelGroup_Set3DOcclusion", lib);
    bindFunc(FMOD_ChannelGroup_Get3DOcclusion)("FMOD_ChannelGroup_Get3DOcclusion", lib);
    bindFunc(FMOD_ChannelGroup_SetPaused)("FMOD_ChannelGroup_SetPaused", lib);
    bindFunc(FMOD_ChannelGroup_GetPaused)("FMOD_ChannelGroup_GetPaused", lib);
    bindFunc(FMOD_ChannelGroup_SetMute)("FMOD_ChannelGroup_SetMute", lib);
    bindFunc(FMOD_ChannelGroup_GetMute)("FMOD_ChannelGroup_GetMute", lib);

    /*
         Channelgroup override values.  (recursively overwrites whatever settings the channels had)
    */

    bindFunc(FMOD_ChannelGroup_Stop)("FMOD_ChannelGroup_Stop", lib);
    bindFunc(FMOD_ChannelGroup_OverrideVolume)("FMOD_ChannelGroup_OverrideVolume", lib);
    bindFunc(FMOD_ChannelGroup_OverrideFrequency)("FMOD_ChannelGroup_OverrideFrequency", lib);
    bindFunc(FMOD_ChannelGroup_OverridePan)("FMOD_ChannelGroup_OverridePan", lib);
    bindFunc(FMOD_ChannelGroup_OverrideReverbProperties)("FMOD_ChannelGroup_OverrideReverbProperties", lib);
    bindFunc(FMOD_ChannelGroup_Override3DAttributes)("FMOD_ChannelGroup_Override3DAttributes", lib);
    bindFunc(FMOD_ChannelGroup_OverrideSpeakerMix)("FMOD_ChannelGroup_OverrideSpeakerMix", lib);

    /*
         Nested channel groups.
    */

    bindFunc(FMOD_ChannelGroup_AddGroup)("FMOD_ChannelGroup_AddGroup", lib);
    bindFunc(FMOD_ChannelGroup_GetNumGroups)("FMOD_ChannelGroup_GetNumGroups", lib);
    bindFunc(FMOD_ChannelGroup_GetGroup)("FMOD_ChannelGroup_GetGroup", lib);
    bindFunc(FMOD_ChannelGroup_GetParentGroup)("FMOD_ChannelGroup_GetParentGroup", lib);

    /*
         DSP functionality only for channel groups playing sounds created with FMOD_SOFTWARE.
    */

    bindFunc(FMOD_ChannelGroup_GetDSPHead)("FMOD_ChannelGroup_GetDSPHead", lib);
    bindFunc(FMOD_ChannelGroup_AddDSP)("FMOD_ChannelGroup_AddDSP", lib);

    /*
         Information only functions.
    */

    bindFunc(FMOD_ChannelGroup_GetName)("FMOD_ChannelGroup_GetName", lib);
    bindFunc(FMOD_ChannelGroup_GetNumChannels)("FMOD_ChannelGroup_GetNumChannels", lib);
    bindFunc(FMOD_ChannelGroup_GetChannel)("FMOD_ChannelGroup_GetChannel", lib);
    bindFunc(FMOD_ChannelGroup_GetSpectrum)("FMOD_ChannelGroup_GetSpectrum", lib);
    bindFunc(FMOD_ChannelGroup_GetWaveData)("FMOD_ChannelGroup_GetWaveData", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_ChannelGroup_SetUserData)("FMOD_ChannelGroup_SetUserData", lib);
    bindFunc(FMOD_ChannelGroup_GetUserData)("FMOD_ChannelGroup_GetUserData", lib);

    bindFunc(FMOD_ChannelGroup_GetMemoryInfo)("FMOD_ChannelGroup_GetMemoryInfo", lib);

    /*
        'SoundGroup' API
    */

    bindFunc(FMOD_SoundGroup_Release)("FMOD_SoundGroup_Release", lib);
    bindFunc(FMOD_SoundGroup_GetSystemObject)("FMOD_SoundGroup_GetSystemObject", lib);

    /*
         SoundGroup control functions.
    */

    bindFunc(FMOD_SoundGroup_SetMaxAudible)("FMOD_SoundGroup_SetMaxAudible", lib);
    bindFunc(FMOD_SoundGroup_GetMaxAudible)("FMOD_SoundGroup_GetMaxAudible", lib);
    bindFunc(FMOD_SoundGroup_SetMaxAudibleBehavior)("FMOD_SoundGroup_SetMaxAudibleBehavior", lib);
    bindFunc(FMOD_SoundGroup_GetMaxAudibleBehavior)("FMOD_SoundGroup_GetMaxAudibleBehavior", lib);
    bindFunc(FMOD_SoundGroup_SetMuteFadeSpeed)("FMOD_SoundGroup_SetMuteFadeSpeed", lib);
    bindFunc(FMOD_SoundGroup_GetMuteFadeSpeed)("FMOD_SoundGroup_GetMuteFadeSpeed", lib);
    bindFunc(FMOD_SoundGroup_SetVolume)("FMOD_SoundGroup_SetVolume", lib);
    bindFunc(FMOD_SoundGroup_GetVolume)("FMOD_SoundGroup_GetVolume", lib);
    bindFunc(FMOD_SoundGroup_Stop)("FMOD_SoundGroup_Stop", lib);

    /*
         Information only functions.
    */

    bindFunc(FMOD_SoundGroup_GetName)("FMOD_SoundGroup_GetName", lib);
    bindFunc(FMOD_SoundGroup_GetNumSounds)("FMOD_SoundGroup_GetNumSounds", lib);
    bindFunc(FMOD_SoundGroup_GetSound)("FMOD_SoundGroup_GetSound", lib);
    bindFunc(FMOD_SoundGroup_GetNumPlaying)("FMOD_SoundGroup_GetNumPlaying", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_SoundGroup_SetUserData)("FMOD_SoundGroup_SetUserData", lib);
    bindFunc(FMOD_SoundGroup_GetUserData)("FMOD_SoundGroup_GetUserData", lib);

    bindFunc(FMOD_SoundGroup_GetMemoryInfo)("FMOD_SoundGroup_GetMemoryInfo", lib);

    /*
        'DSP' API
    */

    bindFunc(FMOD_DSP_Release)("FMOD_DSP_Release", lib);
    bindFunc(FMOD_DSP_GetSystemObject)("FMOD_DSP_GetSystemObject", lib);

    /*
         Connection / disconnection / input and output enumeration.
    */

    bindFunc(FMOD_DSP_AddInput)("FMOD_DSP_AddInput", lib);
    bindFunc(FMOD_DSP_DisconnectFrom)("FMOD_DSP_DisconnectFrom", lib);
    bindFunc(FMOD_DSP_DisconnectAll)("FMOD_DSP_DisconnectAll", lib);
    bindFunc(FMOD_DSP_Remove)("FMOD_DSP_Remove", lib);
    bindFunc(FMOD_DSP_GetNumInputs)("FMOD_DSP_GetNumInputs", lib);
    bindFunc(FMOD_DSP_GetNumOutputs)("FMOD_DSP_GetNumOutputs", lib);
    bindFunc(FMOD_DSP_GetInput)("FMOD_DSP_GetInput", lib);
    bindFunc(FMOD_DSP_GetOutput)("FMOD_DSP_GetOutput", lib);

    /*
         DSP unit control.
    */

    bindFunc(FMOD_DSP_SetActive)("FMOD_DSP_SetActive", lib);
    bindFunc(FMOD_DSP_GetActive)("FMOD_DSP_GetActive", lib);
    bindFunc(FMOD_DSP_SetBypass)("FMOD_DSP_SetBypass", lib);
    bindFunc(FMOD_DSP_GetBypass)("FMOD_DSP_GetBypass", lib);
    bindFunc(FMOD_DSP_SetSpeakerActive)("FMOD_DSP_SetSpeakerActive", lib);
    bindFunc(FMOD_DSP_GetSpeakerActive)("FMOD_DSP_GetSpeakerActive", lib);
    bindFunc(FMOD_DSP_Reset)("FMOD_DSP_Reset", lib);

    /*
         DSP parameter control.
    */

    bindFunc(FMOD_DSP_SetParameter)("FMOD_DSP_SetParameter", lib);
    bindFunc(FMOD_DSP_GetParameter)("FMOD_DSP_GetParameter", lib);
    bindFunc(FMOD_DSP_GetNumParameters)("FMOD_DSP_GetNumParameters", lib);
    bindFunc(FMOD_DSP_GetParameterInfo)("FMOD_DSP_GetParameterInfo", lib);
    bindFunc(FMOD_DSP_ShowConfigDialog)("FMOD_DSP_ShowConfigDialog", lib);

    /*
         DSP attributes.
    */

    bindFunc(FMOD_DSP_GetInfo)("FMOD_DSP_GetInfo", lib);
    bindFunc(FMOD_DSP_GetType)("FMOD_DSP_GetType", lib);
    bindFunc(FMOD_DSP_SetDefaults)("FMOD_DSP_SetDefaults", lib);
    bindFunc(FMOD_DSP_GetDefaults)("FMOD_DSP_GetDefaults", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_DSP_SetUserData)("FMOD_DSP_SetUserData", lib);
    bindFunc(FMOD_DSP_GetUserData)("FMOD_DSP_GetUserData", lib);

    bindFunc(FMOD_DSP_GetMemoryInfo)("FMOD_DSP_GetMemoryInfo", lib);

    /*
        'DSPConnection' API
    */

    bindFunc(FMOD_DSPConnection_GetInput)("FMOD_DSPConnection_GetInput", lib);
    bindFunc(FMOD_DSPConnection_GetOutput)("FMOD_DSPConnection_GetOutput", lib);
    bindFunc(FMOD_DSPConnection_SetMix)("FMOD_DSPConnection_SetMix", lib);
    bindFunc(FMOD_DSPConnection_GetMix)("FMOD_DSPConnection_GetMix", lib);
    bindFunc(FMOD_DSPConnection_SetLevels)("FMOD_DSPConnection_SetLevels", lib);
    bindFunc(FMOD_DSPConnection_GetLevels)("FMOD_DSPConnection_GetLevels", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_DSPConnection_SetUserData)("FMOD_DSPConnection_SetUserData", lib);
    bindFunc(FMOD_DSPConnection_GetUserData)("FMOD_DSPConnection_GetUserData", lib);

    bindFunc(FMOD_DSPConnection_GetMemoryInfo)("FMOD_DSPConnection_GetMemoryInfo", lib);

    /*
        'Geometry' API
    */

    bindFunc(FMOD_Geometry_Release)("FMOD_Geometry_Release", lib);

    /*
         Polygon manipulation.
    */

    bindFunc(FMOD_Geometry_AddPolygon)("FMOD_Geometry_AddPolygon", lib);
    bindFunc(FMOD_Geometry_GetNumPolygons)("FMOD_Geometry_GetNumPolygons", lib);
    bindFunc(FMOD_Geometry_GetMaxPolygons)("FMOD_Geometry_GetMaxPolygons", lib);
    bindFunc(FMOD_Geometry_GetPolygonNumVertices)("FMOD_Geometry_GetPolygonNumVertices", lib);
    bindFunc(FMOD_Geometry_SetPolygonVertex)("FMOD_Geometry_SetPolygonVertex", lib);
    bindFunc(FMOD_Geometry_GetPolygonVertex)("FMOD_Geometry_GetPolygonVertex", lib);
    bindFunc(FMOD_Geometry_SetPolygonAttributes)("FMOD_Geometry_SetPolygonAttributes", lib);
    bindFunc(FMOD_Geometry_GetPolygonAttributes)("FMOD_Geometry_GetPolygonAttributes", lib);

    /*
         Object manipulation.
    */

    bindFunc(FMOD_Geometry_SetActive)("FMOD_Geometry_SetActive", lib);
    bindFunc(FMOD_Geometry_GetActive)("FMOD_Geometry_GetActive", lib);
    bindFunc(FMOD_Geometry_SetRotation)("FMOD_Geometry_SetRotation", lib);
    bindFunc(FMOD_Geometry_GetRotation)("FMOD_Geometry_GetRotation", lib);
    bindFunc(FMOD_Geometry_SetPosition)("FMOD_Geometry_SetPosition", lib);
    bindFunc(FMOD_Geometry_GetPosition)("FMOD_Geometry_GetPosition", lib);
    bindFunc(FMOD_Geometry_SetScale)("FMOD_Geometry_SetScale", lib);
    bindFunc(FMOD_Geometry_GetScale)("FMOD_Geometry_GetScale", lib);
    bindFunc(FMOD_Geometry_Save)("FMOD_Geometry_Save", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_Geometry_SetUserData)("FMOD_Geometry_SetUserData", lib);
    bindFunc(FMOD_Geometry_GetUserData)("FMOD_Geometry_GetUserData", lib);

    bindFunc(FMOD_Geometry_GetMemoryInfo)("FMOD_Geometry_GetMemoryInfo", lib);

    /*
        'Reverb' API
    */

    bindFunc(FMOD_Reverb_Release)("FMOD_Reverb_Release", lib);

    /*
         Reverb manipulation.
    */

    bindFunc(FMOD_Reverb_Set3DAttributes)("FMOD_Reverb_Set3DAttributes", lib);
    bindFunc(FMOD_Reverb_Get3DAttributes)("FMOD_Reverb_Get3DAttributes", lib);
    bindFunc(FMOD_Reverb_SetProperties)("FMOD_Reverb_SetProperties", lib);
    bindFunc(FMOD_Reverb_GetProperties)("FMOD_Reverb_GetProperties", lib);
    bindFunc(FMOD_Reverb_SetActive)("FMOD_Reverb_SetActive", lib);
    bindFunc(FMOD_Reverb_GetActive)("FMOD_Reverb_GetActive", lib);

    /*
         Userdata set/get.
    */

    bindFunc(FMOD_Reverb_SetUserData)("FMOD_Reverb_SetUserData", lib);
    bindFunc(FMOD_Reverb_GetUserData)("FMOD_Reverb_GetUserData", lib);

    bindFunc(FMOD_Reverb_GetMemoryInfo)("FMOD_Reverb_GetMemoryInfo", lib);
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
