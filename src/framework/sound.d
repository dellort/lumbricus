module framework.sound;

private import
    utils.stream,
    utils.time;
import framework.framework, utils.configfile, utils.factory, utils.time,
    utils.vector2, utils.weaklist;

public enum SoundType {
    error,
    music,
    sfx,
}

public enum MusicState {
    Stopped,
    Playing,
    Paused
}

//some data about the object the sound is attached to
//the mixer can use this to make sound more realistic according to the object's
//position/movement
struct SoundSourcePosition {
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
    WeakList!(SoundBase, SoundKillData) gSounds;
}

///audio data (or rather, how it can be loaded)
///[the stream data is owned by the Sound class; and as long a DriverSound is
///allocated with this DriverSoundData, the DriverSound can assume it's the
///only code which reads/seeks the Stream
///probably a smarter way would be to store the filename instead of the stream]
struct DriverSoundData {
    char[] filename;
    SoundType type;
}

///handle for any sound data (samples and music)
///DriverSoundData is used to create this!
//(unifying smaples and music simplifies memory managment)
abstract class DriverSound {
    abstract SoundType type();
    abstract Time length();
}

///a channel is used to play sound effects (but not music, strange, hurrr)
abstract class DriverChannel {
    SoundDriver owner;
    //actually a class Channel or null
    //will be set to null if playback is finished or driver is unloaded etc.
    Object reserved_for;

    abstract void setPos(ref SoundSourcePosition pos);

    //play() and stop() must only be called if you're still the owner by
    //reserved_by
    abstract void play(DriverSound s, bool loop);
    //unreserve==true: make channel available to others (getChannel())
    abstract void stop(bool unreserve);
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

    abstract void setVolume(SoundType v, float value);

    abstract void destroy();

    //only one Music per time -> need only a  simple per-driver interface for it
    //m==null: reset
    abstract void musicPlay(DriverSound m, Time startAt, Time fade);
    abstract void musicFadeOut(Time fadetime);
    abstract void musicGetState(out MusicState state, out Time pos);
    abstract void musicPause(bool pause);
}

///main sound class, loads samples and music and sets volume
//NOTE: not overloaded by sound driver anymore
public class Sound {
    private {
        Music mCurrentMusic;
        SoundDriver mDriver;
        //all loaded sound files (music & samples)
        bool[DriverSound] mDriverSounds;

        MusicState mExpectedMusicState;
        bool mExpectMusicStop;
    }

    this() {
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

        if (mCurrentMusic) {
            //restore music state (for now, only playing/paused, not the time)
            /*if (mSavedMusicState != MusicState.Stopped) {
                mCurrentMusic.play();
                mCurrentMusic.state = mSavedMusicState; //possibly paused
            }*/
        }
    }

