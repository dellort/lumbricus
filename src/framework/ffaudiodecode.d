module framework.ffaudiodecode;

///FFMpeg audio decoder stream, based on alFFmpeg tutorial of OpenAL Soft

import derelict.ffmpeg.av;
import utils.time;
import utils.misc;

import utils.stream;
import tango.stdc.stringz;
import tango.util.Convert;
import tango.stdc.string : memmove;


extern(C):

//stream interface to connect D streams with url_xxx functions and ByteIOContext

int avreadstr(void *opaque, ubyte *buf, int buf_size) {
    auto st = cast(Stream)opaque;
    assert(!!st);
    return st.readBlock(buf, buf_size);
}

int avwritestr(void *opaque, ubyte *buf, int buf_size) {
    auto st = cast(Stream)opaque;
    assert(!!st);
    return st.writeBlock(buf, buf_size);
}

long avseekstr(void *opaque, long offset, int whence) {
    //debug Trace.formatln("Seek {} ({})", offset, whence);
    auto st = cast(Stream)opaque;
    assert(!!st);
    if (whence == AVSEEK_SIZE)
        return st.size();
    else
        return st.seek(offset, cast(SeekPos)whence);
}

extern(D):

//convert a D stream to a ByteIOContext*
ByteIOContext* streamToByteIO(Stream st, bool write) {
    //create context with callbacks set
    ByteIOContext* ret = av_alloc_put_byte(null, 0, cast(int)write,
        cast(void*)st, &avreadstr, &avwritestr, &avseekstr);
    //allocate buffer
    url_setbufsize(ret, 4*1024);
    return ret;
}

private bool libLoaded;

void checkFFMpegLoaded() {
    if (!libLoaded) {
        //load ffmpeg libraries
        DerelictAVCodec.load();
        DerelictAVFormat.load();
        DerelictAVUtil.load();

        //initialize
        av_register_all();
        av_log_set_level(AV_LOG_ERROR);
        libLoaded = true;
    }
}

void unloadFFMpeg() {
    if (libLoaded) {
        DerelictAVCodec.unload();
        DerelictAVFormat.unload();
        DerelictAVUtil.unload();
        libLoaded = false;
    }
}

///This stream decodes one audio stream of the input media file to
///  raw 16-bit PCM with samplerate/channels of the source
class AudioDecoderStream : Stream {
    private {
        AVFormatContext* mFmtCtx;
        AVCodecContext* mCodecCtx;
        ByteIOContext* mByteIO;
        int mStreamIdx;
        Stream mAudioFile;
        Time mDuration;

        ubyte[] mData = void, mDecodedData = void;
        size_t mDataSize, mDecodedDataSize, mDecodedIndex;
    }

