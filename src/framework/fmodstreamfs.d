module framework.fmodstreamfs;

//Some callback functions to connect D streams to FMOD file functions

private import
    derelict.fmod.fmod,
    utils.stream;

void FMODSetStreamFs(FMOD_SYSTEM* sys, bool enable) {
    if (enable) {
        FMOD_ErrorCheck(FMOD_System_SetFileSystem(sys, &fmodFileOpenCallback,
            &fmodFileCloseCallback, &fmodFileReadCallback,
            &fmodFileSeekCallback, 2048));
    } else {
        FMOD_ErrorCheck(FMOD_System_SetFileSystem(sys, null, null, null, null,
            2048));
    }
}

extern(System):

FMOD_RESULT fmodFileOpenCallback(char *name, int unicode, uint *filesize,
    void **handle, void **userdata)
{
    try {
        Object o = cast(Object)name; //eh???
        Stream st = cast(Stream)o;
        *filesize = cast(uint)st.size();
        *handle = cast(void*)st;
        *userdata = null;
        return FMOD_OK;
    } catch(IOException e) {
        return FMOD_ERR_INVALID_PARAM;
    }
}

FMOD_RESULT fmodFileCloseCallback(void *handle, void *userdata) {
    //stream is freed by user
    return FMOD_OK;
}

FMOD_RESULT fmodFileReadCallback(void *handle, void *buffer, uint sizebytes,
    uint *bytesread, void *userdata)
{
    try {
        Stream st = cast(Stream)handle;
        ubyte[] read = st.readUntilEof(cast(ubyte[])buffer[0..sizebytes]);
        *bytesread = read.length;
        //by the way: ...eh what the fuck is this?
        if (*bytesread < sizebytes)
            return FMOD_ERR_FILE_EOF;
        return FMOD_OK;
    } catch(IOException e) {
        return FMOD_ERR_INVALID_PARAM;
    }
}

FMOD_RESULT fmodFileSeekCallback(void *handle, uint pos, void *userdata) {
    try {
        Stream st = cast(Stream)handle;
        //xxx: setting bogus position doesn't throw exceptions
        //     so FMOD_ERR_INVALID_PARAM will never be returned, that ok?
        st.position = pos;
        return FMOD_OK;
    } catch(IOException e) {
        return FMOD_ERR_INVALID_PARAM;
    }
}
