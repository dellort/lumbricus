module framework.fmod;

///Sound driver implementation for the FMOD sound system, www.fmod.org
//Based on OpenAL sound driver implementation, which is quite crappy
//xxx contains some code which may be worth moving to a super class
//    (like fading)

import derelict.fmod.fmod;
import framework.framework;
import framework.sound;
import framework.fmodstreamfs;
import stdx.stream;
import tango.stdc.stringz;
import utils.array;
import utils.misc;
import utils.time;
import utils.configfile;

private FMODSoundDriver gBase;

class FMODSound : DriverSound {
    private {
        Stream mSourceSt;
        SoundType mType;
        FMOD_SOUND* mSound = null;
        Time mLength;
    }

    this(DriverSoundData data) {
        debug Trace.formatln("Load sound {}",data.filename);
        mSourceSt = gFS.open(data.filename);
        mType = data.type;
        //I'm assuming SoundType.sfx means load into memory, SoundType.music
        //  means streaming (xxx maybe rename those flags)
        FMOD_MODE m = FMOD_2D;
        if (mType == SoundType.sfx) {
            //create a sample in memory
            m |= FMOD_SOFTWARE;
        } else if (mType == SoundType.music) {
            //prepare a stream (keeping the source opened)
            m |= FMOD_SOFTWARE | FMOD_CREATESTREAM;
            //if (exactTiming)
            //    m |= FMOD_ACCURATETIME;
        } else assert(false);

        FMOD_ErrorCheck(FMOD_System_CreateSound(gBase.system,
            cast(char*)mSourceSt, m, null, &mSound));
        if (mType == SoundType.sfx) {
            //not needed anymore
            mSourceSt.close();
            mSourceSt = null;
        }

        //get sound length
        uint len;
        FMOD_ErrorCheck(FMOD_Sound_GetLength(mSound, &len, FMOD_TIMEUNIT_MS));
        mLength = timeMsecs(cast(int)len);
    }

    SoundType type() {
        return mType;
    }

    Time length() {
        return mLength;
    }

    private void free() {
        FMOD_Sound_Release(mSound);
        mSound = null;
        if (mSourceSt) {
            mSourceSt.close();
            mSourceSt = null;
        }
    }
}

//can't use FMOD virtual channel system with our api :(
class FMODChannel : DriverChannel {
    private {
        enum FadeType {
            none,
            fadeIn,
            fadeOut,
        }

        SoundSourcePosition mSourcePosition;
        FMOD_CHANNEL* mChannel;
        SoundType mSType;
        FadeType mFading;
        Time mFadeStart, mFadeLength;
    }
    bool neverfree;

    this() {
        owner = gBase;
    }

    override void setPos(ref SoundSourcePosition pos) {
        if (state != MusicState.Stopped) {
            update(pos);
        } else {
            mSourcePosition = pos;
        }
    }

    override void play(DriverSound s, bool loop) {
        play(s, loop, Time.Null, Time.Null);
    }

    void play(DriverSound s, bool loop, Time startAt, Time fade) {
        auto fs = castStrict!(FMODSound)(s);
        assert(!!fs);
        assert(!!reserved_for);
        stop(false);
        mSType = s.type;
        //allocate a channel, start paused
        FMOD_ErrorCheck(FMOD_System_PlaySound(gBase.system, FMOD_CHANNEL_REUSE,
            fs.mSound, true, &mChannel));

        update(mSourcePosition);
        FMOD_ErrorCheck(FMOD_Channel_SetPosition(mChannel, startAt.msecs(),
            FMOD_TIMEUNIT_MS));
        //0 = no looping, -1 = loop forever
        FMOD_ErrorCheck(FMOD_Channel_SetLoopCount(mChannel, loop ? -1 : 0));

        if (fade == Time.Null) {
            updateVolume();
        } else {
            internalSetVolume(0);
            startFade(FadeType.fadeIn, fade);
        }

        FMOD_ErrorCheck(FMOD_Channel_SetPaused(mChannel, false));
    }

    override void stop(bool unreserve) {
        stop(unreserve, Time.Null);
    }

    void stop(bool unreserve, Time fadeOut) {
        if (state != MusicState.Stopped) {
            if (fadeOut == Time.Null) {
                FMOD_Channel_Stop(mChannel);
            } else {
                //stop will be called again for final stop
                startFade(FadeType.fadeOut, fadeOut);
            }
        }
        //xxx when fading, channel could be unreserved while still playing
        //  but currently, fading is only for music, which has neverfree = true
        if (unreserve && !neverfree) {
            reserved_for = null;
        }
    }

    //initiate fadein/fadeout
    private void startFade(FadeType t, Time fTime) {
        mFading = t;
        mFadeStart = timeCurrentTime();
        mFadeLength = fTime;
    }

    private MusicState state() {
        if (!checkChannel)
            return MusicState.Stopped;
        int p;
        //check playing/stopped
        FMOD_ErrorCheck(FMOD_Channel_IsPlaying(mChannel, &p));
        if (p == 0)
            return MusicState.Stopped;
        //check playing/paused
        FMOD_ErrorCheck(FMOD_Channel_GetPaused(mChannel, &p));
        return p>0 ? MusicState.Paused : MusicState.Playing;
    }

