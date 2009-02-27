module derelict.ffmpeg.avtypes;

extern(C):

enum CodecID {
    CODEC_ID_NONE,

    /* video codecs */
    CODEC_ID_MPEG1VIDEO,
    CODEC_ID_MPEG2VIDEO, ///< preferred ID for MPEG-1/2 video decoding
    CODEC_ID_MPEG2VIDEO_XVMC,
    CODEC_ID_H261,
    CODEC_ID_H263,
    CODEC_ID_RV10,
    CODEC_ID_RV20,
    CODEC_ID_MJPEG,
    CODEC_ID_MJPEGB,
    CODEC_ID_LJPEG,
    CODEC_ID_SP5X,
    CODEC_ID_JPEGLS,
    CODEC_ID_MPEG4,
    CODEC_ID_RAWVIDEO,
    CODEC_ID_MSMPEG4V1,
    CODEC_ID_MSMPEG4V2,
    CODEC_ID_MSMPEG4V3,
    CODEC_ID_WMV1,
    CODEC_ID_WMV2,
    CODEC_ID_H263P,
    CODEC_ID_H263I,
    CODEC_ID_FLV1,
    CODEC_ID_SVQ1,
    CODEC_ID_SVQ3,
    CODEC_ID_DVVIDEO,
    CODEC_ID_HUFFYUV,
    CODEC_ID_CYUV,
    CODEC_ID_H264,
    CODEC_ID_INDEO3,
    CODEC_ID_VP3,
    CODEC_ID_THEORA,
    CODEC_ID_ASV1,
    CODEC_ID_ASV2,
    CODEC_ID_FFV1,
    CODEC_ID_4XM,
    CODEC_ID_VCR1,
    CODEC_ID_CLJR,
    CODEC_ID_MDEC,
    CODEC_ID_ROQ,
    CODEC_ID_INTERPLAY_VIDEO,
    CODEC_ID_XAN_WC3,
    CODEC_ID_XAN_WC4,
    CODEC_ID_RPZA,
    CODEC_ID_CINEPAK,
    CODEC_ID_WS_VQA,
    CODEC_ID_MSRLE,
    CODEC_ID_MSVIDEO1,
    CODEC_ID_IDCIN,
    CODEC_ID_8BPS,
    CODEC_ID_SMC,
    CODEC_ID_FLIC,
    CODEC_ID_TRUEMOTION1,
    CODEC_ID_VMDVIDEO,
    CODEC_ID_MSZH,
    CODEC_ID_ZLIB,
    CODEC_ID_QTRLE,
    CODEC_ID_SNOW,
    CODEC_ID_TSCC,
    CODEC_ID_ULTI,
    CODEC_ID_QDRAW,
    CODEC_ID_VIXL,
    CODEC_ID_QPEG,
    CODEC_ID_XVID,
    CODEC_ID_PNG,
    CODEC_ID_PPM,
    CODEC_ID_PBM,
    CODEC_ID_PGM,
    CODEC_ID_PGMYUV,
    CODEC_ID_PAM,
    CODEC_ID_FFVHUFF,
    CODEC_ID_RV30,
    CODEC_ID_RV40,
    CODEC_ID_VC1,
    CODEC_ID_WMV3,
    CODEC_ID_LOCO,
    CODEC_ID_WNV1,
    CODEC_ID_AASC,
    CODEC_ID_INDEO2,
    CODEC_ID_FRAPS,
    CODEC_ID_TRUEMOTION2,
    CODEC_ID_BMP,
    CODEC_ID_CSCD,
    CODEC_ID_MMVIDEO,
    CODEC_ID_ZMBV,
    CODEC_ID_AVS,
    CODEC_ID_SMACKVIDEO,
    CODEC_ID_NUV,
    CODEC_ID_KMVC,
    CODEC_ID_FLASHSV,
    CODEC_ID_CAVS,
    CODEC_ID_JPEG2000,
    CODEC_ID_VMNC,
    CODEC_ID_VP5,
    CODEC_ID_VP6,
    CODEC_ID_VP6F,
    CODEC_ID_TARGA,
    CODEC_ID_DSICINVIDEO,
    CODEC_ID_TIERTEXSEQVIDEO,
    CODEC_ID_TIFF,
    CODEC_ID_GIF,
    CODEC_ID_FFH264,
    CODEC_ID_DXA,
    CODEC_ID_DNXHD,
    CODEC_ID_THP,
    CODEC_ID_SGI,
    CODEC_ID_C93,
    CODEC_ID_BETHSOFTVID,
    CODEC_ID_PTX,
    CODEC_ID_TXD,
    CODEC_ID_VP6A,
    CODEC_ID_AMV,
    CODEC_ID_VB,
    CODEC_ID_PCX,
    CODEC_ID_SUNRAST,
    CODEC_ID_INDEO4,
    CODEC_ID_INDEO5,
    CODEC_ID_MIMIC,
    CODEC_ID_RL2,
    CODEC_ID_8SVX_EXP,
    CODEC_ID_8SVX_FIB,
    CODEC_ID_ESCAPE124,
    CODEC_ID_DIRAC,
    CODEC_ID_BFI,
    CODEC_ID_CMV,
    CODEC_ID_MOTIONPIXELS,
    CODEC_ID_TGV,
    CODEC_ID_TGQ,
    CODEC_ID_TQI,