    //filename is needed for format probing
    //  streamNum = select another audio stream, counting only audio streams
    this(Stream audioFile, char[] filename = "", int streamNum = 0) {
        checkFFMpegLoaded();

        readable = false;
        seekable = false;

        mAudioFile = audioFile;

        //determine input format
        AVInputFormat* fmt = probeFormat(mAudioFile, filename);
        if (!fmt)
            throw new Exception("Failed to determine input format");

        debug Trace.formatln("Container format: {}",
            fromStringz(fmt.long_name));

        //allocate stream structure and open the file with the format
        //  probed before
        mByteIO = streamToByteIO(mAudioFile, false);
        if (av_open_input_stream(&mFmtCtx, mByteIO, toStringz(filename), fmt,
            null) != 0)
        {
            throw new Exception("Failed to open input file");
        }
        scope(failure) av_close_input_file(mFmtCtx);

        /* After opening, we must search for the stream information because not
         * all formats will have it in stream headers (eg. system MPEG streams)
         */
        if (av_find_stream_info(mFmtCtx) < 0) {
            throw new Exception("Failed to get media file info");
        }

        //check all streams and search for audio streams (there may be more)
        for (int i = 0; i < mFmtCtx.nb_streams; i++) {
            if (mFmtCtx.streams[i].codec.codec_type
                != CodecType.CODEC_TYPE_AUDIO)
            {
                //no audio stream
                continue;
            }

            if(streamNum == 0)
            {
                //we have the audio stream requested by the user
                mCodecCtx = mFmtCtx.streams[i].codec;
                mStreamIdx = i;
                debug Trace.formatln("{}: Audio stream, CodecID={:x#}",
                    i, mCodecCtx.codec_id);

                //initialize decoder
                AVCodec* codec = avcodec_find_decoder(mCodecCtx.codec_id);
                if (!codec || avcodec_open(mCodecCtx, codec) < 0) {
                    throw new Exception("Failed to load a matching decoder");
                }
                debug Trace.formatln("Codec: {}",fromStringz(codec.long_name));

                //calculate stream duration
                mDuration = timeMusecs((1_000_000L*mFmtCtx.streams[i].duration
                    *mFmtCtx.streams[i].time_base.num)
                    /mFmtCtx.streams[i].time_base.den);
            }
            streamNum--;
        }
        if (!mCodecCtx)
            throw new Exception("The file does not contain audio stream "
                ~ to!(char[])(streamNum));
        scope(failure) avcodec_close(mCodecCtx);

        //reserve buffer space for decoded samples
        mDecodedData = new ubyte[AVCODEC_MAX_AUDIO_FRAME_SIZE];
    }

    //probe format of input stream
    //stolen from av_open_input_file() implementation, because ffmpeg public
    //  api is quite stupid
    //Stream needs to be seekable, and will be reset to position 0 afterwards
    private AVInputFormat* probeFormat(Stream st, char[] filename) {
        const PROBE_BUF_MIN = 2048;
        const PROBE_BUF_MAX = 1<<20;

        AVProbeData pd;
        AVInputFormat* fmt;
        //I don't know if the filename is really necessary
        pd.filename = toStringz(filename);
        ubyte[] probeBuf;
        for(int probe_size=PROBE_BUF_MIN; probe_size<=PROBE_BUF_MAX && !fmt;
            probe_size<<=1)
        {
            /* read probe data */
            probeBuf.length = probe_size + AVPROBE_PADDING_SIZE;
            pd.buf = probeBuf.ptr;
            st.seek(0, SeekPos.Set);
            pd.buf_size = st.readBlock(probeBuf.ptr, probe_size);
            probeBuf[probe_size..$] = 0;
            fmt = av_probe_input_format(&pd, 1);
        }
        st.seek(0, SeekPos.Set);
        delete probeBuf;
        return fmt;
    }

    //read a packet into the input buffer and return the number of bytes added
    protected int getNextPacket() {
        AVPacket packet;
        while (av_read_frame(mFmtCtx, &packet) >= 0) {
            if (packet.stream_index == mStreamIdx) {
                //the packet belongs to the current stream
                if (mDataSize + packet.size + FF_INPUT_BUFFER_PADDING_SIZE
                    > mData.length)
                {
                    mData.length = mDataSize + packet.size
                        + FF_INPUT_BUFFER_PADDING_SIZE;
                }
                mData[mDataSize..mDataSize+packet.size] =
                    packet.data[0..packet.size];
                mDataSize += packet.size;
                //Clear the input padding bits
                mData[mDataSize..mDataSize+FF_INPUT_BUFFER_PADDING_SIZE] = 0;
                int psize = packet.size;
                av_free_packet(&packet);
                return psize;
            }
            // Free the packet and look for another
            av_free_packet(&packet);
        }
        return 0;
    }

    //decode audio data in mData and write to mDecodedData
    //return the number of bytes of mData used (-1 on error, 0 if not enough
    //  data available)
    //set decBytes to the number of decoded bytes written into mDecodedData
    //  (0 if return <= 0)
    protected int decodeAudio(out int decBytes) {
        decBytes = mDecodedData.length;
        return avcodec_decode_audio2(mCodecCtx, cast(short*)mDecodedData.ptr,
            &decBytes, mData.ptr, mDataSize);
    }

