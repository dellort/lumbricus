module framework.openal;

import derelict.openal.al;
import derelict.openal.alut;
import derelict.sdl.sdl;
import derelict.sdl.sound;
import framework.framework;
import framework.sound;
import framework.sdl.sdl;
import framework.sdl.rwops;
import utils.stream;
import tango.stdc.stringz;
import utils.array;
import utils.misc;
import utils.time;
import utils.configfile;
import utils.path;


private void throwALUTError(char[] msg) {
    throw new Exception(msg ~ " failed: "~fromStringz(
        alutGetErrorString(alutGetError())));
}

private void checkALError(char[] msg) {
    int code = alGetError();
    if (code != AL_NO_ERROR) {
        throw new Exception("call of "~msg~" failed: "~fromStringz(
            alGetString(code)));
    }
}

private ALSoundDriver gBase;

class ALChannel : DriverChannel {
    ALuint source;
    ALuint lastbuffer;
    bool neverfree;

    this() {
        owner = gBase;
        alGenSources(1, &source);
        checkALError("alGenSources");
    }

    void setPos(ref SoundSourceInfo pos) {
        //listener orientation is (0, 0, -1), so this should position the source
        //in front of the listener with a 90° FOV, meaning x values close
        //to -1 / 1 will sound "off-screen"
        //y is source height, positive meaning "up"
        alSource3f(source, AL_POSITION, pos.position.x, pos.position.y, -1.0f);
    }

    void play(DriverSound s, bool loop, Time startAt) {
        //xxx startAt is ignored
        auto as = castStrict!(ALSound)(s);
        assert(!!as);
        assert(!!reserved_for);
        alSourceStop(source);
        alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);
        alSourcei(source, AL_BUFFER, as.mALBuffer);
        alSourcePlay(source);
        assert (oalState() == AL_PLAYING);
        lastbuffer = as.mALBuffer;
    }

    void stop(bool unreserve) {
        alSourceStop(source);
        lastbuffer = int.max;
        if (unreserve && !neverfree) {
            reserved_for = null;
        }
    }

    void paused(bool p) {
        if (p) {
            alSourcePause(source);
        } else if (oalState() == AL_PAUSED) {
            alSourcePlay(source);
        }
    }

    void setVolume(float value) {
        alSourcef(source, AL_GAIN, value);
    }

    ALint oalState() {
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
        if (oalState == AL_PLAYING || oalState == AL_PAUSED) {
            ALfloat pos;
            alGetSourcef(source, AL_SEC_OFFSET, &pos);
            return timeSecs(pos);
        } else {
            return Time.Null;
        }
    }

    void check() {
        if ((oalState() != AL_PLAYING) && !neverfree) {
            reserved_for = null;
        }
    }

    void close() {
        stop(true);
        alDeleteSources(1, &source);
    }
}
import tango.io.device.File;
class ALSound : DriverSound {
    ALSoundDriver mDriver;
    Time mLength;
    ALuint mALBuffer;

    this(ALSoundDriver drv, DriverSoundData data) {
        mDriver = drv;
        mDriver.mSounds ~= this;

        //open the stream and create a sample
        auto source = gFS.open(data.filename);
        SDL_RWops* ops = rwopsFromStream(source);
        //1024*1024 is the buffer size, meaning DecodeAll with process 1mb
        //  at once and then grow the output buffer by that amount
        Sound_Sample* smp = Sound_NewSample(ops,
            toStringz(VFSPath(data.filename).extNoDot()), null, 1024*1024);
        if (!smp) {
            throw new Exception("SDL_sound failed to load '"~data.filename~"'");
        }
        Trace.formatln("Sound-Err: {}", fromStringz(Sound_GetError()));
        Trace.formatln("{}Hz, {}Ch, {}", smp.actual.rate, smp.actual.channels, smp.actual.format);

        //decode everything into memory (no streaming for now)
        Sound_DecodeAll(smp);

        //debug output
        File.set("out.raw", cast(void[])smp.buffer[0..smp.buffer_size]);

        Trace.formatln("Sound-Err: {}", fromStringz(Sound_GetError()));
        //copy sound data to openal buffer
        alGenBuffers(1, &mALBuffer);
        alBufferData(mALBuffer,
            convertSDLFormat(smp.actual.channels, smp.actual.format),
            smp.buffer, smp.buffer_size, smp.actual.rate);

        //close original sample
        Sound_FreeSample(smp);
        source.close();

        //xxx set mLength
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

    Time length() {
        return mLength;
    }

    private void free() {
        alDeleteSources(1, &mALBuffer);
        mALBuffer = uint.max;
    }
}

class ALSoundDriver : SoundDriver {
    package {
        ALSound[] mSounds;
        ALChannel[] mChannels;
        ALChannel mMusic;
    }

    const cDefaultChannelCount = 28;

    this(Sound base, ConfigNode config) {
        assert(base is gFramework.sound()); //lol

        assert(!gBase);
        gBase = this;

        DerelictAL.load();
        DerelictALUT.load();

        sdlInit();
        DerelictSDLSound.load();
        Sound_Init();

        if (alutInit(null, null) == AL_FALSE) {
            throwALUTError("alutInit");
        }

        mChannels.length = config.getIntValue("channels", cDefaultChannelCount);
        foreach (ref c; mChannels) {
            c = new ALChannel();
        }

        mMusic = castStrict!(ALChannel)(getChannel(this));
        assert(!!mMusic);
        mMusic.neverfree = true;

        //probably set up listener (AL_POSITION, AL_VELOCITY, AL_GAIN,
        //AL_ORIENTATION), but there are defaults
    }

    DriverChannel getChannel(Object reserve_for) {
        foreach (c; mChannels) {
            c.check();
            if (!c.reserved_for) {
                c.reserved_for = reserve_for;
                return c;
            }
        }
        return null;
    }

    void tick() {
    }

    DriverSound loadSound(DriverSoundData data) {
        return new ALSound(this, data);
    }

    void closeSound(DriverSound s) {
        debug Trace.formatln("close sound {}", s);
        auto as = castStrict!(ALSound)(s);
        foreach (c; mChannels) {
            if (as.mALBuffer == c.lastbuffer)
                c.stop(true);
        }
        arrayRemoveUnordered(mSounds, as);
        as.free();
    }

    void destroy() {
        debug Trace.formatln("unloading OpenAL");
        //caller must make sure all stuff has been unloaded
        assert(mSounds.length == 0);
        foreach (c; mChannels) {
            c.close();
        }
        gBase = null;
        alutExit();
        Sound_Quit();
        DerelictSDLSound.unload();
        sdlQuit();
        DerelictALUT.unload();
        DerelictAL.unload();
        debug Trace.formatln("unloaded OpenAL");
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("openal");
    }
}
