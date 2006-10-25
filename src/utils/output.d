module utils.output;

/// interface for a generic text output stream (D currently lacks support for
/// text streams, so we have to do it)
public interface Output {
    void writef(...);
    void writefln(...);
    void writef_ind(bool newline, TypeInfo[] arguments, void* argptr);
}
