#include "audio.hpp"
#include "filesystem.hpp"
#include <math.h>

AudioSystem * AudioSystem::instance = 0;

AudioSystem * AudioSystem::inst()
{
  if (!instance)
    instance = new AudioSystem();
  return instance;
}

void AudioSystem::closeAudio()
{
  if (instance)
    delete instance;
  instance = NULL;
}

AudioSystem::AudioSystem()
{
  mChannels = AUDIO_CHANNELS;

  //set some geometry defaults
  setListenerDistance(50);    //50 distance to audio plane
  setListenerPosX(0);         //center of audio plane
  setAudioPlaneWidth(2*255);  //255 in each direction

	// Init SDL_Mixer
	if (Mix_OpenAudio(44100, MIX_DEFAULT_FORMAT, 2, 2048) < 0)
	{
	  throw Mix_GetError();
	}
  Mix_AllocateChannels(mChannels);
  setSFXVolume(70);
  setMusicVolume(70);
}

AudioSystem::~AudioSystem()
{
 	Mix_CloseAudio();
}

void AudioSystem::setSFXVolume(const float newVolume)
{
  int v = (int)(newVolume*MIX_MAX_VOLUME);
  v = (v<0)?0:(v>MIX_MAX_VOLUME)?MIX_MAX_VOLUME:v;
  Mix_Volume(-1,v);
}

void AudioSystem::setMusicVolume(const float newVolume)
{
  int v = (int)(newVolume*MIX_MAX_VOLUME);
  v = (v<0)?0:(v>MIX_MAX_VOLUME)?MIX_MAX_VOLUME:v;
  Mix_VolumeMusic(v);
}

void AudioSystem::setListenerDistance(const int newDistance)
{
  mListenerDist = (newDistance<0)?0:newDistance;
}

void AudioSystem::setAudioPlaneWidth(const int newWidth)
{
  mAudioPlaneWidth = (newWidth<0)?0:newWidth;
}

void AudioSystem::setListenerPosX(const int newPosX)
{
  mListenerPosX = newPosX;
}

Audio_Sample * AudioSystem::loadSample(const char* fileName)
{
  //TODO: Add some more error checking
  Mix_Chunk* sample = Mix_LoadWAV_RW(GameFS->sdlOpenRead(fileName), 1);
  if (!sample)
  {
    throw Mix_GetError();
  }
  return sample;
}

void AudioSystem::stopSample(const Audio_Sample* sample)
{
  //walk through channels and stop everyone thats playing sample
  for (int i=0; i<mChannels; i++)
  {
    Mix_Chunk* curChunk = Mix_GetChunk(i);
    if (curChunk == sample)
    {
      Mix_HaltChannel(i);
    }
  }
}

void AudioSystem::freeSample(Audio_Sample* sample, const int doStopPlay)
{
  if (doStopPlay)
  {
    stopSample(sample);
  }
  Mix_FreeChunk(sample);
  sample = NULL;
}

void AudioSystem::playSample(const Audio_Sample* sample, const int xPos, const int loopCount)
{
  //TODO: really except when playback fails, or just keep quiet?
  int channel = Mix_PlayChannel(-1, (Mix_Chunk*)sample, loopCount);
  if (channel < 0)
  {
    throw Mix_GetError();
  } else {
    int d = xPos - mListenerPosX;   //distance sound.x to listener.x
    //diagonal distance listener-sound, scaled to 0-255
    int dist = (int)(255*sqrt(d*d+mListenerDist*mListenerDist)/sqrt((float)(mAudioPlaneWidth*mAudioPlaneWidth)/4+mListenerDist*mListenerDist));
    dist = (dist>255)?255:dist;   //cut off at 255
    //angle between (listener, listener on audioplane) and (listener, sound)
    float angle = atan((float)d/(float)mListenerDist)*180/M_PI;

    //printf("%d %d %f\n", d, dist, angle);
    Mix_SetPosition(channel, (int)angle, dist);
  }
}

void AudioSystem::stopAllSamples()
{
  Mix_HaltChannel(-1);
}

Audio_Music * AudioSystem::loadMusic(const char* fileName)
{
  //TODO: add even more error checking
  Mix_Music* music = Mix_LoadMUS_RW(GameFS->sdlOpenRead(fileName));
  if (!music)
  {
    throw Mix_GetError();
  }
  return music;
}

void AudioSystem::stopMusic()
{
	if( Mix_PlayingMusic() )
	{
    Mix_HaltMusic();
	}
}

void AudioSystem::freeMusic(Audio_Music* music)
{
  if (music)
  {
    Mix_FreeMusic(music);
  }
  music = NULL;
}

void AudioSystem::playMusic(const Audio_Music* music, const int loopCount)
{
  //TODO: Should we really throw exception here?
  if (Mix_PlayMusic((Mix_Music*)music, loopCount+1) < 0)
  {
    throw Mix_GetError();
  }
}

