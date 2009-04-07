module framework.openal;

import derelict.openal.al;
import derelict.openal.alut;
import framework.framework;
import framework.sound;
import stdx.stream;
import tango.stdc.stringz;
import utils.array;
import utils.misc;
import utils.time;
import utils.configfile;


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

    void setPos(ref SoundSourcePosition pos) {
        alSource3f(source, AL_POSITION, pos.position.x, pos.position.y, 0.0f);
    }

    void play(DriverSound s, bool loop) {
        auto as = castStrict!(ALSound)(s);
        assert(!!as);
        assert(!!reserved_for);
        alSourceStop(source);
        alSourcei(source, AL_LOOPING, loop ? AL_TRUE : AL_FALSE);
        alSourcei(source, AL_BUFFER, as.mALBuffer);
        alSourcePlay(source);
        assert (state() == AL_PLAYING);
        lastbuffer = as.mALBuffer;
    }

    void stop(bool unreserve) {
        alSourceStop(source);
        lastbuffer = int.max;
        if (unreserve && !neverfree) {
            reserved_for = null;
        }
    }

    void setPause(bool p) {
        if (p) {
            alSourcePause(source);
        } else if (state() == AL_PAUSED) {
            alSourcePlay(source);
        }
    }

    ALint state() {
        ALint s;
        alGetSourcei(source, AL_SOURCE_STATE, &s);
        checkALError("alGetSourcei");
        return s;
    }

    void check() {
        if ((state() != AL_PLAYING) && !neverfree) {
            reserved_for = null;
        }
    }

    void close() {
        stop(true);
        alDeleteSources(1, &source);
    }
}

class ALSound : DriverSound {
    ALSoundDriver mDriver;
    Time mLength;
    SoundType mType;
    ALuint mALBuffer;

    this(ALSoundDriver drv, DriverSoundData data) {
        mDriver = drv;
        mDriver.mSounds ~= this;
        auto source = gFS.open(data.filename);
        //no Stream-like abstraction (?) => temporarily copy into memory
        auto stuff = new char[source.size()];
        source.position = 0;
        source.readExact(stuff.ptr, stuff.length);
        mALBuffer = alutCreateBufferFromFileImage(stuff.ptr, stuff.length);
        delete stuff;
        if (mALBuffer == AL_NONE) {
            throwALUTError("loading of '"~data.filename~"'");
        }
        //bleh
        mType = data.type;
    }

    SoundType type() {
        return mType;
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
        float[SoundType.max+1] volume;
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

        volume[SoundType.music] = 1.0f;
        volume[SoundType.sfx] = 1.0f;
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

    void setVolume(SoundType v, float value) {
        volume[v] = value;
        //xxx
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
        DerelictALUT.unload();
        DerelictAL.unload();
        debug Trace.formatln("unloaded OpenAL");
    }

    void musicPlay(DriverSound m, Time startAt, Time fade) {
        auto as = castStrict!(ALSound)(m);
        if (!m) {
            mMusic.stop(false);
        } else {
            mMusic.play(m, true);
        }
    }

    void musicFadeOut(Time fadetime) {
        //???
        musicPlay(null, Time.Null, Time.Null);
    }

    void musicGetState(out MusicState state, out Time pos) {
        auto s = mMusic.state();
        if (s == AL_PLAYING) {
            state = MusicState.Playing;
        } else if (s == AL_PAUSED) {
            state = MusicState.Paused;
        } else {
            state = MusicState.Stopped;
        }
    }

    void musicPause(bool pause) {
        mMusic.setPause(pause);
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("openal");
    }
}