    /* various PCM "codecs" */
    CODEC_ID_PCM_S16LE= 0x10000,
    CODEC_ID_PCM_S16BE,
    CODEC_ID_PCM_U16LE,
    CODEC_ID_PCM_U16BE,
    CODEC_ID_PCM_S8,
    CODEC_ID_PCM_U8,
    CODEC_ID_PCM_MULAW,
    CODEC_ID_PCM_ALAW,
    CODEC_ID_PCM_S32LE,
    CODEC_ID_PCM_S32BE,
    CODEC_ID_PCM_U32LE,
    CODEC_ID_PCM_U32BE,
    CODEC_ID_PCM_S24LE,
    CODEC_ID_PCM_S24BE,
    CODEC_ID_PCM_U24LE,
    CODEC_ID_PCM_U24BE,
    CODEC_ID_PCM_S24DAUD,
    CODEC_ID_PCM_ZORK,
    CODEC_ID_PCM_S16LE_PLANAR,
    CODEC_ID_PCM_DVD,
    CODEC_ID_PCM_F32BE,
    CODEC_ID_PCM_F32LE,
    CODEC_ID_PCM_F64BE,
    CODEC_ID_PCM_F64LE,

    /* various ADPCM codecs */
    CODEC_ID_ADPCM_IMA_QT= 0x11000,
    CODEC_ID_ADPCM_IMA_WAV,
    CODEC_ID_ADPCM_IMA_DK3,
    CODEC_ID_ADPCM_IMA_DK4,
    CODEC_ID_ADPCM_IMA_WS,
    CODEC_ID_ADPCM_IMA_SMJPEG,
    CODEC_ID_ADPCM_MS,
    CODEC_ID_ADPCM_4XM,
    CODEC_ID_ADPCM_XA,
    CODEC_ID_ADPCM_ADX,
    CODEC_ID_ADPCM_EA,
    CODEC_ID_ADPCM_G726,
    CODEC_ID_ADPCM_CT,
    CODEC_ID_ADPCM_SWF,
    CODEC_ID_ADPCM_YAMAHA,
    CODEC_ID_ADPCM_SBPRO_4,
    CODEC_ID_ADPCM_SBPRO_3,
    CODEC_ID_ADPCM_SBPRO_2,
    CODEC_ID_ADPCM_THP,
    CODEC_ID_ADPCM_IMA_AMV,
    CODEC_ID_ADPCM_EA_R1,
    CODEC_ID_ADPCM_EA_R3,
    CODEC_ID_ADPCM_EA_R2,
    CODEC_ID_ADPCM_IMA_EA_SEAD,
    CODEC_ID_ADPCM_IMA_EA_EACS,
    CODEC_ID_ADPCM_EA_XAS,
    CODEC_ID_ADPCM_EA_MAXIS_XA,
    CODEC_ID_ADPCM_IMA_ISS,

    /* AMR */
    CODEC_ID_AMR_NB= 0x12000,
    CODEC_ID_AMR_WB,

    /* RealAudio codecs*/
    CODEC_ID_RA_144= 0x13000,
    CODEC_ID_RA_288,

    /* various DPCM codecs */
    CODEC_ID_ROQ_DPCM= 0x14000,
    CODEC_ID_INTERPLAY_DPCM,
    CODEC_ID_XAN_DPCM,
    CODEC_ID_SOL_DPCM,

