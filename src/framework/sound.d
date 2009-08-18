module framework.sound;

import framework.framework, utils.configfile, utils.factory, utils.time,
    utils.vector2, utils.weaklist, utils.stream, utils.misc, utils.list2;

//sound type is only used for mixing (e.g. sfx may be louder than music)
//  (esp. this should not influence streaming behaviour)
alias ubyte SoundType;

public enum PlaybackState {
    stopped,     //playback has not yet started, or has reached the end
                 //in either case, play() will start playing from the start
    playing,
    paused,
    stopping,    //fading out to stop
}

//some data about the object the sound is attached to
//the mixer can use this to make sound more realistic according to the object's
//position/movement
struct SoundSourceInfo {
    //units: I don't know how to handle this (and we don't even have an OpenAL
    //backend to test it), but I thought about placing the listener into the
    //middle of the screen and to define the respective borders as -1 and +1
    //SoundScene does the rest
    Vector2f position;
    //(I think OpenAL could do a lot more here, like this?)
    //Vector2f speed;
}

//the (really, really sucky) memory managment hack
package {
    struct SoundKillData {
        DriverSound sound;

        void doFree() {
            if (sound) {
                gFramework.sound.killDriverSound(sound);
            }
        }
    }
    WeakList!(Sample, SoundKillData) gSounds;
}

///audio data (or rather, how it can be loaded)
///[the stream data is owned by the Sound class; and as long a DriverSound is
///allocated with this DriverSoundData, the DriverSound can assume it's the
///only code which reads/seeks the Stream
///probably a smarter way would be to store the filename instead of the stream]
struct DriverSoundData {
    char[] filename;
    bool streamed;  //streamed audio can only have one instance playing;
                    //no other restrictions
}

///handle for any sound data (samples and music)
///DriverSoundData is used to create this!
//(unifying smaples and music simplifies memory managment)
abstract class DriverSound {
    abstract Time length();
}

///a channel is used to play sound effects (but not music, strange, hurrr)
abstract class DriverChannel {
    SoundDriver owner;
    //actually a class Channel or null
    //will be set to null if playback is finished or driver is unloaded etc.
    Object reserved_for;

    abstract void setPos(ref SoundSourceInfo pos);
    //set absolute volume of this channel
    abstract void setVolume(float value);

    //play() and stop() must only be called if you're still the owner by
    //reserved_by
    abstract void play(DriverSound s, bool loop, Time startAt);

    abstract void paused(bool p);

    //unreserve==true: make channel available to others (getChannel())
    abstract void stop(bool unreserve);

    abstract PlaybackState state();

    abstract Time position();
}

abstract class SoundDriver {
    //create/get a free channel to play stuff
    //returns null if none available
    //reserve_for: DriverChannel.reserved_for is set to it
    abstract DriverChannel getChannel(Object reserve_for);
    //call each frame
    abstract void tick();
    //load/destroy a sound file
    abstract DriverSound loadSound(DriverSoundData data);
    abstract void closeSound(DriverSound s);

    abstract void destroy();
}

///main sound class, loads samples and music and sets volume
//NOTE: not overloaded by sound driver anymore
public class Sound {
    private {
        //Music mCurrentMusic;
        SoundDriver mDriver;
        //all loaded sound files (music & samples)
        bool[DriverSound] mDriverSounds;
        ObjectList!(Source, "sNode") mSources;

        //MusicState mExpectedMusicState;
        //bool mExpectMusicStop;

        float mVolume = 1.0f;
        float[SoundType.max] mTypeVolume = 1.0f;
    }

    this() {
        mSources = new typeof(mSources);
        mDriver = new NullSound(this, null);
    }

    //disassociate from current sound driver
    //all DriverSounds must have been released
    public void close() {
        if (!available())
            return;
        assert(mDriverSounds.length == 0);
        //Trace.formatln("destroy");
        mDriver.destroy();
        mDriver = new NullSound(this, null);
    }

    //save audio-state before all DriverSounds are free'd and close()/reinit()
    //is called
    public void beforeKill() {
        //Time d;
        //mDriver.musicGetState(mExpectedMusicState, d);
    }

    //associate with new sound driver
    public void reinit(SoundDriver driver) {
        //replace old driver by the dummy driver and overwrite that one
        close();
        mDriver = driver;

        //if (mCurrentMusic) {
            //restore music state (for now, only playing/paused, not the time)
            /*if (mSavedMusicState != MusicState.Stopped) {
                mCurrentMusic.play();
                mCurrentMusic.state = mSavedMusicState; //possibly paused
            }*/
        //}
    }

