module derelict.ffmpeg.av;

///Minimal headers for ffmpeg dynamic libraries (i.e. just what's required to
///  decode audio streams to raw pcm)
///Required versions: avcodec-52, avformat-52, avutil-49
///Get Win32 shared lib binaries at http://ffmpeg.arrozcru.com/builds

import derelict.util.loader;
public import derelict.ffmpeg.avtypes;

extern(C):

//****** AVCodec functions *********
void function() avcodec_init;
void function() avcodec_register_all;
int function(AVCodecContext *avctx, AVCodec *codec) avcodec_open;
int function(AVCodecContext *avctx) avcodec_close;
AVCodec* function(CodecID id) avcodec_find_decoder;
int function(AVCodecContext *avctx, short *samples, int *frame_size_ptr,
    ubyte *buf, int buf_size) avcodec_decode_audio2;

//****** AVFormat functions *********
void function() av_register_all;
int function(AVFormatContext **ic_ptr, char *filename, AVInputFormat *fmt,
    int buf_size, AVFormatParameters *ap) av_open_input_file;
int function(AVFormatContext **ic_ptr, ByteIOContext *pb, char *filename,
    AVInputFormat *fmt, AVFormatParameters *ap) av_open_input_stream;
int function(AVFormatContext *ic) av_find_stream_info;
void function(AVFormatContext *s) av_close_input_file;
int function(AVFormatContext *s, AVPacket *pkt) av_read_frame;
AVInputFormat* function(AVProbeData *pd, int is_opened) av_probe_input_format;

ByteIOContext* function(ubyte *buffer, int buffer_size,
      int write_flag, void *opaque,
      int function(void *opaque, ubyte *buf, int buf_size) read_packet,
      int function(void *opaque, ubyte *buf, int buf_size) write_packet,
      long function(void *opaque, long offset, int whence) seek) av_alloc_put_byte;
int function(ByteIOContext *s, int buf_size) url_setbufsize;
long function(ByteIOContext *s, long offset, int whence) url_fseek;
void function(ByteIOContext *s, long offset) url_fskip;
long function(ByteIOContext *s) url_ftell;
long function(ByteIOContext *s) url_fsize;
int function(ByteIOContext *s) url_fclose;

//****** AVUtil functions *********
void function(int) av_log_set_level;


extern(D):

void av_free_packet(AVPacket *pkt) {
    if (pkt && pkt.destruct) {
        pkt.destruct(pkt);
    }
}

private void loadCodec(SharedLib lib) {
    bindFunc(avcodec_init)("avcodec_init", lib);
    bindFunc(avcodec_register_all)("avcodec_register_all", lib);
    bindFunc(avcodec_open)("avcodec_open", lib);
    bindFunc(avcodec_close)("avcodec_close", lib);
    bindFunc(avcodec_find_decoder)("avcodec_find_decoder", lib);
    bindFunc(avcodec_decode_audio2)("avcodec_decode_audio2", lib);
}

private void loadFormat(SharedLib lib) {
    bindFunc(av_register_all)("av_register_all", lib);
    bindFunc(av_open_input_file)("av_open_input_file", lib);
    bindFunc(av_open_input_stream)("av_open_input_stream", lib);
    bindFunc(av_find_stream_info)("av_find_stream_info", lib);
    bindFunc(av_close_input_file)("av_close_input_file", lib);
    bindFunc(av_read_frame)("av_read_frame", lib);
    bindFunc(av_alloc_put_byte)("av_alloc_put_byte", lib);
    bindFunc(url_setbufsize)("url_setbufsize", lib);
    bindFunc(av_probe_input_format)("av_probe_input_format", lib);
    bindFunc(url_fseek)("url_fseek", lib);
    bindFunc(url_fskip)("url_fskip", lib);
    bindFunc(url_ftell)("url_ftell", lib);
    bindFunc(url_fsize)("url_fsize", lib);
    bindFunc(url_fclose)("url_fclose", lib);
}

private void loadUtil(SharedLib lib) {
    bindFunc(av_log_set_level)("av_log_set_level", lib);
}

GenericLoader DerelictAVCodec;
GenericLoader DerelictAVFormat;
GenericLoader DerelictAVUtil;
static this() {
    DerelictAVCodec.setup(
        "avcodec-52.dll",
        "libavcodec.so.52",
        "",
        &loadCodec
    );
    DerelictAVFormat.setup(
        "avformat-52.dll",
        "libavformat.so.52",
        "",
        &loadFormat
    );
    DerelictAVUtil.setup(
        "avutil-49.dll",
        "libavutil.so.49",
        "",
        &loadUtil
    );
}