    /* audio codecs */
    CODEC_ID_MP2= 0x15000,
    CODEC_ID_MP3, ///< preferred ID for decoding MPEG audio layer 1, 2 or 3
    CODEC_ID_AAC,
    CODEC_ID_AC3,
    CODEC_ID_DTS,
    CODEC_ID_VORBIS,
    CODEC_ID_DVAUDIO,
    CODEC_ID_WMAV1,
    CODEC_ID_WMAV2,
    CODEC_ID_MACE3,
    CODEC_ID_MACE6,
    CODEC_ID_VMDAUDIO,
    CODEC_ID_SONIC,
    CODEC_ID_SONIC_LS,
    CODEC_ID_FLAC,
    CODEC_ID_MP3ADU,
    CODEC_ID_MP3ON4,
    CODEC_ID_SHORTEN,
    CODEC_ID_ALAC,
    CODEC_ID_WESTWOOD_SND1,
    CODEC_ID_GSM, ///< as in Berlin toast format
    CODEC_ID_QDM2,
    CODEC_ID_COOK,
    CODEC_ID_TRUESPEECH,
    CODEC_ID_TTA,
    CODEC_ID_SMACKAUDIO,
    CODEC_ID_QCELP,
    CODEC_ID_WAVPACK,
    CODEC_ID_DSICINAUDIO,
    CODEC_ID_IMC,
    CODEC_ID_MUSEPACK7,
    CODEC_ID_MLP,
    CODEC_ID_GSM_MS, /* as found in WAV */
    CODEC_ID_ATRAC3,
    CODEC_ID_VOXWARE,
    CODEC_ID_APE,
    CODEC_ID_NELLYMOSER,
    CODEC_ID_MUSEPACK8,
    CODEC_ID_SPEEX,
    CODEC_ID_WMAVOICE,
    CODEC_ID_WMAPRO,
    CODEC_ID_WMALOSSLESS,
    CODEC_ID_ATRAC3P,
    CODEC_ID_EAC3,
    CODEC_ID_SIPR,
    CODEC_ID_MP1,

    /* subtitle codecs */
    CODEC_ID_DVD_SUBTITLE= 0x17000,
    CODEC_ID_DVB_SUBTITLE,
    CODEC_ID_TEXT,  ///< raw UTF-8 text
    CODEC_ID_XSUB,
    CODEC_ID_SSA,
    CODEC_ID_MOV_TEXT,

    /* other specific kind of codecs (generally used for attachments) */
    CODEC_ID_TTF= 0x18000,

    CODEC_ID_PROBE= 0x19000, ///< codec_id is not known (like CODEC_ID_NONE) but lavf should attempt to identify it

    CODEC_ID_MPEG2TS= 0x20000, /**< _FAKE_ codec to indicate a raw MPEG-2 TS
                                * stream (only used by libavformat) */
}

enum CodecType {
    CODEC_TYPE_UNKNOWN = -1,
    CODEC_TYPE_VIDEO,
    CODEC_TYPE_AUDIO,
    CODEC_TYPE_DATA,
    CODEC_TYPE_SUBTITLE,
    CODEC_TYPE_ATTACHMENT,
    CODEC_TYPE_NB
}

/**
 * all in native-endian format
 */
enum SampleFormat {
    SAMPLE_FMT_NONE = -1,
    SAMPLE_FMT_U8,              ///< unsigned 8 bits
    SAMPLE_FMT_S16,             ///< signed 16 bits
    SAMPLE_FMT_S32,             ///< signed 32 bits
    SAMPLE_FMT_FLT,             ///< float
    SAMPLE_FMT_DBL,             ///< double
    SAMPLE_FMT_NB               ///< Number of sample formats. DO NOT USE if dynamically linking to libavcodec
}

/* Audio channel masks */
enum {
    CH_FRONT_LEFT             = 0x00000001,
    CH_FRONT_RIGHT            = 0x00000002,
    CH_FRONT_CENTER           = 0x00000004,
    CH_LOW_FREQUENCY          = 0x00000008,
    CH_BACK_LEFT              = 0x00000010,
    CH_BACK_RIGHT             = 0x00000020,
    CH_FRONT_LEFT_OF_CENTER   = 0x00000040,
    CH_FRONT_RIGHT_OF_CENTER  = 0x00000080,
    CH_BACK_CENTER            = 0x00000100,
    CH_SIDE_LEFT              = 0x00000200,
    CH_SIDE_RIGHT             = 0x00000400,
    CH_TOP_CENTER             = 0x00000800,
    CH_TOP_FRONT_LEFT         = 0x00001000,
    CH_TOP_FRONT_CENTER       = 0x00002000,
    CH_TOP_FRONT_RIGHT        = 0x00004000,
    CH_TOP_BACK_LEFT          = 0x00008000,
    CH_TOP_BACK_CENTER        = 0x00010000,
    CH_TOP_BACK_RIGHT         = 0x00020000,
    CH_STEREO_LEFT            = 0x20000000,  ///< Stereo downmix.
    CH_STEREO_RIGHT           = 0x40000000,  ///< See CH_STEREO_LEFT.
}

/* Audio channel convenience macros */
const CH_LAYOUT_MONO           = CH_FRONT_CENTER;
const CH_LAYOUT_STEREO         = CH_FRONT_LEFT | CH_FRONT_RIGHT;
const CH_LAYOUT_SURROUND       = CH_LAYOUT_STEREO | CH_FRONT_CENTER;
const CH_LAYOUT_QUAD           = CH_LAYOUT_STEREO | CH_BACK_LEFT
    | CH_BACK_RIGHT;
const CH_LAYOUT_5POINT0        = CH_LAYOUT_SURROUND | CH_SIDE_LEFT
    | CH_SIDE_RIGHT;
