module framework.sound;

import framework.driver_base;
import framework.filesystem;
import framework.globalsettings;
import utils.factory;
import utils.list2;;
import utils.log;
import utils.stream;
import utils.misc;
import utils.time;
import utils.vector2;


//sound type is only used for mixing (e.g. sfx may be louder than music)
//  (esp. this should not influence streaming behaviour)
//NOTE: used to be alias ubyte SoundType;
enum SoundType {
   sfx,
   music,
   other
}

SoundManager gSoundManager;

static this() {
    gSoundManager = new SoundManager;
}

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
abstract class DriverSound : DriverResource {
    abstract Time length();

    //don't interrupt music when doing a "soft" cache release
    override bool isInUse() {
        //xxx: seeking when the sample/music is restarted would be nicer,
        //  because then music would be continuous even if driver is changed
        Sample sample = castStrict!(Sample)(getResource());
        foreach (Source s; gSoundManager.mSources) {
            if (s.sample() is sample && s.state != PlaybackState.stopped)
                return true;
        }
        return false;
    }
}

///a channel is used to play sound effects (but not music, strange, hurrr)
abstract class DriverChannel {
    SoundDriver owner;
    //actually a class Channel or null
    //will be set to null if playback is finished or driver is unloaded etc.
    Object reserved_for;

    abstract void setInfo(ref SoundSourceInfo info);
    //set absolute volume of this channel
    abstract void setVolume(float value);
    //true to loop the played sound (does not have to be supported)
    //implementing note: can be called either before or after play(); both
    //  should work
    abstract void looping(bool loop);

    //play() and stop() must only be called if you're still the owner by
    //reserved_by
    abstract void play(DriverSound s, Time startAt);

    abstract void paused(bool p);

    //unreserve==true: make channel available to others (getChannel())
    abstract void stop(bool unreserve);

    abstract PlaybackState state();

    abstract Time position();
}

//also create DriverSound resources
abstract class SoundDriver : ResDriver {
    //create/get a free channel to play stuff
    //returns null if none available
    //reserve_for: DriverChannel.reserved_for is set to it
    abstract DriverChannel getChannel(Object reserve_for);
}

///main sound class, loads samples and music and sets volume
//NOTE: not overloaded by sound driver anymore
class SoundManager : ResourceManagerT!(SoundDriver) {
    private {
        //Music mCurrentMusic;
        //all loaded sound files (music & samples)
        ObjectList!(Source, "sNode") mSources;

        SettingVar!(float) mVolume;

        SettingVar!(float)[SoundType.max] mTypeVolume;
    }

    this() {
        super("sound");
        mSources = new typeof(mSources);

        SettingVar!(float) addsndval(char[] name) {
            auto res = SettingVar!(float).Add("sound." ~ name, 1.0f);
            res.setting.type = SettingType.Percent;
            res.setting.onChange ~= &change_volume;
            return res;
        }

        mVolume = addsndval("master_volume");

        foreach (int idx, ref tv; mTypeVolume) {
            tv = addsndval(myformat("volume{}", idx));
        }
    }

    DriverSound getDriverSound(Sample s) {
        if (!driver)
            return null;
        return castStrict!(DriverSound)(driver.requireDriverResource(s));
    }

    private void change_volume(Setting v) {
        foreach (s; mSources) {
            s.updateVolume();
        }
    }

    ///call this in main loop to update the sound system
    override void tick() {
        super.tick();
        foreach (s; mSources) {
            s.tick();
        }
    }

    //basically returns the number of hardware channels currently in use
    int activeSources() {
        int cnt;
        foreach (s; mSources) {
            DriverChannel ch = s.createDC(false);
            if (ch) {
                //channel can be assigned, but not in use
                if (ch.state != PlaybackState.stopped)
                    cnt++;
            }
        }
        return cnt;
    }

    ///create music/samples from stream
    ///the ownership of st completely goes to the framework, and it might be
    ///accessed at any time (Music: for streaming, Sample: in case the driver
    ///is reloaded)
    ///yes, it is silly, and I don't even know when st will definitely be closed
    ///xxx: ok, changed to a filename; class FileSystem is used to open it
    /// this shouldn't have any disadvantages
    public Sample createSample(char[] filename, SoundType type = SoundType.init,
        bool streamed = false)
    {
        return new Sample(filename, type, streamed);
    }