    ///call this in main loop to update the sound system
    public void tick() {
        mDriver.tick();
        foreach (s; mSources) {
            s.tick();
        }
        /*Time pos;
        MusicState mstate;
        mDriver.musicGetState(mstate, pos);
        if (mstate != mExpectedMusicState && mCurrentMusic
            && !(mstate == MusicState.Stopped && mExpectMusicStop))
        {
            assert(mstate == mCurrentMusic.state());
            //only happens if the driver was reinitialized or if the music
            //DriverSound was (temporarily destroyed)
            //Trace.formatln("fixup music state {} -> {}",
              //  cast(int)mstate, cast(int)mExpectedMusicState);
            mCurrentMusic.state = mExpectedMusicState;
        }*/
    }

    ///create music/samples from stream
    ///the ownership of st completely goes to the framework, and it might be
    ///accessed at any time (Music: for streaming, Sample: in case the driver
    ///is reloaded)
    ///yes, it is silly, and I don't even know when st will definitely be closed
    ///xxx: ok, changed to a filename; class FileSystem is used to open it
    /// this shouldn't have any disadvantages
    //public Music createMusic(char[] filename) {
    //    return new Music(this, filename);
    //}
    public Sample createSample(char[] filename, SoundType type = 0,
        bool streamed = false)
    {
        return new Sample(this, filename, type, streamed);
    }

    ///set global volume (also see setTypeVolume)
    void volume(float value) {
        mVolume = clampRangeC(value, 0f, 1f);
        foreach (s; mSources) {
            s.updateVolume();
        }
    }
    float volume() {
        return mVolume;
    }

    ///set volume for a specific sample type
    ///actual source volume: <global> * <type volume> * <source volume>
    void setTypeVolume(SoundType v, float value) {
        mTypeVolume[v] = clampRangeC(value, 0f, 1f);
        foreach (s; mSources) {
            s.updateVolume();
        }
    }
    float getTypeVolume(SoundType v) {
        return mTypeVolume[v];
    }

    ///currently playing music, may be null if no music is set
    //public Music currentMusic() {
    //    return mCurrentMusic;
    //}

    ///if this is a real sound device (false when this is a null-driver)
    public bool available() {
        assert(!!mDriver);
        return cast(NullSound)mDriver is null;
    }

    ///context for playing a Sample
    public Source createSource() {
        return new Source(this);
    }

    package DriverSound createDriverSound(DriverSoundData d) {
        DriverSound res = mDriver.loadSound(d);
        //expect a new instance
        assert(!(res in mDriverSounds));
        mDriverSounds[res] = true;
        return res;
    }

    package void killDriverSound(inout DriverSound sound) {
        if (!sound)
            return;
        assert(sound in mDriverSounds);
        mDriverSounds.remove(sound);
        mDriver.closeSound(sound);
        sound = null;
    }
}

///common class for all sounds
///sounds can still be streamed if set in the constructor (a streamed sound may
///  only be playing once at a time)
public class Sample {
    protected {
        Sound mParent;
        DriverSoundData mSource;
        DriverSound mSound;
        SoundType mType;
    }

    ///type: only for setting type-specific volume; you can use any value
    this(Sound parent, char[] filename, SoundType type, bool streamed = false) {
        assert(!!parent);
        mParent = parent;
        mSource.filename = filename;
        mSource.streamed = streamed;
        mType = type;
        gSounds.add(this);
    }

    Sound parent() {
        return mParent;
    }

    private DriverSound getDriverSound() {
        if (!mSound) {
            //xxx error handling?
            mSound = mParent.createDriverSound(mSource);
        }
        return mSound;
    }

    //destroy driver sound
    //force=even when in use (=> user can hear it)
    bool release(bool force) {
        if (!mSound)
            return false;
        mParent.killDriverSound(mSound);
        mSound = null;
        return true;
    }

    private void doFree(bool finalizer) {
        SoundKillData k;
        k.sound = mSound;
        mSound = null;
        if (!finalizer) {
            k.doFree();
            k = k.init;
        }
        gSounds.remove(this, finalizer, k);
    }

    ~this() {
        doFree(true);
    }

    ///close the sample/music (and stop if active)
    void dclose() {
        release(true);
    }

    ///get length of this sample/music stream
    Time length() {
        return getDriverSound().length();
    }

    ///type for specific volume level
    SoundType type() {
        return mType;
    }

    ///Create a source with this sample assigned to it
    Source createSource() {
        Source s = parent().createSource();
        s.sample = this;
        return s;
    }

    ///play the sample on a new source
    ///redundant helper function
    Source play() {
        Source s = createSource();
        s.play();
        return s;
    }
}