const CH_LAYOUT_5POINT1        = CH_LAYOUT_5POINT0 | CH_LOW_FREQUENCY;
const CH_LAYOUT_7POINT1        = CH_LAYOUT_5POINT1 | CH_BACK_LEFT
    | CH_BACK_RIGHT;
const CH_LAYOUT_7POINT1_WIDE   = CH_LAYOUT_SURROUND | CH_LOW_FREQUENCY
    | CH_BACK_LEFT | CH_BACK_RIGHT
    | CH_FRONT_LEFT_OF_CENTER | CH_FRONT_RIGHT_OF_CENTER;
const CH_LAYOUT_STEREO_DOWNMIX = CH_STEREO_LEFT | CH_STEREO_RIGHT;


/* in bytes */
const AVCODEC_MAX_AUDIO_FRAME_SIZE = 192000; // 1 second of 48khz 32bit audio

const FF_INPUT_BUFFER_PADDING_SIZE = 8;

const FF_MIN_BUFFER_SIZE = 16384;

enum Motion_Est_ID {
    ME_ZERO = 1,    ///< no search, that is use 0,0 vector whenever one is needed
    ME_FULL,
    ME_LOG,
    ME_PHODS,
    ME_EPZS,        ///< enhanced predictive zonal search
    ME_X1,          ///< reserved for experiments
    ME_HEX,         ///< hexagon based search
    ME_UMH,         ///< uneven multi-hexagon search
    ME_ITER,        ///< iterative search
    ME_TESA,        ///< transformed exhaustive search algorithm
}

enum AVDiscard {
    /* We leave some space between them for extensions (drop some
     * keyframes for intra-only or drop just some bidir frames). */
    AVDISCARD_NONE   =-16, ///< discard nothing
    AVDISCARD_DEFAULT=  0, ///< discard useless packets like 0 size packets in avi
    AVDISCARD_NONREF =  8, ///< discard all non reference
    AVDISCARD_BIDIR  = 16, ///< discard all bidirectional frames
    AVDISCARD_NONKEY = 32, ///< discard all frames except keyframes
    AVDISCARD_ALL    = 48, ///< discard all
}

enum PixelFormat {
    PIX_FMT_NONE= -1,
    PIX_FMT_YUV420P,   ///< planar YUV 4:2:0, 12bpp, (1 Cr & Cb sample per 2x2 Y samples)
    PIX_FMT_YUYV422,   ///< packed YUV 4:2:2, 16bpp, Y0 Cb Y1 Cr
    PIX_FMT_RGB24,     ///< packed RGB 8:8:8, 24bpp, RGBRGB...
    PIX_FMT_BGR24,     ///< packed RGB 8:8:8, 24bpp, BGRBGR...
    PIX_FMT_YUV422P,   ///< planar YUV 4:2:2, 16bpp, (1 Cr & Cb sample per 2x1 Y samples)
    PIX_FMT_YUV444P,   ///< planar YUV 4:4:4, 24bpp, (1 Cr & Cb sample per 1x1 Y samples)
    PIX_FMT_RGB32,     ///< packed RGB 8:8:8, 32bpp, (msb)8A 8R 8G 8B(lsb), in CPU endianness
    PIX_FMT_YUV410P,   ///< planar YUV 4:1:0,  9bpp, (1 Cr & Cb sample per 4x4 Y samples)
    PIX_FMT_YUV411P,   ///< planar YUV 4:1:1, 12bpp, (1 Cr & Cb sample per 4x1 Y samples)
    PIX_FMT_RGB565,    ///< packed RGB 5:6:5, 16bpp, (msb)   5R 6G 5B(lsb), in CPU endianness
    PIX_FMT_RGB555,    ///< packed RGB 5:5:5, 16bpp, (msb)1A 5R 5G 5B(lsb), in CPU endianness, most significant bit to 0
    PIX_FMT_GRAY8,     ///<        Y        ,  8bpp
    PIX_FMT_MONOWHITE, ///<        Y        ,  1bpp, 0 is white, 1 is black
    PIX_FMT_MONOBLACK, ///<        Y        ,  1bpp, 0 is black, 1 is white
    PIX_FMT_PAL8,      ///< 8 bit with PIX_FMT_RGB32 palette
    PIX_FMT_YUVJ420P,  ///< planar YUV 4:2:0, 12bpp, full scale (JPEG)
    PIX_FMT_YUVJ422P,  ///< planar YUV 4:2:2, 16bpp, full scale (JPEG)
    PIX_FMT_YUVJ444P,  ///< planar YUV 4:4:4, 24bpp, full scale (JPEG)
    PIX_FMT_XVMC_MPEG2_MC,///< XVideo Motion Acceleration via common packet passing
    PIX_FMT_XVMC_MPEG2_IDCT,
    PIX_FMT_UYVY422,   ///< packed YUV 4:2:2, 16bpp, Cb Y0 Cr Y1
    PIX_FMT_UYYVYY411, ///< packed YUV 4:1:1, 12bpp, Cb Y0 Y1 Cr Y2 Y3
    PIX_FMT_BGR32,     ///< packed RGB 8:8:8, 32bpp, (msb)8A 8B 8G 8R(lsb), in CPU endianness
    PIX_FMT_BGR565,    ///< packed RGB 5:6:5, 16bpp, (msb)   5B 6G 5R(lsb), in CPU endianness
    PIX_FMT_BGR555,    ///< packed RGB 5:5:5, 16bpp, (msb)1A 5B 5G 5R(lsb), in CPU endianness, most significant bit to 1
    PIX_FMT_BGR8,      ///< packed RGB 3:3:2,  8bpp, (msb)2B 3G 3R(lsb)
    PIX_FMT_BGR4,      ///< packed RGB 1:2:1,  4bpp, (msb)1B 2G 1R(lsb)
    PIX_FMT_BGR4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1B 2G 1R(lsb)
    PIX_FMT_RGB8,      ///< packed RGB 3:3:2,  8bpp, (msb)2R 3G 3B(lsb)
    PIX_FMT_RGB4,      ///< packed RGB 1:2:1,  4bpp, (msb)1R 2G 1B(lsb)
    PIX_FMT_RGB4_BYTE, ///< packed RGB 1:2:1,  8bpp, (msb)1R 2G 1B(lsb)
    PIX_FMT_NV12,      ///< planar YUV 4:2:0, 12bpp, 1 plane for Y and 1 for UV
    PIX_FMT_NV21,      ///< as above, but U and V bytes are swapped

