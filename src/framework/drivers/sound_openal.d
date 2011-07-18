module framework.drivers.sound_openal;

import derelict.openal.al;
import derelict.sdl.sdl;
import derelict.sdl.sound;
import derelict.util.exception;
import framework.driver_base;
import framework.filesystem;
import framework.sound;
import framework.sdl.sdl;
import framework.sdl.rwops;
import utils.stream;
import utils.array;
import utils.misc;
import utils.time;
import utils.configfile;
import utils.path;
import utils.log;

private void checkALError(string msg) {
    int code = alGetError();
    if (code != AL_NO_ERROR) {
        throw new Exception("call of "~msg~" failed: "~fromStringz(
            alGetString(code)));
    }
}

private ALSoundDriver gBase;

private LogStruct!("openal") gLog;

class ALChannel : DriverChannel {
    ALuint source;
    ALSound mSound;
    private float mPriority = 0;

    this() {
        owner = gBase;
        alGenSources(1, &source);
        checkALError("alGenSources");
    }

    void setInfo(ref SoundSourceInfo info) {
        //listener orientation is (0, 0, -1), so this should position the source
        //in front of the listener with a 90° FOV, meaning x values close
        //to -1 / 1 will sound "off-screen"
        //y is source height, positive meaning "up"
        alSource3f(source,AL_POSITION, info.position.x, info.position.y, -1.0f);
    }

    void play(DriverSound s, Time startAt) {
        mSound = castStrict!(ALSound)(s);
        assert(!!mSound);
        assert(!!reserved_for);
        alSourceStop(source);

        mSound.initPlay(source, startAt);
        alSourcePlay(source);
        //this fails if sample has length 0
        //--assert (oalState() == AL_PLAYING);
    }

    void stop(bool unreserve) {
        if (state != PlaybackState.stopped)
            alSourceStop(source);
        if (mSound) {
            mSound.finishPlay();
        }
        mSound = null;
        //clear buffers
        alSourcei(source, AL_BUFFER, AL_NONE);
        if (unreserve) {
            reserved_for = null;
            alSourcei(source, AL_LOOPING, AL_FALSE);
        }
    }

    void paused(bool p) {
        if (p) {
            alSourcePause(source);
        } else if (oalState() == AL_PAUSED) {
            alSourcePlay(source);
        }
    }

    void looping(bool loop) {
        if (mSound) {
            //xxx AL_LOOPING does not work with streaming; currently, playback
            //    will stop and be immediately restarted by code in
            //    framework.sound.Source (=hack)
            if (mSound.canLoop)
                alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);
        }
    }

    void priority(float prio) {
        mPriority = prio;
    }
    float priority() {
        return mPriority;
    }

    void setVolume(float value) {
        alSourcef(source, AL_GAIN, value);
    }

    private ALint oalState() {
        ALint s;
        alGetSourcei(source, AL_SOURCE_STATE, &s);
        checkALError("alGetSourcei");
        return s;
    }

    PlaybackState state() {
        switch (oalState()) {
            case AL_PLAYING:
                return PlaybackState.playing;
            case AL_PAUSED:
                return PlaybackState.paused;
            default:
                return PlaybackState.stopped;
        }
    }

    Time position() {
        ALint st = oalState();
        if (state != PlaybackState.stopped) {
            ALfloat pos;
            alGetSourcef(source, AL_SEC_OFFSET, &pos);
            Time ret = timeSecs(pos);
            if (mSound)
                ret += mSound.streamPos;
            return ret;
        } else {
            return Time.Null;
        }
    }

    void check() {
        if (state == PlaybackState.stopped) {
            reserved_for = null;
        }
    }

    void checkWithPrio(float prio) {
        //allow stealing if this priority is lower than requested priority
        if (state == PlaybackState.stopped || mPriority < prio) {
            reserved_for = null;
        }
    }

    void tick() {
        auto curSt = state();
        bool underrunResume;
        //buffer underrun protection: if playback stopped, buf we still have
        //a streamed sound assigned that has not run to EOF, this should be (?)
        //an underrun condition
        if (curSt == PlaybackState.stopped && mSound && mSound.streamed &&
            !mSound.streamEOF)
        {
            //so force a buffer refill...
            underrunResume = true;
        }
        if ((mSound && curSt == PlaybackState.playing) || underrunResume)
            mSound.update();
        if (underrunResume) {
            //...and resume playback
            alSourcePlay(source);
        } else if (mSound && curSt == PlaybackState.stopped) {
            //playback has finished
            stop(true);
        }
    }

    void close() {
        stop(true);
        alDeleteSources(1, &source);
    }
}