    ///call this in main loop to update the sound system
    public void tick() {
        mDriver.tick();
        Time pos;
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
        }
    }

    ///create music/samples from stream
    ///the ownership of st completely goes to the framework, and it might be
    ///accessed at any time (Music: for streaming, Sample: in case the driver
    ///is reloaded)
    ///yes, it is silly, and I don't even know when st will definitely be closed
    ///xxx: ok, changed to a filename; class FileSystem is used to open it
    /// this shouldn't have any disadvantages
    public Music createMusic(char[] filename) {
        return new Music(this, filename);
    }
    public Sample createSample(char[] filename) {
        return new Sample(this, filename);
    }

    ///set volume for current music and future samples
    public void setVolume(SoundType v, float value) {
        mDriver.setVolume(v, value);
    }

    ///currently playing music, may be null if no music is set
    public Music currentMusic() {
        return mCurrentMusic;
    }

    ///if this is a real sound device (false when this is a null-driver)
    public bool available() {
        assert(!!mDriver);
        return cast(NullSound)mDriver is null;
    }

    ///context for playing a Sample
    public Channel createChannel() {
        return new Channel(this);
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

///common baseclass for Music and Sample
public class SoundBase {
    protected {
        Sound mParent;
        DriverSoundData mSource;
        DriverSound mSound;
    }

    this(Sound parent, SoundType type, char[] filename) {
        assert(!!parent);
        mParent = parent;
        mSource.filename = filename;
        mSource.type = type;
        gSounds.add(this);
    }

    Sound parent() {
        return mParent;
    }

    DriverSound getDriverSound() {
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
    public void dclose() {
        release(true);
    }

    ///get length of this sample/music stream
    public Time length() {
        return getDriverSound().length();
    }
}

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

///a sound sample that can be played several times
public class Sample : SoundBase {
    this(Sound parent, char[] filename) {
        super(parent, SoundType.sfx, filename);
    }

    ///play the sample on a free channel
    ///redundant helper function
    public void play() {
        Channel ch = parent().createChannel();
        ch.play(this);
    }
}

///a Channel is an object that manages how a Sample is played
///this is not necessarily equal to a real channel (like a channel in SDL_mixer)
///instead, when play() is called, this will try allocate a real channel
///when the sound sample is played in a loop, this will continue to try to get
///a real channel (through the tick() method)
class Channel {
    private {
        Sound mParent;
        Sample mSample;
        bool mLooping;
        DriverChannel mDC;
    }

    this(Sound base) {
        assert(!!base);
        mParent = base;
    }

    SoundSourcePosition position;

    ///last played Sample (even valid if playback has finished)
    final Sample sample() {
        return mSample;
    }

    ///play a Sample on this Channel
    ///possibly cancel currently playing Sample
    /// looping = if true, playback never stops unless stop() is called
    void play(Sample s, bool looping = false) {
        mSample = s;
        mLooping = looping;
        if (auto dc = createDC()) {
            dc.setPos(position);
            dc.play(mSample.getDriverSound(), mLooping);
        }
    }

    ///stop playback
    void stop() {
        mLooping = false;
        if (auto dc = createDC(false)) {
            dc.stop(true);
        }
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
                assert(mDC.reserved_for is this);
        }
        return mDC;
    }

    ///should be called on each frame, copies the position value and also makes
    ///sure a looping sample is played when 1. there was a channel shortage and
    ///2. if the driver was reloaded
    //(in other words, this interface sucks)
    //(not looped samples are not "retried" to play again)
    void tick() {
        //update position if still playing
        if (auto dc = createDC(false)) {
            dc.setPos(position);
        }
        if (!mLooping || !mSample)
            return;
        if (!dcValid()) {
            //restart
            play(mSample, mLooping);
        }
    }
}

///sound driver which does nothing
class NullSound : SoundDriver {
    MusicState mustate;

    this(Sound base, ConfigNode config) {
    }

    DriverChannel getChannel(Object reserve_for) {
        return null;
    }

    void tick() {
    }

    class NullSoundSound : DriverSound {
        SoundType mtype;
        SoundType type() {
            return mtype;
        }
        Time length() {
            return Time.Null;
        }
    }

    DriverSound loadSound(DriverSoundData data) {
        auto snd = new NullSoundSound();
        snd.mtype = data.type;
        return snd;
    }

    void closeSound(DriverSound s) {
    }

    void setVolume(SoundType v, float value) {
    }

    void destroy() {
    }

    void musicPlay(DriverSound m, Time startAt, Time fade) {
        mustate = m ? MusicState.Playing : MusicState.Stopped;
    }
    void musicFadeOut(Time fadetime) {
    }
    void musicGetState(out MusicState state, out Time pos) {
        pos = Time.Null;
        state = mustate;
    }
    void musicPause(bool pause) {
        if (mustate == MusicState.Stopped)
            return;
        mustate = pause ? MusicState.Paused : MusicState.Playing;
    }

    static this() {
        SoundDriverFactory.register!(typeof(this))("null");
    }
}

alias StaticFactory!("SoundDrivers", SoundDriver, Sound, ConfigNode)
    SoundDriverFactory;
