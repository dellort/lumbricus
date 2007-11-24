module framework.sdl.soundmixer;

import derelict.sdl.mixer;
import derelict.sdl.sdl;
import framework.framework;
import framework.sound;
import framework.sdl.rwops;
import std.stream;
import str = std.string;
import utils.time;

private void throwError() {
    throw new Exception("Sound error: " ~ str.toString(Mix_GetError()));
}

class SoundMixer : Sound {
    protected float[Volume.max+1] volume;
    private SampleMixer[] mSamples;
    private MusicMixer[] mMusics;

    private const cChannelCount = 32;

    //currently playing music, set by MusicMixer.play
    private MusicMixer mCurrentMusic;

    this() {
        DerelictSDLMixer.load();
        //44.1kHz stereo
        Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 2048);

        //allocate 32 mixing channels
        Mix_AllocateChannels(cChannelCount);

        volume[Volume.music] = 1.0f;
        volume[Volume.sfx] = 1.0f;
    }

    public void tick() {
        //SDL_Mixer does not need this
    }

    public void deinitialize() {
        foreach (s; mSamples) s.close;
        foreach (m; mMusics) m.close;
        DerelictSDLMixer.unload();
    }

    public Music createMusic(Stream st, bool ownsStream = true) {
        MusicMixer mus = new MusicMixer(this, st, ownsStream);
        mMusics ~= mus;
        return mus;
    }

    public Sample createSample(Stream st, bool ownsStream = true) {
        SampleMixer sample = new SampleMixer(this, st, ownsStream);
        mSamples ~= sample;
        return sample;
    }

    public void setVolume(Volume v, float value) {
        volume[v] = value;
    }

    private void setCurrentMusic(MusicMixer mus) {
        mCurrentMusic = mus;
    }

    private MusicMixer currentMusicInt() {
        return mCurrentMusic;
    }

    public Music currentMusic() {
        return mCurrentMusic;
    }
}

class MusicMixer : Music {
    private SoundMixer mParent;
    private Mix_Music* mMusic;
    private Stream mSrc;
    private bool mOwnsStream;
    private bool mOpen;

    private this(SoundMixer parent, Stream st, bool ownsStream) {
        mParent = parent;
        mSrc = st;
        mOwnsStream = ownsStream;

        SDL_RWops* ops = rwopsFromStream(st);
        mMusic = Mix_LoadMUS_RW(ops);
        if (!mMusic)
            throwError();
        mOpen = true;
    }

    public void close() {
        if (!mOpen)
            return;
        mOpen = false;

        if (mParent.currentMusicInt == this)
            mParent.setCurrentMusic(null);

        Mix_FreeMusic(mMusic);
        if (mOwnsStream)
            mSrc.close();
    }

    public void play(Time start = timeMusecs(0),
        Time fadeinTime = timeMusecs(0))
    {
        if (!mOpen)
            return;

        mParent.setCurrentMusic(this);
        Mix_FadeInMusicPos(mMusic, -1, fadeinTime.msecs, start.secsf);
    }

    public void paused(bool p) {
        if (mParent.currentMusicInt != this)
            return;
        if (!mOpen)
            return;

        if (p)
            Mix_PauseMusic();
        else
            Mix_ResumeMusic();
    }

    public bool playing() {
        if (mParent.currentMusicInt == this && Mix_PlayingMusic())
            return true;
        return false;
    }

    public void stop() {
        if (playing) {
            Mix_HaltMusic();
            mParent.setCurrentMusic(null);
        }
    }

    public void fadeOut(Time fadeTime) {
        if (playing)
            Mix_FadeOutMusic(fadeTime.msecs);
    }

    public Time position() {
        throw new Exception("Music.position: Not supported");
        return timeSecs(0);
    }

    public Time length() {
        throw new Exception("Music.length: Not supported");
        return timeSecs(0);
    }
}

class SampleMixer : Sample {
    private Mix_Chunk* mChunk;
    private SoundMixer mParent;
    private bool mOpen;

    private this(SoundMixer parent, Stream st, bool ownsStream) {
        mParent = parent;
        SDL_RWops* ops = rwopsFromStream(st);
        //if ownsStream == true, stream is closed by this call
        mChunk = Mix_LoadWAV_RW(ops, ownsStream);
        if (!mChunk)
            throwError();
        mOpen = true;
    }

    public void close() {
        if (!mOpen)
            return;
        mOpen = false;

        //stop all channels still playing the sample
        for (int i = 0; i < SoundMixer.cChannelCount; i++) {
            if (Mix_GetChunk(i) == mChunk) {
                Mix_HaltChannel(i);
            }
        }
        Mix_FreeChunk(mChunk);
        mChunk = null;
    }

    public void play() {
        if (!mOpen)
            return;

        Mix_VolumeChunk(mChunk, cast(int)(mParent.volume[Volume.sfx]
            *MIX_MAX_VOLUME));
        Mix_PlayChannel(-1, mChunk, 0);
    }
}