class ALSound : DriverSound {
    private {
        ALSoundDriver mDriver;
        Time mLength;
        ALuint[2] mALBuffer;
        Stream mStream;
        Sound_Sample* mSample;
        ALuint mCurrentSource = uint.max;  //for streaming; can only play once
        bool streamEOF;
        uint mStreamedBytes;

        const cReadSampleBuffer = 1024*1024;
        const cStreamBuffer = 4096*8;
    }

    this(ALSoundDriver drv, Sample sample) {
        DriverSoundData data = sample.data;
        mDriver = drv;

        //open the stream and create a sample
        mStream = gFS.open(data.filename);
        SDL_RWops* ops = rwopsFromStream(mStream);
        //bufs is the buffer size, meaning DecodeAll will process bufs bytes
        //  at once and then grow the output buffer by that amount
        uint bufs = data.streamed ? cStreamBuffer : cReadSampleBuffer;
        mSample = Sound_NewSample(ops,
            toStringz(VFSPath(data.filename).extNoDot()), null, bufs);
        if (!mSample) {
            throwError("SDL_sound failed to load '{}'", data.filename);
        }

        //recent versions of SDL_sound support fast duration calculation
        if (Sound_GetDuration) {
            //may return -1 if not possible
            int dur = Sound_GetDuration(mSample);
            if (dur > 0)
                mLength = timeMsecs(dur);
        }

        if (data.streamed) {
            //just prepare buffers, data will be streamed in on playback
            alGenBuffers(2, mALBuffer.ptr);
            checkALError("alGenBuffers");
        } else {
            //decode everything into memory (no streaming for now)
            uint bufSize = Sound_DecodeAll(mSample);

            Sound_AudioInfo fmt = mSample.actual;

            //copy sound data to openal buffer
            alGenBuffers(1, &mALBuffer[0]);
            checkALError("alGenBuffers");
            alBufferData(mALBuffer[0],
                convertSDLFormat(fmt.channels, fmt.format), mSample.buffer,
                bufSize, fmt.rate);
            checkALError("alBufferData");

            //close original sample
            Sound_FreeSample(mSample);
            mStream.close();
            mStream = null;
            mSample = null;

            //get exact length (because we have it decoded to PCM)
            //calculation stolen from SDL_sound's wav decoder, lol.
            uint bps = formatBps(fmt);
            assert(bps != 0);
            uint ms_len = (bufSize / bps) * 1000;
            ms_len += (bufSize % bps) * 1000 / bps;
            mLength = timeMsecs(ms_len);
        }

        //only do this when initialization was successful
        ctor(drv, sample);
        mDriver.mSounds ~= this;
    }

    private ALenum convertSDLFormat(ubyte channels, ushort format) {
        if (channels == 1) {
            if (format == AUDIO_U8 || format == AUDIO_S8)
                return AL_FORMAT_MONO8;
            return AL_FORMAT_MONO16;
        } else if (channels == 2) {
            if (format == AUDIO_U8 || format == AUDIO_S8)
                return AL_FORMAT_STEREO8;
            return AL_FORMAT_STEREO16;
        } else assert(false);
    }

