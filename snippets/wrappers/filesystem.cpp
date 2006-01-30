#include "filesystem.hpp"
#include "physfsrwops.h"
#include <physfs.h>
#include <assert.h>

GameFilesystem * GameFilesystem::instance = 0;

GameFilesystem * GameFilesystem::inst()
{
    if (instance == 0)
        instance = new GameFilesystem();
    return instance;
}

GameFilesystem::GameFilesystem()
        :mInitialized(false)
{
//
}

void GameFilesystem::initFilesystem(const char* argv0)
{
    PHYSFS_init(argv0);
    mInitialized = true;
}

void GameFilesystem::closeFilesystem()
{
    mInitialized = false;
    PHYSFS_deinit();
}

void GameFilesystem::addToSearchPath(const char* newPhysArch, int append, const char* mountPoint)
{
    assert(mInitialized);
    PHYSFS_mount(newPhysArch, mountPoint, append);
}

bool GameFilesystem::fileExists(const char* fileName)
{
    assert(mInitialized);
    return PHYSFS_exists(fileName);
}

int GameFilesystem::setWriteDir(const char* newPhysDir)
{
    return PHYSFS_setWriteDir(newPhysDir);
}

SDL_RWops * GameFilesystem::sdlOpenRead(const char* fileName)
{
    assert(mInitialized);
    return PHYSFSRWOPS_openRead(fileName);
}

SDL_RWops * GameFilesystem::sdlOpenWrite(const char* fileName)
{
    assert(mInitialized);
    return PHYSFSRWOPS_openWrite(fileName);
}

SDL_RWops * GameFilesystem::sdlOpenAppend(const char* fileName)
{
    assert(mInitialized);
    return PHYSFSRWOPS_openAppend(fileName);
}

libsdlconfig::Config * GameFilesystem::configLoad(const char* fileName)
{
  //TODO
}

void GameFilesystem::configSave(const char* fileName, libsdlconfig::Config* cfgFile)
{
  //TODO
}