    PIX_FMT_RGB32_1,   ///< packed RGB 8:8:8, 32bpp, (msb)8R 8G 8B 8A(lsb), in CPU endianness
    PIX_FMT_BGR32_1,   ///< packed RGB 8:8:8, 32bpp, (msb)8B 8G 8R 8A(lsb), in CPU endianness

    PIX_FMT_GRAY16BE,  ///<        Y        , 16bpp, big-endian
    PIX_FMT_GRAY16LE,  ///<        Y        , 16bpp, little-endian
    PIX_FMT_YUV440P,   ///< planar YUV 4:4:0 (1 Cr & Cb sample per 1x2 Y samples)
    PIX_FMT_YUVJ440P,  ///< planar YUV 4:4:0 full scale (JPEG)
    PIX_FMT_YUVA420P,  ///< planar YUV 4:2:0, 20bpp, (1 Cr & Cb sample per 2x2 Y & A samples)
    PIX_FMT_VDPAU_H264,///< H.264 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
    PIX_FMT_VDPAU_MPEG1,///< MPEG-1 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
    PIX_FMT_VDPAU_MPEG2,///< MPEG-2 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
    PIX_FMT_VDPAU_WMV3,///< WMV3 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
    PIX_FMT_VDPAU_VC1, ///< VC-1 HW decoding with VDPAU, data[0] contains a vdpau_render_state struct which contains the bitstream of the slices as well as various fields extracted from headers
    PIX_FMT_RGB48BE,   ///< packed RGB 16:16:16, 48bpp, 16R, 16G, 16B, big-endian
    PIX_FMT_RGB48LE,   ///< packed RGB 16:16:16, 48bpp, 16R, 16G, 16B, little-endian
    PIX_FMT_NB,        ///< number of pixel formats, DO NOT USE THIS if you want to link with shared libav* because the number of formats might differ between versions
}

enum {
    AV_LOG_QUIET    = -8,
    AV_LOG_PANIC    = 0,
    AV_LOG_FATAL    = 8,
    AV_LOG_ERROR    = 16,
    AV_LOG_WARNING  = 24,
    AV_LOG_INFO     = 32,
    AV_LOG_VERBOSE  = 40,
    AV_LOG_DEBUG    = 48,
}

const AVPROBE_PADDING_SIZE = 32;  ///< extra allocated bytes at the end of the probe buffer
const AVPROBE_SCORE_MAX = 100;

const AVSEEK_SIZE = 0x10000;

struct RcOverride {
    int start_frame;
    int end_frame;
    int qscale; // If this is 0 then quality_factor will be used instead.
    float quality_factor;
}

struct AVRational {
    int num; ///< numerator
    int den; ///< denominator
}

struct AVPanScan {
    int id;
    int width;
    int height;
    short [2][3]position;
}

struct AVFrame {
    ubyte *[4]data;
    int [4]linesize;
    ubyte *[4]base;
    int key_frame;
    int pict_type;
    long pts;
    int coded_picture_number;
    int display_picture_number;
    int quality;
    int age;
    int reference;
    byte *qscale_table;
    int qstride;
    ubyte *mbskip_table;
    short [2]*[2]motion_val;
    uint *mb_type;
    ubyte motion_subsample_log2;
    void *opaque;
    ulong [4]error;
    int type;
    int repeat_pict;
    int qscale_type;
    int interlaced_frame;
    int top_field_first;
    AVPanScan *pan_scan;
    int palette_has_changed;
    int buffer_hints;
    short *dct_coeff;
    byte *[2]ref_index;
    long reordered_opaque;
}