    //returns bytes per second for a given SDL format
    private uint formatBps(Sound_AudioInfo fmt) {
        ubyte sampleSize = 2;
        if (fmt.format == AUDIO_U8 || fmt.format == AUDIO_S8)
            sampleSize = 1;
        return sampleSize * fmt.channels * fmt.rate;
    }

    private uint formatBps(Sound_Sample* sample) {
        return formatBps(sample.actual);
    }

    //called before the alSourcePlay() call
    private void initPlay(ALuint source, Time startAt) {
        alSourcei(source, AL_BUFFER, AL_NONE);
        mStreamedBytes = 0;
        if (mSample) {
            if (mCurrentSource != uint.max) {
                finishPlay();
                gLog.warn("ALSound.initPlay warning: tried to"
                    " play stream multiple times, current playback cut off");
            }
            Sound_Seek(mSample, startAt.msecs);
            mStreamedBytes = cast(uint)(startAt.secsf * formatBps(mSample));
            //streamed, queue first 2 buffers
            if (!stream(mALBuffer[0]) || !stream(mALBuffer[1]))
                throw new Exception("ALSound streaming failed");
            alSourceQueueBuffers(source, 2, mALBuffer.ptr);
            checkALError("alSourceQueueBuffers");
            mCurrentSource = source;
            streamEOF = false;
        } else {
            //not streamed, all data is already in first buffer
            alSourcei(source, AL_BUFFER, mALBuffer[0]);
            checkALError("alSourcei");
            //seek to start pos (note: will reset on loop)
            alSourcef(source, AL_SEC_OFFSET, startAt.secsf);
            checkALError("alSourcef");
        }
    }

    //called on stop, stop playback and prepare for restart
    private void finishPlay() {
        if (mCurrentSource == uint.max)
            return;

        //make sure playback is stopped
        alSourceStop(mCurrentSource);
        checkALError("alSourceStop");

        //unqueue all buffers
        int nbufs;
        ALuint buf;
        alGetSourcei(mCurrentSource, AL_BUFFERS_QUEUED, &nbufs);
        checkALError("alGetSourcei");
        while (nbufs--) {
            alSourceUnqueueBuffers(mCurrentSource, 1, &buf);
            checkALError("alSourceUnqueueBuffers");
        }
        mCurrentSource = uint.max;

        //restart from beginning
        Sound_Rewind(mSample);
        mStreamedBytes = 0;
    }

    //called every frame while playing
    private void update() {
        //only if streaming
        if (!mSample || mCurrentSource == uint.max)
            return;
        //check if queued buffers are done
        int processed;
        alGetSourcei(mCurrentSource, AL_BUFFERS_PROCESSED, &processed);
        checkALError("alGetSourcei");
        while(processed--) {
            //for all finished buffers, decode and queue a new one
            ALuint buffer;

            //pop from begin
            alSourceUnqueueBuffers(mCurrentSource, 1, &buffer);
            ALint bufs;
            alGetBufferi(buffer, AL_SIZE, &bufs);
            mStreamedBytes += bufs;
            if (!stream(buffer)) {
                streamEOF = true;
                return;
            }
            //queue at end
            alSourceQueueBuffers(mCurrentSource, 1, &buffer);
            checkALError("alSourceQueueBuffers");
        }
    }

    //fills the passed buffer with data
    //returns false if no more data available
    private bool stream(ALuint buffer) {
        assert(!!mSample);
        //returns bytes decoded, or 0 on EOF/error
        uint bufSize = Sound_Decode(mSample);
        if (bufSize == 0)
            return false;

        alBufferData(buffer,
            convertSDLFormat(mSample.actual.channels, mSample.actual.format),
            mSample.buffer, bufSize, mSample.actual.rate);
        checkALError("alBufferData");
        return true;
    }

    private bool canLoop() {
        //can't loop streamed sounds
        return !streamed;
    }

    private bool streamed() {
        return !!mSample;
    }

