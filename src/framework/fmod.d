module framework.fmod;

///Sound driver implementation for the FMOD sound system, www.fmod.org
//Based on OpenAL sound driver implementation, which is quite crappy
//xxx contains some code which may be worth moving to a super class
//    (like fading)

import derelict.fmod.fmod;
import framework.framework;
import framework.sound;
import framework.fmodstreamfs;
import utils.stream;
import tango.stdc.stringz;
import utils.array;
import utils.misc;
import utils.time;
import utils.configfile;
import utils.list2;

private FMODSoundDriver gBase;

class FMODSound : DriverSound {
    private {
        Stream mSourceSt;
        FMOD_SOUND* mSound = null;
        Time mLength;
    }

    this(DriverSoundData data) {
        debug Trace.formatln("Load sound {}",data.filename);
        mSourceSt = gFS.open(data.filename);

        FMOD_MODE m = FMOD_2D;
        if (data.streamed) {
            //prepare a stream (keeping the source opened)
            m |= FMOD_SOFTWARE | FMOD_CREATESTREAM;
            //if (exactTiming)
            //    m |= FMOD_ACCURATETIME;
        } else {
            //create a sample in memory
            m |= FMOD_SOFTWARE;
        }

        FMOD_ErrorCheck(FMOD_System_CreateSound(gBase.system,
            cast(char*)mSourceSt, m, null, &mSound));
        if (!data.streamed) {
            //not needed anymore
            mSourceSt.close();
            mSourceSt = null;
        }

        //get sound length
        uint len;
        FMOD_ErrorCheck(FMOD_Sound_GetLength(mSound, &len, FMOD_TIMEUNIT_MS));
        mLength = timeMsecs(cast(int)len);
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

//this corresponds to a FMOD "virtual channel" and is created on demand
class FMODChannel : DriverChannel {
    private {
        SoundSourceInfo mSourceInfo;
        FMOD_CHANNEL* mChannel;
    }
    ObjListNode!(typeof(this)) chNode;

    this() {
        owner = gBase;
    }

    override void setPos(ref SoundSourceInfo pos) {
        if (state != PlaybackState.stopped) {
            update(pos);
        } else {
            mSourceInfo = pos;
        }
    }

    void setVolume(float v) {
        FMOD_Channel_SetVolume(mChannel, v);
    }

    override void play(DriverSound s, bool loop, Time startAt) {
        auto fs = castStrict!(FMODSound)(s);
        assert(!!fs);
        assert(!!reserved_for);
        stop(false);
        //allocate a channel, start paused
        FMOD_ErrorCheck(FMOD_System_PlaySound(gBase.system, FMOD_CHANNEL_REUSE,
            fs.mSound, true, &mChannel));

        update(mSourceInfo);
        FMOD_ErrorCheck(FMOD_Channel_SetPosition(mChannel, startAt.msecs(),
            FMOD_TIMEUNIT_MS));
        if (loop) {
            FMOD_ErrorCheck(FMOD_Channel_SetMode(mChannel, FMOD_LOOP_NORMAL));
            //0 = no looping, -1 = loop forever
            FMOD_ErrorCheck(FMOD_Channel_SetLoopCount(mChannel, -1));
        } else {
            FMOD_ErrorCheck(FMOD_Channel_SetMode(mChannel, FMOD_LOOP_OFF));
        }

        FMOD_ErrorCheck(FMOD_Channel_SetPaused(mChannel, false));
    }

    override void stop(bool unreserve) {
        if (state != PlaybackState.stopped) {
            FMOD_Channel_Stop(mChannel);
        }

        if (unreserve) {
            reserved_for = null;
        }
    }

    override PlaybackState state() {
        if (!checkChannel)
            return PlaybackState.stopped;
        int p;
        //check playing/stopped
        FMOD_ErrorCheck(FMOD_Channel_IsPlaying(mChannel, &p));
        if (p == 0)
            return PlaybackState.stopped;
        //check playing/paused
        FMOD_ErrorCheck(FMOD_Channel_GetPaused(mChannel, &p));
        return p>0 ? PlaybackState.paused : PlaybackState.playing;
    }

    private void update(ref SoundSourceInfo pos) {
        assert(state != PlaybackState.stopped);
        //pos.position.x should be in [-1, +1], -1 for left, +1 for right
        //xxx why is position a Vector2f??
        FMOD_ErrorCheck(FMOD_Channel_SetPan(mChannel, pos.position.x));
        //xxx FMOD has some nice effects like doppler, use them?
    }

    void paused(bool p) {
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
        if (state == PlaybackState.stopped) {
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

    void tick() {
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
        ObjectList!(FMODChannel, "chNode") mChannels;
    }

    //Number of "virtual" FMOD channels to use
    const cVirtualChannelCount = 512;

    this(Sound base, ConfigNode config) {
        assert(base is gFramework.sound()); //lol

        assert(!gBase);
        gBase = this;

        mChannels = new typeof(mChannels);

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

        FMOD_ErrorCheck(FMOD_System_Init(mSystem, cVirtualChannelCount,
            FMOD_INIT_NORMAL, null));
        scope(failure) FMOD_System_Close(mSystem);

        FMODSetStreamFs(mSystem,true);
    }

    DriverChannel getChannel(Object reserve_for) {
        //look for a free channel (reuse class)
        foreach (c; mChannels) {
            c.check();
            if (!c.reserved_for) {
                c.reserved_for = reserve_for;
                return c;
            }
        }
        //check if there is room for another channel
        if (mChannels.count < cVirtualChannelCount) {
            auto ch = new FMODChannel();
            ch.reserved_for = reserve_for;
            mChannels.add(ch);
            return ch;
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

    void destroy() {
        foreach (c; mChannels) {
            c.close();
            mChannels.remove(c);
        }
        FMODSetStreamFs(mSystem, false);
        FMOD_System_Close(mSystem);
        FMOD_System_Release(mSystem);
        DerelictFMOD.unload();
        gBase = null;
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("fmod");
    }
}
