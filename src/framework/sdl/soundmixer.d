module framework.sdl.soundmixer;

import derelict.sdl.mixer;
import derelict.sdl.sdl;
import framework.framework;
import framework.sound;
import framework.sdl.rwops;
import framework.sdl.sdl;
import std.stream;
import str = std.string;
import utils.array;
import utils.misc;
import utils.time;

private void throwError() {
    throw new Exception("Sound error: " ~ str.toString(Mix_GetError()));
}

class SDLChannel : DriverChannel {
    SDLSoundDriver mParent;
    int mChannel; //SDL_mixer channel number

    void setPos(ref SoundSourcePosition pos) {
        float l = 1.0f, r = 1.0f;
        //no idea how to use this correctly, so I came up with some crap
        float x = pos.position.x;
        l = x > 0 ? 1.0f - x : 1.0f;
        r = x < 0 ? 1.0f + x : 1.0f;
        Mix_SetPanning(mChannel, cast(int)(clampRangeC(l, 0.0f, 1.0f)*255),
            cast(int)(clampRangeC(r, 0.0f, 1.0f)*255));
    }

    void play(DriverSound s, bool loop) {
        auto ss = castStrict!(SDLSound)(s);
        assert(ss && ss.type() == SoundType.sfx && ss.mChunk);
        assert(!!reserved_for, "channel wasn't reserved, but is being used");

        Mix_PlayChannel(mChannel, ss.mChunk, loop ? -1 : 0);
    }

    void stop(bool unreserve) {
        Mix_HaltChannel(mChannel);
        if (unreserve) {
            reserved_for = null;
        }
    }

    void check() {
        if (Mix_Playing(mChannel) == 0)
            reserved_for = null;
    }
}

class SDLSound : DriverSound {
    //exactly one of these is non-null, depending on what it is
    Mix_Chunk* mChunk;
    Mix_Music* mMusic;
    Stream mSource;
    SDLSoundDriver mDriver;
    Time mLength;

    this(SDLSoundDriver drv, DriverSoundData data) {
        mDriver = drv;
        mDriver.mSounds ~= this;
        mSource = gFramework.fs.open(data.filename);
        SDL_RWops* ops = rwopsFromStream(mSource);
        switch (data.type) {
            case SoundType.music:
                mMusic = Mix_LoadMUS_RW(ops);
                break;
            case SoundType.sfx:
                mChunk = Mix_LoadWAV_RW(ops, 1);
                mSource.close();
                mSource = null;
                break;
        }
        if (!mMusic && !mChunk)
            throwError();

        if (mChunk) {
            //hopefully correct? not tested yet
            int samples = mChunk.alen / mDriver.bytes_per_sample;
            mLength = timeMsecs(1000*samples / mDriver.frequency);
        } else if (mMusic) {
            // :(
            mLength = Time.Null;
        }
    }

    SoundType type() {
        return mChunk ? SoundType.sfx : SoundType.music;
    }

    Time length() {
        return mLength;
    }

    private void free() {
        if (mChunk)
            Mix_FreeChunk(mChunk);
        if (mMusic)
            Mix_FreeMusic(mMusic);
        mChunk = null;
        mMusic = null;
    }
}

class SDLSoundDriver : SoundDriver {
    package {
        float[SoundType.max+1] volume;
        SDLSound[] mSounds; //samples+music
        int frequency;
        //per sample and channel
        int bytes_per_sample;
        SDLChannel[] mChannels;
        Mix_Music* mLastPlayed;
    }

    const cDefaultChannelCount = 32;