    private void update(ref SoundSourcePosition pos) {
        assert(state != MusicState.Stopped);
        //pos.position.x should be in [-1, +1], -1 for left, +1 for right
        //xxx why is position a Vector2f??
        FMOD_ErrorCheck(FMOD_Channel_SetPan(mChannel, pos.position.x));
        //xxx FMOD has some nice effects like doppler, use them?
    }

    void setPause(bool p) {
        if (!checkChannel())
            return;
        FMOD_ErrorCheck(FMOD_Channel_SetPaused(mChannel, p));
    }

    Time position() {
        if (!checkChannel())
            return Time.Null;
        uint pos;
        FMOD_ErrorCheck(FMOD_Channel_GetPosition(mChannel, &pos,
            FMOD_TIMEUNIT_MS));
        return timeMsecs(cast(int)pos);
    }

    void check() {
        //whatever
        if (state == MusicState.Stopped && !neverfree) {
            reserved_for = null;
        }
    }

    //returns true if mChannel is still valid (may get stolen)
    private bool checkChannel() {
        if (!mChannel)
            return false;
        int idx;
        auto res = FMOD_Channel_GetIndex(mChannel, &idx);
        if (res == FMOD_OK)
            return true;
        return false;
    }

    private void internalSetVolume(float v) {
        FMOD_Channel_SetVolume(mChannel, v);
    }

    //refresh channel volume, and handle fading
    void updateVolume() {
        if (!checkChannel())
            return;
        if (mFading == FadeType.fadeIn) {
            //Fading in
            Time d = timeCurrentTime() - mFadeStart;
            if (d < mFadeLength) {
                float p = d.secsf()/mFadeLength.secsf();
                internalSetVolume(gBase.volume[mSType]*p);
            } else {
                internalSetVolume(gBase.volume[mSType]);
                mFading = FadeType.none;
            }
        } else if (mFading == FadeType.fadeOut) {
            //Fading out
            Time d = timeCurrentTime() - mFadeStart;
            if (d < mFadeLength) {
                float p = 1.0f - d.secsf()/mFadeLength.secsf();
                internalSetVolume(gBase.volume[mSType]*p);
            } else {
                stop(false, Time.Null);
                mFading = FadeType.none;
            }
        } else {
            internalSetVolume(gBase.volume[mSType]);
        }
    }

    void tick() {
        if (mFading != FadeType.none)
            updateVolume();
    }

    void close() {
        stop(true);
    }
}

///sound driver for FMOD sound system, www.fmod.org
///  FMOD is free for non-commercial use
class FMODSoundDriver : SoundDriver {
    private {
        FMOD_SYSTEM* mSystem;
        alias mSystem system;
        FMODChannel[] mChannels;
        FMODChannel mMusic;
        float[SoundType.max+1] volume;
    }

    const cDefaultChannelCount = 32;

    this(Sound base, ConfigNode config) {
        assert(base is gFramework.sound()); //lol

        assert(!gBase);
        gBase = this;

        DerelictFMOD.load();

        FMOD_ErrorCheck(FMOD_System_Create(&mSystem));
        scope(failure) FMOD_System_Release(mSystem);

        uint fmVersion;
        FMOD_ErrorCheck(FMOD_System_GetVersion(mSystem, &fmVersion));
        if (fmVersion < FMOD_VERSION)
            throw new Exception(myformat(
            "Version of FMOD library is too low. Required is at least {:x8}",
            FMOD_VERSION));

        FMOD_ErrorCheck(FMOD_System_SetOutput(mSystem,
            FMOD_OUTPUTTYPE_AUTODETECT));

        FMOD_ErrorCheck(FMOD_System_Init(mSystem, 32, FMOD_INIT_NORMAL, null));
        scope(failure) FMOD_System_Close(mSystem);

        FMODSetStreamFs(mSystem,true);

        mChannels.length = config.getIntValue("channels", cDefaultChannelCount);
        foreach (ref c; mChannels) {
            c = new FMODChannel();
        }

        mMusic = castStrict!(FMODChannel)(getChannel(this));
        assert(!!mMusic);
        mMusic.neverfree = true;

        for (SoundType s; s <= SoundType.max; s++) {
            volume[s] = 1.0f;
        }
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
        FMOD_System_Update(mSystem);
        foreach (c; mChannels) {
            c.tick();
        }
    }

    DriverSound loadSound(DriverSoundData data) {
        return new FMODSound(data);
    }

    void closeSound(DriverSound s) {
        auto fs = castStrict!(FMODSound)(s);
        fs.free();
    }

    void setVolume(SoundType v, float value) {
        volume[v] = clampRangeC(value, 0f, 1.0f);
        foreach (c; mChannels) {
            c.updateVolume();
        }
    }

    void destroy() {
        foreach (c; mChannels) {
            c.close();
        }
        FMODSetStreamFs(mSystem, false);
        FMOD_System_Close(mSystem);
        FMOD_System_Release(mSystem);
        DerelictFMOD.unload();
        gBase = null;
    }

    void musicPlay(DriverSound m, Time startAt, Time fade) {
        if (!m) {
            mMusic.stop(false);
        } else {
            mMusic.play(m, true, startAt, fade);
        }
    }

    void musicFadeOut(Time fadetime) {
        mMusic.stop(false, fadetime);
    }

    void musicGetState(out MusicState state, out Time pos) {
        pos = mMusic.position;
        state = mMusic.state;
    }

    void musicPause(bool pause) {
        mMusic.setPause(pause);
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("fmod");
    }
}