///a Source is an object that manages how a Sample is played
///this is not necessarily equal to a real channel (like a channel in SDL_mixer)
///  instead, when play() is called, this will try allocate a real channel
///  when the sound sample is played in a loop, this will continue to try to get
///  a real channel (through the tick() method)
///a Source can only play one Sample at a time
class Source {
    private {
        //moved here from DriverChannel -> less driver code
        enum FadeType {
            none,
            fadeIn,
            fadeOut,
        }
        FadeType mFading;
        Time mFadeStart, mFadeLength;

        Sound mParent;
        Sample mSample;
        bool mLooping;
        float mVolume = 1.0f;
        DriverChannel mDC;
        PlaybackState mState;  //the state wanted by the user
    }
    ObjListNode!(typeof(this)) sNode;

    SoundSourceInfo info;

    this(Sound base) {
        assert(!!base);
        mParent = base;
        mParent.mSources.add(this);
    }

    ///stop playing and release this Source
    void close() {
        stop();
        mParent.mSources.remove(this);
    }

    ///assigned Sample (even valid if playback has finished)
    final Sample sample() {
        return mSample;
    }
    ///assign a sample
    ///if this Source is playing, playback will be stopped
    final void sample(Sample s) {
        stop();
        mSample = s;
    }

    ///if true, the sound will play forever (it will also be restarted
    ///  on driver reload, or on channel shortage)
    final bool looping() {
        return mLooping;
    }
    final void looping(bool l) {
        mLooping = l;
    }

    ///Private volume for this source
    ///Relative to global volume settings
    final float volume() {
        return mVolume;
    }
    final void volume(float value) {
        mVolume = clampRangeC(value, 0f, 1f);
        updateVolume();
    }

    ///play current Sample on this Source
    ///plays from position start, fading in over fadeinTime
    ///possibly cancels currently playing Sample
    void play(Time start = Time.Null, Time fadeinTime = Time.Null) {
        assert(!!mSample);
        auto dc = createDC(false);
        //first try to resume playback if Source was paused
        if (dc && dc.state == PlaybackState.paused) {
            //resume
            dc.paused = false;
            mState = PlaybackState.playing;
            return;
        }
        //next, try to allocate a channel and start playback
        if (!dc)
            dc = createDC();
        if (dc) {
            dc.setPos(info);
            if (fadeinTime == Time.Null) {
                mFading = FadeType.none;
                updateVolume();
            } else {
                //fading in, so start silent
                dc.setVolume(0);
                startFade(FadeType.fadeIn, fadeinTime);
            }

            //xxx mLooping is only passed here, setting it after the play()
            //    call has no effect
            dc.play(mSample.getDriverSound(), mLooping, start);
            mState = PlaybackState.playing;
        }
    }

    //initiate fadein/fadeout
    private void startFade(FadeType t, Time fTime) {
        mFading = t;
        mFadeStart = timeCurrentTime();
        mFadeLength = fTime;
    }

    void paused(bool p) {
        auto dc = createDC(false);
        if (!dc)
            return;
        if (p && mState == PlaybackState.playing) {
            //going from playing to paused
            if (dc.state == PlaybackState.playing)
                dc.paused = true;
            mState = PlaybackState.paused;
        } else if (!p && mState == PlaybackState.paused) {
            //going from paused to playing
            if (dc.state == PlaybackState.paused)
                dc.paused = false;
            mState = PlaybackState.playing;
        }
    }

    ///stop playback
    void stop(Time fadeOut = Time.Null) {
        if (fadeOut == Time.Null) {
            //stop now
            mFading = FadeType.none;
            if (auto dc = createDC(false)) {
                dc.stop(true);
            }
            mState = PlaybackState.stopped;
        } else {
            //start fading out
            startFade(FadeType.fadeOut, fadeOut);
            mState = PlaybackState.stopping;
        }
    }

    ///Returns actual state of playback
    //Returned value may be different from mState
    PlaybackState state() {
        if (!mSample)
            return PlaybackState.stopped;
        auto dc = createDC(false);
        if (!dc || dc.state == PlaybackState.stopped)
            return PlaybackState.stopped;
        return mState;
    }

    ///get current playback position
    ///Note: 0 is returned if Driver does not support this, or not playing
    public Time position() {
        auto dc = createDC(false);
        if (!dc || dc.state == PlaybackState.stopped)
            return Time.Null;
        return dc.position();
    }

    private bool dcValid() {
        return mDC && mDC.reserved_for is this
            && mDC.owner is mParent.mDriver;
    }

    //must be called to get the DriverChannel instead of using mDC
    //can still return null, if channel shortage or dummy sound driver
    private DriverChannel createDC(bool recreate = true) {
        if (!dcValid()) {
            mDC = recreate ? mParent.mDriver.getChannel(this) : null;
            if (mDC)
                assert(dcValid());
        }
        return mDC;
    }

