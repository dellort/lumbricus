#ifndef _filesystem_hpp_
#define _filesystem_hpp_

#include <SDL/SDL.h>
#include <libsdlconfig.hpp>

/** wrapper class for physfs
 * Before accessing other methods, make sure initFilesystem() has been called
 */
class GameFilesystem
{
  public:
    /** \brief create singleton instance of GameFilesystem
     *
     */
    static GameFilesystem* inst();

    /** \brief initialize filesystem
     * Initialize the physfs library with the executable path.
     * Call this before using other methods.
     * \param argv0 command line argument 0 (path to executable)
     */
    void initFilesystem(const char* argv0);

    /** \brief shutdown filesystem
     * Terminates physfs and invalidates all open handles
     */
    void closeFilesystem();

    /** \brief add an archive or directory to search path
     * \param newPhysArch Path to directory or archive, relative to app path,
     *        or absolute
     * \param append if non-zero, adds the new archive to bottom of search list,
     *        (searched top-down)
     * \param mountPoint the path in the virtual FS where the new archive should
     *        be mounted, or NULL to mount in root
     */
    void addToSearchPath(const char* newPhysArch, int append, const char* mountPoint);

    /** \brief set the directory for write access
     * In this directory, all files that are opened for writing are placed
     * \param newPhysDir the new write directory, either relative to app path
     *        or absolute
     */
    int setWriteDir(const char* newPhysDir);

    /** \brief check if a file exists in the virtual FS
     *
     */
    bool fileExists(const char* fileName);

    /** \brief Opens a file for reading, you are responsible for closing it
     *
     */
    SDL_RWops *sdlOpenRead(const char* fileName);

    /** \brief Opens a file for writing, you are responsible for closing it
     * Content of file is overwritten
     */
    SDL_RWops *sdlOpenWrite(const char* fileName);

    /** \brief Opens a file for modifying, you are responsible for closing it
     *
     */
    SDL_RWops *sdlOpenAppend(const char* fileName);

    /**
     * Not implemented
     */
    libsdlconfig::Config *configLoad(const char* fileName);

    /**
     * Not implemented
     */
    void configSave(const char* fileName, libsdlconfig::Config* cfgFile);
  protected:
    GameFilesystem();
  private:
    bool mInitialized;

    static GameFilesystem* instance;
};

/**
 * Short way to access the GameFilesystem singleton instance
 */
#define GameFS GameFilesystem::inst()

#endif /* _filesystem_hpp_ */
