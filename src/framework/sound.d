module framework.sound;

private import
    std.stream,
    utils.time;

public enum Volume {
    music,
    sfx,
}

///main sound class, loads samples and music and sets volume
public class Sound {
    ///call this in main loop to update the sound system
    public abstract void tick();

    ///create music from stream
    ///if ownsStream == true, this class will close the stream when
    ///it is not needed anymore
    ///st is used for streaming after this call
    public abstract Music createMusic(Stream st, bool ownsStream = true);

    ///create sample from stream
    ///if ownsStream == true, this class will close the stream when
    ///it is not needed anymore
    ///sample is loaded from st, which can be closed after this call
    public abstract Sample createSample(Stream st, bool ownsStream = true);

    ///set volume for current music and future samples
    public abstract void setVolume(Volume v, float value);

    ///currently playing music, may be null if no music is playing
    public abstract Music currentMusic();
}

///music is, other than samples, streamed on playback
///only one music stream can play at a time
public class Music {
    ///close (and stop if playing) this music stream
    public abstract void close();

    ///play music from position start, fading in over fadeinTime
    ///returns immediately
    public abstract void play(Time start = timeMusecs(0),
        Time fadeinTime = timeMusecs(0));

    ///pause/resume music, if playing
    public abstract void paused(bool p);

    ///check if this music is currently playing
    public abstract bool playing();

    ///stop the music, if it is playing
    ///Note: after this call, Sound.currentMusic will be null
    public abstract void stop();

    ///Fade out music over fadeTime
    ///returns immediately
    ///Note: Sound.currentMusic is not affected
    public abstract void fadeOut(Time fadeTime);

    ///get current playback position
    public abstract Time position();

    ///get length of the stream
    public abstract Time length();
}

///a sound sample that can be played several times
public class Sample {
    ///close the sample (and stop if active)
    public abstract void close();

    ///play the sample on a free channel
    public abstract void play();
}