    ///should be called on each frame, copies the position value and also makes
    ///sure a looping sample is played when 1. there was a channel shortage and
    ///2. if the driver was reloaded
    //(in other words, this interface sucks)
    //(not looped samples are not "retried" to play again)
    private void tick() {
        //update position if still playing
        if (auto dc = createDC(false)) {
            dc.setPos(info);
            if (mFading != FadeType.none)
                updateVolume();
        }
        if (!mLooping || !mSample)
            return;
        if (!dcValid() && mState == PlaybackState.playing) {
            //restart
            play();
        }
    }

    //Called by Sound, as result of a setVolume() call, or from tick() when
    //  fade-in/fade-out in progress
    private void updateVolume() {
        auto dc = createDC(false);
        if (!dc)
            return;

        //The volume level without fading:
        //  <global volume> * <sound-type specific volume> * <Source volume>
        float baseVol = mParent.mVolume * mParent.mTypeVolume[mSample.type]
            * mVolume;
        float fadeVol = 1.0f;

        if (mFading == FadeType.fadeIn) {
            //Fading in
            Time d = timeCurrentTime() - mFadeStart;
            if (d < mFadeLength) {
                fadeVol = d.secsf()/mFadeLength.secsf();
            } else {
                mFading = FadeType.none;
            }
        } else if (mFading == FadeType.fadeOut) {
            //Fading out
            Time d = timeCurrentTime() - mFadeStart;
            if (d < mFadeLength) {
                fadeVol = 1.0f - d.secsf()/mFadeLength.secsf();
            } else {
                fadeVol = 0f;
                stop();
                mFading = FadeType.none;
            }
        }
        dc.setVolume(baseVol * fadeVol);
    }
}

///sound driver which does nothing
class NullSound : SoundDriver {
    this(Sound base, ConfigNode config) {
    }

    DriverChannel getChannel(Object reserve_for) {
        return null;
    }

    void tick() {
    }

    class NullSoundSound : DriverSound {
        Time length() {
            return Time.Null;
        }
    }

    DriverSound loadSound(DriverSoundData data) {
        return new NullSoundSound();
    }

    void closeSound(DriverSound s) {
    }

    void destroy() {
    }
    static this() {
        SoundDriverFactory.register!(typeof(this))("null");
    }
}

alias StaticFactory!("SoundDrivers", SoundDriver, Sound, ConfigNode)
    SoundDriverFactory;







/*
///music is, other than samples, streamed on playback
///only one music stream can play at a time
public class Music : SoundBase {
    this(Sound parent, char[] filename) {
        super(parent, SoundType.music, filename);
    }

    ///play music from position start, fading in over fadeinTime
    ///returns immediately
    ///only one Music at a time can be playing
    public void play(Time start = Time.Null,
        Time fadeinTime = Time.Null)
    {
        DriverSound snd = getDriverSound();
        mParent.mCurrentMusic = this;
        mParent.mExpectedMusicState = MusicState.Playing;
        mParent.mExpectMusicStop = false;
        mParent.mDriver.musicPlay(snd, start, fadeinTime);
    }

    bool isCurrent() {
        return (mParent.mCurrentMusic is this);
    }

    public MusicState state() {
        if (!isCurrent())
            return MusicState.Stopped;
        MusicState s;
        Time t;
        mParent.mDriver.musicGetState(s, t);
        return s;
    }

    public void state(MusicState set) {
        if (isCurrent() && state() != MusicState.Stopped) {
            if (set == MusicState.Stopped) {
                mParent.mCurrentMusic = null;
                mParent.mDriver.musicPlay(null, Time.Null, Time.Null);
            } else {
                mParent.mDriver.musicPause(set == MusicState.Paused);
            }
            mParent.mExpectedMusicState = set;
        } else {
            if (set == MusicState.Playing) {
                play();
            }
        }
    }

    ///pause/resume music, if playing
    ///if it was not playing and p is true, play() is tiggered
    public void paused(bool p) {
        state = p ? MusicState.Paused : MusicState.Playing;
    }

    ///stop the music, if it is playing
    ///Note: after this call, Sound.currentMusic will be null
    public void stop() {
        state = MusicState.Stopped;
    }

    ///Fade out music over fadeTime
    ///returns immediately
    ///Note: Sound.currentMusic is not affected
    public void fadeOut(Time fadeTime) {
        if (!isCurrent())
            return;
        mParent.mDriver.musicFadeOut(fadeTime);
        //silly silly
        mParent.mExpectMusicStop = true;
    }

    ///get current playback position
    public Time position() {
        if (!isCurrent())
            return Time.Null;
        MusicState s;
        Time t;
        mParent.mDriver.musicGetState(s, t);
        return t;
    }
}
*/