struct AVCodec {
    char *name;
    CodecType type;
    CodecID id;
    int priv_data_size;
    int  function(AVCodecContext *)init;
    int  function(AVCodecContext *, ubyte *buf, int buf_size, void *data)encode;
    int  function(AVCodecContext *)close;
    int  function(AVCodecContext *, void *outdata, int *outdata_size, ubyte *buf, int buf_size)decode;
    int capabilities;
    AVCodec *next;
    void  function(AVCodecContext *)flush;
    AVRational *supported_framerates;
    PixelFormat *pix_fmts;
    char *long_name;
    int *supported_samplerates;
    SampleFormat *sample_fmts;
    long *channel_layouts;
}

struct AVCodecContext {
    void* av_class;
    int bit_rate;
    int bit_rate_tolerance;
    int flags;
    int sub_id;
    int me_method;
    ubyte *extradata;
    int extradata_size;
    AVRational time_base;
    int width;
    int height;
    int gop_size;
    PixelFormat pix_fmt;
    int rate_emu;
    void  function(AVCodecContext *s, AVFrame *src, int *offset, int y, int type, int height)draw_horiz_band;
    int sample_rate;
    int channels;
    SampleFormat sample_fmt;
    int frame_size;
    int frame_number;
    int real_pict_num;
    int delay;
    float qcompress;
    float qblur;
    int qmin;
    int qmax;
    int max_qdiff;
    int max_b_frames;
    float b_quant_factor;
    int rc_strategy;
    int b_frame_strategy;
    int hurry_up;
    AVCodec *codec;
    void *priv_data;
    int rtp_payload_size;
    void  function(AVCodecContext *avctx, void *data, int size, int mb_nb)rtp_callback;
    int mv_bits;
    int header_bits;
    int i_tex_bits;
    int p_tex_bits;
    int i_count;
    int p_count;
    int skip_count;
    int misc_bits;
    int frame_bits;
    void *opaque;
    char [32]codec_name;
    CodecType codec_type;
    CodecID codec_id;
    uint codec_tag;
    int workaround_bugs;
    int luma_elim_threshold;
    int chroma_elim_threshold;
    int strict_std_compliance;
    float b_quant_offset;
    int error_recognition;
    int  function(AVCodecContext *c, AVFrame *pic)get_buffer;
    void  function(AVCodecContext *c, AVFrame *pic)release_buffer;
    int has_b_frames;
    int block_align;
    int parse_only;
    int mpeg_quant;
    char *stats_out;
    char *stats_in;
    float rc_qsquish;
    float rc_qmod_amp;
    int rc_qmod_freq;
    RcOverride *rc_override;
    int rc_override_count;
    char *rc_eq;
    int rc_max_rate;
    int rc_min_rate;
    int rc_buffer_size;
    float rc_buffer_aggressivity;
    float i_quant_factor;
    float i_quant_offset;
    float rc_initial_cplx;
    int dct_algo;
    float lumi_masking;
    float temporal_cplx_masking;
    float spatial_cplx_masking;
    float p_masking;
    float dark_masking;
    int idct_algo;
    int slice_count;
    int *slice_offset;
    int error_concealment;
    uint dsp_mask;
    int bits_per_coded_sample;
    int prediction_method;
    AVRational sample_aspect_ratio;
    AVFrame *coded_frame;
    int _debug;
    int debug_mv;
    ulong [4]error;
    int mb_qmin;
    int mb_qmax;
    int me_cmp;
    int me_sub_cmp;
    int mb_cmp;
    int ildct_cmp;
    int dia_size;
    int last_predictor_count;
    int pre_me;
    int me_pre_cmp;
    int pre_dia_size;
    int me_subpel_quality;
    PixelFormat  function(AVCodecContext *s, int *fmt)get_format;
    int dtg_active_format;
    int me_range;
    int intra_quant_bias;
    int inter_quant_bias;
    int color_table_id;
    int internal_buffer_count;
    void *internal_buffer;
    int global_quality;
    int coder_type;
    int context_model;
    int slice_flags;
    int xvmc_acceleration;
    int mb_decision;
    ushort *intra_matrix;
    ushort *inter_matrix;
    uint stream_codec_tag;
    int scenechange_threshold;
    int lmin;
    int lmax;
    void *palctrl;  //AVPaletteControl *palctrl;
    int noise_reduction;
    int  function(AVCodecContext *c, AVFrame *pic)reget_buffer;
    int rc_initial_buffer_occupancy;
    int inter_threshold;
    int flags2;
    int error_rate;
    int antialias_algo;
    int quantizer_noise_shaping;
    int thread_count;
    int  function(AVCodecContext *c, int  function(AVCodecContext *c2, void *arg)func, void *arg2, int *ret, int count, int size)execute;
    void *thread_opaque;
    int me_threshold;
    int mb_threshold;
    int intra_dc_precision;
    int nsse_weight;
    int skip_top;
    int skip_bottom;
    int profile;
    int level;
    int lowres;
    int coded_width;
    int coded_height;
    int frame_skip_threshold;
    int frame_skip_factor;
    int frame_skip_exp;
    int frame_skip_cmp;
    float border_masking;
    int mb_lmin;
    int mb_lmax;
    int me_penalty_compensation;
    AVDiscard skip_loop_filter;
    AVDiscard skip_idct;
    AVDiscard skip_frame;
    int bidir_refine;
    int brd_scale;
    float crf;
    int cqp;
    int keyint_min;
    int refs;
    int chromaoffset;
    int bframebias;
    int trellis;
    float complexityblur;
    int deblockalpha;
    int deblockbeta;
    int partitions;
    int directpred;
    int cutoff;
    int scenechange_factor;
    int mv0_threshold;
    int b_sensitivity;
    int compression_level;
    int use_lpc;
    int lpc_coeff_precision;
    int min_prediction_order;
    int max_prediction_order;
    int prediction_order_method;
    int min_partition_order;
    int max_partition_order;
    long timecode_frame_start;
    int request_channels;
    float drc_scale;
    long reordered_opaque;
    int bits_per_raw_sample;
    long channel_layout;
    long request_channel_layout;
    float rc_max_available_vbv_use;
    float rc_min_vbv_overflow_use;
    void *hwaccel;  //AVHWAccel *hwaccel;
}



