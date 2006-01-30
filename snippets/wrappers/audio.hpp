#ifndef _audio_hpp_
#define _audio_hpp_
#include <SDL/SDL.h>
#include <SDL/SDL_mixer.h>

#define AUDIO_CHANNELS 16

typedef Mix_Chunk Audio_Sample;
typedef Mix_Music Audio_Music;

/** \brief class for playing audio out of physfs archives
 * Make sure filesystem is initialized before loading samples/music
 * (FS does not need to be initialized for AudioSystem instanciation)
 */
class AudioSystem
{
  public:
    /** \brief Get singleton instance of AudioSystem
     *
     */
    static AudioSystem* inst();

    /** \brief Close mixer and delete singleton instance
     * This is used to clean up on program exit
     */
    static void closeAudio();

    /** \brief Set Volume for audio played as sample
     * \param newVolume The new sample volume, 0.0f is silent, 1.0f is full
     */
    void setSFXVolume(const float newVolume);

    /** \brief Set Volume for audio played as music
     * \param newVolume The new music volume, 0.0f is silent, 1.0f is full
     */
    void setMusicVolume(const float newVolume);

    /** \brief Set distance of listener to audio plane
     * \param newDistance The new distance of the listener to the audio plane,
     *        in geom. units.
     *        A realistic value is the viewport width in pixels.
     */
    void setListenerDistance(const int newDistance);

    /** \brief Set width of audio plane
     * \param newWidth New width of the audio plane, in geom. units.
     *        Note that sounds that are more than newDistance/2 away from
     *        listener pos. are silent, so consider making this a
     *        little larger than the space where you would like to hear sound.
     *        Only affects sound volume, not positioning
     */
    void setAudioPlaneWidth(const int newWidth);

    /** \brief X position of listener over audio plane
     * Set the x position from where the listener is currently viewing the
     * plane where sound is generated
     * \param newPosX The new listener position, in geom. units
     *        Note: no particular 0 point, but MUST be the same as
     *        xPos on playSample(), e.g when you set listener pos
     *        relative to audio plane center, do the same with xPos
     */
    void setListenerPosX(const int newPosX);

    /** \brief Load a sample from the mounted physfs paths
     *
     */
    Audio_Sample* loadSample(const char* fileName);

    /** \brief Stop a sample on every channel its currently playing on
     *
     */
    void stopSample(const Audio_Sample* sample);

    /** \brief Free a sample loaded with loadsample()
     * \param doStopPlay Set to have the sample stopped if it could still be playing
     */
    void freeSample(Audio_Sample* sample, const int doStopPlay);

    /** Play the loaded sample.
     * \param loopCount Number of loops, e.g. 1 means play 2x
     * \param xPos The position of the sound on the audio plane
     *        As above, no particular coord sys, but the same as listenerPos
     */
    void playSample(const Audio_Sample* sample, const int xPos, const int loopCount);

    /** \brief Stops playback on all channels
     *
     */
    void stopAllSamples();

    /** \brief Load music for streaming from a file in physfs paths
     *
     */
    Audio_Music* loadMusic(const char* fileName);

    /** \brief Stop playing music
     *
     */
    void stopMusic();

    /** \brief Free music loaded with loadMusic()
     * If specified music is still playing, it will be stopped
     */
    void freeMusic(Audio_Music* music);

    /** \brief Play loaded music
     * \param loopCount Number of loops, e.g. 1 means play 2x
     */
    void playMusic(const Audio_Music* music, const int loopCount);
  protected:
    AudioSystem();
    virtual ~AudioSystem();
  private:
    static AudioSystem* instance;
    int mChannels;
    int mListenerDist;
    int mAudioPlaneWidth;
    int mListenerPosX;
    double mMaxRightDist;
};

/**
 * Short way to access the AudioSystem singleton instance
 */
#define AudioSys AudioSystem::inst()

#endif // _audio_hpp_
