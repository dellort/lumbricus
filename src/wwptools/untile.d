module wwptools.untile;

import framework.surface;
import utils.stream;
import utils.misc;
import utils.vector2;

string[] readNamefile(Stream f) {
    return str.splitlines(cast(string)f.readAll());
}

Surface[] untileImages(Surface img) {
    Surface[] res;
    if (img.size.y > img.size.x) {
        int tilesize = img.size.x;
        for (int i = 0; i < img.size.y/tilesize; i ++) {
            auto s = Vector2i(tilesize);
            auto imgout = new Surface(s);
            imgout.copyFrom(img, Vector2i(0), Vector2i(0, tilesize*i), s);
            res ~= imgout;
        }
    } else {
        int tilesize = img.size.y;
        for (int i = 0; i < img.size.x/tilesize; i ++) {
            auto s = Vector2i(tilesize);
            auto imgout = new Surface(s);
            imgout.copyFrom(img, Vector2i(0), Vector2i(tilesize*i, 0), s);
            res ~= imgout;
        }
    }
    return res;
}