struct AVCodecTag;

struct AVFormatParameters {
    AVRational time_base;
    int sample_rate;
    int channels;
    int width;
    int height;
    PixelFormat pix_fmt;
    int channel; /**< Used to select DV channel. */
    char *standard; /**< TV standard, NTSC, PAL, SECAM */
align(1):
    uint mpeg2ts_raw;  /**< Force raw MPEG-2 transport stream output, if possible. */
    uint mpeg2ts_compute_pcr; /**< Compute exact PCR for each transport
                                            stream packet (only meaningful if
                                            mpeg2ts_raw is TRUE). */
    uint initial_pause;       /**< Do not begin to play the stream
                                            immediately (RTSP only). */
    uint prealloced_context;
    CodecID video_codec_id;
    CodecID audio_codec_id;
}

struct AVPacket {
    /**
     * Presentation timestamp in time_base units.
     * This is the time at which the decompressed packet will be presented
     * to the user.
     * Can be AV_NOPTS_VALUE if it is not stored in the file.
     * pts MUST be larger or equal to dts as presentation cannot happen before
     * decompression, unless one wants to view hex dumps. Some formats misuse
     * the terms dts and pts/cts to mean something different, these timestamps
     * must be converted to true pts/dts before they are stored in AVPacket.
     */
    long pts;
    /**
     * Decompression timestamp in time_base units.
     * This is the time at which the packet is decompressed.
     * Can be AV_NOPTS_VALUE if it is not stored in the file.
     */
    long dts;
    ubyte *data;
    int   size;
    int   stream_index;
    int   flags;
    /**
     * Duration of this packet in time_base units, 0 if unknown.
     * Equals next_pts - this_pts in presentation order.
     */
    int   duration;
    void function (AVPacket*) destruct;
    void  *priv;
    long pos;                            ///< byte position in stream, -1 if unknown

    /**
     * Time difference in stream time base units from the pts of this
     * packet to the point at which the output from the decoder has converged
     * independent from the availability of previous frames. That is, the
     * frames are virtually identical no matter if decoding started from
     * the very first frame or from this keyframe.
     * Is AV_NOPTS_VALUE if unknown.
     * This field is not the display duration of the current packet.
     *
     * The purpose of this field is to allow seeking in streams that have no
     * keyframes in the conventional sense. It corresponds to the
     * recovery point SEI in H.264 and match_time_delta in NUT. It is also
     * essential for some types of subtitle streams to ensure that all
     * subtitles are correctly displayed after seeking.
     */
    long convergence_duration;
}

const PKT_FLAG_KEY = 0x0001;

struct AVProbeData {
    char *filename;
    ubyte *buf;
    int buf_size;
}