    this(Sound base, ConfigNode config) {
        assert(base is gFramework.sound()); //lol
        std.stdio.writefln("loading sdl_mixer");

        sdlInit();

        DerelictSDLMixer.load();
        if (SDL_InitSubSystem(SDL_INIT_AUDIO) < 0) {
            throw new Exception(format("Could not init SDL audio subsystem: %s",
                std.string.toString(SDL_GetError())));
        }

        //44.1kHz stereo
        if (Mix_OpenAudio(config.getIntValue("frequency", 44100), AUDIO_S16SYS,
            2, 2048) == -1)
        {
            throwError();
        }

        //get bytes per sample to be able to calculate the length of samples
        int freq;
        Uint16 format;
        int channels;
        if (Mix_QuerySpec(&freq, &format, &channels) == 0) {
            throwError();
        }
        //better way?
        static int bytes(Uint16 format) {
            switch (format) {
                case AUDIO_U8, AUDIO_S8:
                    return 1;
                case AUDIO_U16LSB, AUDIO_S16LSB, AUDIO_U16MSB, AUDIO_S16MSB:
                    return 2;
                default:
                    throw new Exception("unknown audio format");
            }
        }
        bytes_per_sample = bytes(format)*channels;
        frequency = freq;

        //allocate 32 mixing channels
        mChannels.length = config.getIntValue("channels", cDefaultChannelCount);
        Mix_AllocateChannels(mChannels.length);

        foreach (int index, ref c; mChannels) {
            c = new SDLChannel();
            c.owner = this;
            c.mParent = this;
            c.mChannel = index;
        }

        volume[SoundType.music] = 1.0f;
        volume[SoundType.sfx] = 1.0f;

        std.stdio.writefln("loaded sdl_mixer");
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
        return new SDLSound(this, data);
    }

    void closeSound(DriverSound s) {
        std.stdio.writefln("close sound %s", s);
        auto ss = castStrict!(SDLSound)(s);
        if (ss.mChunk) {
            //stop from playing on any channels
            foreach (c; mChannels) {
                if (Mix_GetChunk(c.mChannel) == ss.mChunk)
                    c.stop(true);
            }
        } else if (ss.mMusic) {
            if (ss.mMusic is mLastPlayed) {
                mLastPlayed = null;
                Mix_HaltMusic();
            }
        }
        arrayRemoveUnordered(mSounds, ss);
        ss.free();
    }

    void setVolume(SoundType v, float value) {
        volume[v] = value;
        Mix_Volume(-1, cast(int)(volume[SoundType.sfx]*MIX_MAX_VOLUME));
        Mix_VolumeMusic(cast(int)(volume[SoundType.music]*MIX_MAX_VOLUME));
    }

    void destroy() {
        std.stdio.writefln("unloading sdl_mixer");
        //caller must make sure all stuff has been unloaded
        assert(mSounds.length == 0);
        Mix_CloseAudio();
        SDL_QuitSubSystem(SDL_INIT_AUDIO);
        DerelictSDLMixer.unload();
        sdlQuit();
        std.stdio.writefln("unloaded sdl_mixer");
    }

    void musicPlay(DriverSound m, Time startAt, Time fade) {
        auto ss = castStrict!(SDLSound)(m);
        if (!ss) {
            Mix_HaltMusic();
            mLastPlayed = null;
            return;
        }
        std.stdio.writefln("play!");
        assert(ss.type() == SoundType.music && ss.mMusic);
        Mix_FadeInMusicPos(ss.mMusic, -1, fade.msecs, startAt.secsf);
        mLastPlayed = ss.mMusic;
    }

    void musicFadeOut(Time fadetime) {
        Mix_FadeOutMusic(fadetime.msecs);
    }

    void musicGetState(out MusicState state, out Time pos) {
        //SDL_mixer makes it too hard to support pos
        if (!Mix_PlayingMusic())
            return MusicState.Stopped;
        state = Mix_PausedMusic() ? MusicState.Paused : MusicState.Playing;
    }

    void musicPause(bool pause) {
        if (!Mix_PlayingMusic())
            return;
        if (!!Mix_PausedMusic() == pause)
            return;
        if (pause) {
            Mix_PauseMusic();
        } else {
            Mix_ResumeMusic();
        }
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("sdl_mixer");
    }
}
