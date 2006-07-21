module framework.sdl.rwops;

import derelict.sdl.sdl;
import std.stream;

/*class SDLRWops {
    private SDL_RWops* mRWops;

    this(Stream str) {

    }

    public SDL_RWops*
}*/

extern (C) {
  int rw_seek (SDL_RWops *context, int offset, int whence) {
    Stream str = cast(Stream)context.data1;
    return cast(int)str.seek(offset,cast(SeekPos)whence);
  }

  int rw_read (SDL_RWops *context, void *ptr, int size, int maxnum) {
    Stream str = cast(Stream)context.data1;
    return str.readBlock(ptr,size*maxnum) / size;
  }

  int rw_write (SDL_RWops *context, void *ptr, int size, int num) {
    Stream str = cast(Stream)context.data1;
    return str.writeBlock(ptr,size*num) / size;
  }

  int rw_close (SDL_RWops *context) {
    Stream str = cast(Stream)context.data1;
    str.close();
    return 1;
  }
}

SDL_RWops* rwopsFromStream(Stream s) {
  SDL_RWops* rw;
  rw = SDL_AllocRW();
  rw.seek=&rw_seek;
  rw.read=&rw_read;
  rw.write=&rw_write;
  rw.close=&rw_close;
  rw.data1 = cast(void*)s;
  return rw;
}