struct AVOutputFormat {
    char *name;
    char *long_name;
    char *mime_type;
    char *extensions;
    int priv_data_size;
    CodecID audio_codec;
    CodecID video_codec;
    int  function(AVFormatContext *)write_header;
    int  function(AVFormatContext *, AVPacket *pkt)write_packet;
    int  function(AVFormatContext *)write_trailer;
    int flags;
    int  function(AVFormatContext *, AVFormatParameters *)set_parameters;
    int  function(AVFormatContext *, AVPacket *_out, AVPacket *_in, int flush)interleave_packet;
    AVCodecTag **codec_tag;
    CodecID subtitle_codec;
    AVOutputFormat *next;
}

struct AVInputFormat {
    char *name;
    char *long_name;
    int priv_data_size;
    int  function(AVProbeData *)read_probe;
    int  function(AVFormatContext *, AVFormatParameters *ap)read_header;
    int  function(AVFormatContext *, AVPacket *pkt)read_packet;
    int  function(AVFormatContext *)read_close;
    int  function(AVFormatContext *, int stream_index, long timestamp, int flags)read_seek;
    long  function(AVFormatContext *s, int stream_index, long *pos, long pos_limit)read_timestamp;
    int flags;
    char *extensions;
    int value;
    int  function(AVFormatContext *)read_play;
    int  function(AVFormatContext *)read_pause;
    AVCodecTag **codec_tag;
    int  function(AVFormatContext *s, int stream_index, long min_ts, long ts, long max_ts, int flags)reed_seek2;
    AVInputFormat *next;
}

struct AVPacketList {
    AVPacket pkt;
    AVPacketList *next;
}

struct AVFrac {
    long val, num, den;
}

struct AVStream {
    int index;
    int id;
    AVCodecContext *codec;
    AVRational r_frame_rate;
    void *priv_data;
    long first_dts;
    AVFrac pts;
    AVRational time_base;
    int pts_wrap_bits;
    int stream_copy;
    int discard;
    float quality;
    long start_time;
    long duration;
    char [4]language;
    int need_parsing;
    //AVCodecParserContext *parser;
    void *parser;
    long cur_dts;
    int last_IP_duration;
    long last_IP_pts;
    //AVIndexEntry *index_entries;
    void *index_entries;
    int nb_index_entries;
    uint index_entries_allocated_size;
    long nb_frames;
    long [5]unused;
    char *filename;
    int disposition;
    AVProbeData probe_data;
    long [17]pts_buffer;
    AVRational sample_aspect_ratio;
    //AVMetadata *metadata;
    void *metadata;
    ubyte *cur_ptr;
    int cur_len;
    AVPacket cur_pkt;
    long reference_dts;
}

struct AVFormatContext {
    //AVCLASS *av_class;
    void *av_class;
    AVInputFormat *iformat;
    AVOutputFormat *oformat;
    void *priv_data;
    void *pb;
    uint nb_streams;
    AVStream *[20]streams;
    char [1024]filename;
    long timestamp;
    char [512]title;
    char [512]author;
    char [512]copyright;
    char [512]comment;
    char [512]album;
    int year;
    int track;
    char [32]genre;
    int ctx_flags;
    AVPacketList *packet_buffer;
    long start_time;
    long duration;
    long file_size;
    int bit_rate;
    AVStream *cur_st;
    ubyte *cur_ptr_deprecated;
    int cur_len_deprecated;
    AVPacket cur_pkt_deprecated;
    long data_offset;
    int index_built;
    int mux_rate;
    int packet_size;
    int preload;
    int max_delay;
    int loop_output;
    int flags;
    int loop_input;
    uint probesize;
    int max_analyze_duration;
    ubyte *key;
    int keylen;
    uint nb_programs;
    //AVProgram **programs;
    void **programs;
    int video_codec_id;
    int audio_codec_id;
    int subtitle_codec_id;
    uint max_index_size;
    uint max_picture_buffer;
    uint nb_chapters;
    //AVChapter **chapters;
    void **chapters;
    int _debug;
    AVPacketList *raw_packet_buffer;
    AVPacketList *raw_packet_buffer_end;
    AVPacketList *packet_buffer_end;
    //AVMetadata *metadata;
    void*metadata;
}

struct ByteIOContext{
    ubyte *buffer;
    int buffer_size;
    ubyte* buf_ptr, buf_end;
    void *opaque;
    int function(void *opaque, ubyte *buf, int buf_size) read_packet;
    int function(void *opaque, ubyte *buf, int buf_size) write_packet;
    long function(void *opaque, long offset, int whence) seek;
    long pos; /**< position in the file of the current buffer */
    int must_flush; /**< true if the next seek should flush */
    int eof_reached; /**< true if eof reached */
    int write_flag;  /**< true if open for writing */
    int is_streamed;
    int max_packet_size;
    uint checksum;
    ubyte *checksum_ptr;
    uint function(uint checksum, ubyte *buf, uint size) update_checksum;
    int error;         ///< contains the error code or 0 if no error happened
    int function(void *opaque, int pause) read_pause;
    long function(void *opaque, int stream_index, long timestamp, int flags) read_seek;
}
