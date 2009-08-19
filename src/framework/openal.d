module framework.openal;

import derelict.openal.al;
import derelict.openal.alut;
import framework.framework;
import framework.sound;
import utils.stream;
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

    void setPos(ref SoundSourceInfo pos) {
        //xxx sounds wrong... maybe we need to set up listener position
        alSource3f(source, AL_POSITION, pos.position.x/2.0f, 0.0f, 0.0f);
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

class ALSound : DriverSound {
    ALSoundDriver mDriver;
    Time mLength;
    ALuint mALBuffer;

    this(ALSoundDriver drv, DriverSoundData data) {
        mDriver = drv;
        mDriver.mSounds ~= this;
        auto source = gFS.open(data.filename);
        //no Stream-like abstraction (?) => temporarily copy into memory
        auto stuff = new char[source.size()];
        source.position = 0;
        source.readExact(cast(ubyte[])stuff);
        mALBuffer = alutCreateBufferFromFileImage(stuff.ptr, stuff.length);
        delete stuff;
        if (mALBuffer == AL_NONE) {
            throwALUTError("loading of '"~data.filename~"'");
        }
        //xxx set mLength
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
        DerelictALUT.unload();
        DerelictAL.unload();
        debug Trace.formatln("unloaded OpenAL");
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("openal");
    }
}
