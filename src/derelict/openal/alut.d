//incomplete alut-binding (I didn't find a _recent_ and derelict one on dsource)
//converted from freealut's alut.h
module derelict.openal.alut;

import derelict.util.loader;
import derelict.openal.altypes;

enum {
    ALUT_ERROR_NO_ERROR = 0,
}

extern(C) {
    typedef ALboolean function(int*, char**) pfalutInit;
    typedef ALboolean function(int*, char**) pfalutInitWithoutContext;
    typedef ALboolean function() pfalutExit;
    typedef ALenum function() pfalutGetError;
    typedef char* function(ALenum) pfalutGetErrorString;
    typedef ALuint function(char*) pfalutCreateBufferFromFile;
    typedef ALuint function(char*, ALsizei) pfalutCreateBufferFromFileImage;
}

pfalutInit alutInit;
pfalutInitWithoutContext alutInitWithoutContext;
pfalutExit alutExit;
pfalutGetError alutGetError;
pfalutGetErrorString alutGetErrorString;
pfalutCreateBufferFromFile alutCreateBufferFromFile;
pfalutCreateBufferFromFileImage alutCreateBufferFromFileImage;

private void load(SharedLib lib) {
    bindFunc(alutInit)("alutInit",lib);
    bindFunc(alutInitWithoutContext)("alutInitWithoutContext",lib);
    bindFunc(alutExit)("alutExit",lib);
    bindFunc(alutGetError)("alutGetError",lib);
    bindFunc(alutGetErrorString)("alutGetErrorString",lib);
    bindFunc(alutCreateBufferFromFile)("alutCreateBufferFromFile",lib);
    bindFunc(alutCreateBufferFromFileImage)("alutCreateBufferFromFileImage",lib);
}

GenericLoader DerelictALUT;
static this() {
    DerelictALUT.setup(
        "alut.dll", //??
        "libalut.so.0",
        "",
        &load
    );
}
