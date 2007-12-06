module convert;

import wwptools.convert;
import std.stdio;

int main(char[][] args)
{
    try {
        RGBTriple ret;
        if (args[1] == "ground") {
            ret = convertGround(args[2]);
            writefln("    bordercolor = \"%.6f %.6f %.6f\"", ret.r, ret.g,
                ret.b);
        } else if (args[1] == "sky") {
            ret = convertSky(args[2]);
            writefln("    skycolor = \"%.6f %.6f %.6f\"", ret.r, ret.g, ret.b);
        } else {
            throw new Exception("Syntax: convert ground|sky <filename>");
        }
    } catch (Exception e) {
        writefln("Error: %s",e.msg);
        return 1;
    }
    return 0;
}
