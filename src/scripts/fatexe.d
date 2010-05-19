import tango.io.Stdout;
import tango.io.device.File;

void main(char[][] args) {
    if (args.length != 3) {
        Stdout("Usage:").newline;
        Stdout("    fatexe <exe> <attachment>").newline;
        Stdout("Attachment will be appended to the exe.").newline;
        return;
    }
    char[] exe = args[1];
    char[] attach = args[2];
    auto exef = new File(exe, File.WriteAppending);
    auto attachf = new File(attach, File.ReadExisting);
    auto len = attachf.length;

    exef.copy(attachf);

    struct Header {
        uint size;
        char[4] MAGIC = "LUMB";
    }
    Header header;
    header.size = len;

    exef.write(cast(void[])((&header)[0..1]));

    exef.close();
    attachf.close();
}