    ///set global volume (also see setTypeVolume)
    void volume(float value) {
        mVolume.set(value);
    }
    float volume() {
        return clampRangeC(mVolume.get(), 0.0f, 1.0f);
    }

    ///set volume for a specific sample type
    ///actual source volume: <global> * <type volume> * <source volume>
    void setTypeVolume(SoundType v, float value) {
        mTypeVolume[v].set(value);
    }
    float getTypeVolume(SoundType v) {
        return clampRangeC(mTypeVolume[v].get(), 0.0f, 1.0f);
    }

    ///if this is a real sound device (false when this is a null-driver)
    public bool available() {
        return driver && !cast(NullSound)driver;
    }

    ///context for playing a Sample
    public Source createSource() {
        return new Source();
    }
}

///common class for all sounds
///sounds can still be streamed if set in the constructor (a streamed sound may
///  only be playing once at a time)
class Sample : ResourceT!(DriverSound) {
    protected {
        DriverSoundData mSource;
        SoundType mType;
    }

    ///type: only for setting type-specific volume; you can use any value
    this(char[] filename, SoundType type, bool streamed = false) {
        //note that the file is only actually loaded by the driver, and may fail
        //  there; Source.play() will catch the CustomException thrown by load
        //  failure in this case, and display the user an error message
        gFS.mustExist(filename);

        mSource.filename = filename;
        mSource.streamed = streamed;
        mType = type;
    }

    char[] name() {
        return mSource.filename;
    }

    DriverSoundData data() {
        return mSource;
    }

    ///close the sample/music (and stop if active)
    void dclose() {
        unload();
    }

    ///get length of this sample/music stream
    Time length() {
        DriverSound ds = gSoundManager.getDriverSound(this);
        return ds ? ds.length() : Time.Null;
    }

    ///type for specific volume level
    SoundType type() {
        return mType;
    }

    ///Create a source with this sample assigned to it
    Source createSource() {
        Source s = gSoundManager.createSource();
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
///Warning: not garbage collected; must be released with close()
/// also, particles.d stores Source in C-memory (not scanned by the GC); if
//  that's a problem, particles.d should just be reverted to allocate D-memory
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

        Sample mSample;
        bool mLooping;
        float mVolume = 1.0f;
        DriverChannel mDC;
        PlaybackState mState;  //the state wanted by the user
    }
    ObjListNode!(typeof(this)) sNode;

    SoundSourceInfo info;

    this() {
        gSoundManager.mSources.add(this);
    }

    ///stop playing and release this Source
    void close() {
        stop();
        gSoundManager.mSources.remove(this);
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
        auto dc = createDC(false);
        if (dc)
            dc.looping = l;
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
        argcheck(mSample);
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
            dc.setInfo(info);
            if (fadeinTime == Time.Null) {
                mFading = FadeType.none;
                updateVolume();
            } else {
                //fading in, so start silent
                dc.setVolume(0);
                startFade(FadeType.fadeIn, fadeinTime);
            }
            dc.looping = mLooping;

            try {
                dc.play(gSoundManager.getDriverSound(mSample), start);
                mState = PlaybackState.playing;
            //may get FilesystemException or FrameworkException if the file was
            //  not found/couldn't be opened
            } catch (CustomException e) {
                gLog.error("couldn't play sound {}", mSample.name);
                mState = PlaybackState.stopped;
            }
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
            && mDC.owner && mDC.owner is gSoundManager.driver;
    }

    //must be called to get the DriverChannel instead of using mDC
    //can still return null, if channel shortage or dummy sound driver
    private DriverChannel createDC(bool recreate = true) {
        if (!dcValid()) {
            mDC = null;
            auto drv = gSoundManager.driver;
            if (recreate)
                mDC = drv ? drv.getChannel(this) : null;
        }
        if (mDC)
            assert(dcValid());
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
            dc.setInfo(info);
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
        float baseVol = gSoundManager.volume
            * gSoundManager.getTypeVolume(mSample.type) * mVolume;
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
    this() {
    }

    override DriverResource createDriverResource(Resource res) {
        return null;
    }

    DriverChannel getChannel(Object reserve_for) {
        return null;
    }

    static this() {
        registerFrameworkDriver!(typeof(this))("sound_none");
    }
}