    //returns the current streaming position; only processed data is counted
    private Time streamPos() {
        if (mSample)
            return timeSecs(cast(float)mStreamedBytes / formatBps(mSample));
        else
            return Time.Null;
    }

    Time length() {
        return mLength;
    }

    private void free() {
        //check if already freed
        if (mALBuffer[0] == uint.max)
            return;
        if (mSample) {
            alDeleteBuffers(2, mALBuffer.ptr);
            checkALError("alDeleteBuffers");
            Sound_FreeSample(mSample);
            mStream.close();
            mStream = null;
            mSample = null;
        } else {
            alDeleteBuffers(1, &mALBuffer[0]);
            checkALError("alDeleteBuffers");
        }
        mALBuffer[] = uint.max;
    }

    override void destroy() {
        super.destroy();
        gBase.closeSound(this);
    }
}

class ALSoundDriver : SoundDriver {
    package {
        ALSound[] mSounds;
        ALChannel[] mChannels;
        ALCcontext* mALContext;
        ALCdevice* mALDevice;
    }

    const cDefaultChannelCount = 20;

    this() {
        assert(!gBase);
        gBase = this;

        gLog.minor("loading OpenAL");

        DerelictAL.load();

        //xxx could use some better error handling

        //how it is done in freealut-1.1.0
        mALDevice = alcOpenDevice(null);
        if (!mALDevice)
            throwError("could not open OpenAL device");
        mALContext = alcCreateContext(mALDevice, null);
        if (!mALContext)
            throwError("could not create OpenAL context");
        alcMakeContextCurrent(mALContext);

        sdlInit();
        Derelict_SetMissingProcCallback(&missingProcSDLsound);
        DerelictSDLSound.load();
        Derelict_SetMissingProcCallback(null);
        Sound_Init();

        //yyy mChannels.length = config.getIntValue("channels", cDefaultChannelCount);
        mChannels.length = cDefaultChannelCount;
        foreach (ref c; mChannels) {
            c = new ALChannel();
        }

        //probably set up listener (AL_POSITION, AL_VELOCITY, AL_GAIN,
        //AL_ORIENTATION), but there are defaults
    }

    DriverChannel getChannel(Object reserve_for, float priority = 0) {
        foreach (c; mChannels) {
            c.check();
            if (!c.reserved_for) {
                c.reserved_for = reserve_for;
                return c;
            }
        }
        //no free channel found, check if we can take a playing one with
        //  low priority
        foreach (c; mChannels) {
            c.checkWithPrio(priority);
            if (!c.reserved_for) {
                c.reserved_for = reserve_for;
                return c;
            }
        }
        return null;
    }

    void tick() {
        foreach (ref c; mChannels) {
            c.tick();
        }
    }

    override DriverResource createDriverResource(Resource res) {
        return new ALSound(this, castStrict!(Sample)(res));
    }

    void closeSound(DriverSound s) {
        gLog("close sound {}", s);
        auto as = castStrict!(ALSound)(s);
        foreach (c; mChannels) {
            if (c.mSound is as)
                c.stop(true);
        }
        arrayRemoveUnordered(mSounds, as);
        as.free();
    }

    override void destroy() {
        super.destroy();
        gLog.minor("unloading OpenAL");
        //caller must make sure all stuff has been unloaded
        assert(mSounds.length == 0);
        foreach (c; mChannels) {
            c.close();
        }
        gBase = null;
        Sound_Quit();
        DerelictSDLSound.unload();
        sdlQuit();

        alcMakeContextCurrent(null);
        alcDestroyContext(mALContext);
        alcCloseDevice(mALDevice);

        DerelictAL.unload();
        gLog.minor("unloaded OpenAL");
    }

    static this() {
        registerFrameworkDriver!(typeof(this))("sound_openal");
    }
}

private bool missingProcSDLsound(string libName, string procName) {
    if (procName == "Sound_GetDuration")
        return true;
    return false;
}