    //decode size bytes into buffer
    //will read and decode data on demand
    //Note: completely independent of ffmpeg, just some generic buffering
    override uint readBlock(void* buffer, uint size) {
        int dec = 0;

        while(dec < size) {
            if (mDecodedDataSize > 0) {
                /* Get the amount of bytes remaining to be written, and clamp to
                 * the amount of decoded data we have */
                size_t rem = size - dec;
                if(rem > mDecodedDataSize)
                    rem = mDecodedDataSize;

                /* Copy the data to the app's buffer and increment */
                buffer[0..rem] = mDecodedData[mDecodedIndex..mDecodedIndex+rem];
                buffer += rem;
                dec += rem;
                //in case we ran out, this index value is never used again
                mDecodedIndex += rem;
                //may become 0
                mDecodedDataSize -= rem;
            }

            /* Check if we need to get more decoded data */
            if (mDecodedDataSize == 0) {
                mDecodedIndex = 0;
                if (mDataSize == 0) {
                    //get some input data
                    if (getNextPacket() == 0) {
                        //no more data
                        break;
                    }
                }

                /* Decode some data, and check for errors */
                int decSize, inputUsed;
                while ((inputUsed = decodeAudio(decSize)) == 0) {
                    //decodeAudio returned 0 (no frame could be
                    //  decompressed), so there should be no output
                    assert(decSize == 0);
                    //there was not enough input data, get another packet
                    if (getNextPacket() == 0)
                        break;
                }

                if (inputUsed < 0)
                    break;  //decoding error, throw exception? maybe just eof

                if (inputUsed > 0) {
                    /* If any input data is left, move it to the start of the
                     * buffer, and decrease the buffer size */
                    size_t rem = mDataSize - inputUsed;
                    //need memmove because areas overlap
                    //xxx lots of memory moving, better solution?
                    memmove(mData.ptr, mData.ptr + inputUsed, rem);
                    mDataSize = rem;
                }
                /* Set the output buffer size */
                mDecodedDataSize = decSize;
            }
        }
        return dec;
    }

    override uint writeBlock(void* buffer, uint size) {
        assert(false);
    }

    override ulong seek(long offset, SeekPos whence) {
        assert(false);
    }

    int rate() {
        return mCodecCtx.sample_rate;
    }
    int channels() {
        return mCodecCtx.channels;
    }
    int bits() {
        return 16;
    }
    Time duration() {
        return mDuration;
    }

    void close() {
        delete mData;
        delete mDecodedData;
        //url_fclose will try to cast this to URLContext* (there doesn't seem
        //  to be a closing equivalent to av_alloc_put_byte)
        mByteIO.opaque = null;
        //this call only frees the buffers, mAudioFile stream is not touched
        url_fclose(mByteIO);
        mByteIO = null;
        avcodec_close(mCodecCtx);
        mCodecCtx = null;
        av_close_input_file(mFmtCtx);
        mFmtCtx = null;
    }
}


debug {

void testAudioDecode() {
    char[] fn = "music.ogg";
    //char[] fn = r"..\data\data\music.wav";
    scope f = new File(fn, FileMode.In);
    auto s = new AudioDecoderStream(f, fn);
    Trace.formatln("{}Hz, {}Ch, {}Bit, {}", s.rate, s.channels, s.bits,
        s.duration);

    scope fout = new File("out.raw", FileMode.OutNew);
    ubyte[] buf = new ubyte[4*1024];
    int total;
    while (true) {
        int len = s.readBlock(buf.ptr, buf.length);
        fout.writeBlock(buf.ptr, len);
        total += len;
        Trace.format("{} bytes written            \r",total).flush;
        if (len < buf.length)
            break;
    }
    fout.close;
    s.close();
}

}
