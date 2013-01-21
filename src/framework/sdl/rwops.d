module framework.sdl.rwops;

import derelict.sdl.sdl;
import utils.stream;
import utils.misc;

extern (C) {
  int rw_seek (SDL_RWops *context, int offset, int whence) {
    Stream str = cast(Stream)context.hidden.unknown.data1;
    switch (whence) {
        case RW_SEEK_SET:
            str.position = offset; break;
        case RW_SEEK_CUR:
            str.seekRelative(offset); break;
        case RW_SEEK_END:
            str.position = str.size + offset; break;
        default:
            return -1; //eh what
    }
    return cast(int)str.position;
  }

  int rw_read (SDL_RWops *context, void *ptr, int size, int maxnum) {
    Stream str = cast(Stream)context.hidden.unknown.data1;
    auto s = str.readUntilEof(cast(ubyte[])ptr[0..size*maxnum]);
    //consider rw_read(_,_,128,1), and s.length is 123 - what should the file
    //position be?
    //from experiments with C it seems having the file pointer at EOF is ok
    return cast(int)(s.length/size);
  }

  int rw_write (SDL_RWops *context, const(void *) ptr, int size, int num) {
    Stream str = cast(Stream)context.hidden.unknown.data1;
    str.writeExact(cast(ubyte[])ptr[0..size*num]);
    return num;
  }

  int rw_close (SDL_RWops *context) {
    Stream str = cast(Stream)context.hidden.unknown.data1;
    str.close();
    return 1;
  }
}

SDL_RWops* rwopsFromStream(Stream s) {
  assert(!!s);
  SDL_RWops* rw;
  rw = SDL_AllocRW();
  rw.seek=&rw_seek;
  rw.read=&rw_read;
  rw.write=&rw_write;
  rw.close=&rw_close;
  rw.hidden.unknown.data1 = cast(void*)s;
  return rw;
}

