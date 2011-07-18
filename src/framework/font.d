module framework.font;
import framework.filesystem;
import framework.drawing;
import framework.driver_base;
import framework.surface;
import utils.array;
import utils.color;
import utils.configfile;
import utils.factory;
import utils.log;
import utils.misc;
import utils.stream;
import utils.vector2;

import str = utils.string;

//read-only for outside
FontManager gFontManager;

static this() {
    gFontManager = new FontManager();
}


enum FaceStyle {
    normal,
    bold,
    italic,
    boldItalic,
}

///uniquely describes a font, same properties => is the same
struct FontProperties {
    string face = "default";
    int size = 14;
    Color back_color = {0.0f,0.0f,0.0f,0.0f};
    Color fore_color = {0.0f,0.0f,0.0f,1.0f};
    bool bold;
    bool italic;
    bool underline;
    //border in pixels (0 means disabled)
    int border_width;
    Color border_color;
    //distance of the shadow from the real text in pixels (0 means disabled)
    int shadow_offset;
    Color shadow_color = {0.0f,0.0f,0.0f,0.7f};

    FaceStyle getFaceStyle() {
        if (bold && italic)  return FaceStyle.boldItalic;
        if (bold && !italic) return FaceStyle.bold;
        if (!bold && italic) return FaceStyle.italic;
        return FaceStyle.normal;
    }
}

//xxx: it'd be better to just keep a file handle to the font file,
//     or to share all FT_Face-s across all FTGlyphCache-s (srsly),
//     but for now I'm doing this due to various circumstances
//     FT doesn't seem to have stream abstractions either
alias BigArray!(ubyte) FontData;

//xxx it would really be much better to provide methods like
//  FontDriver.draw(FontProperties style, Vector2i pos, string text);
//this would keep the number of objects lower and would be simpler
//for now, keeping this, because all the code is already written
abstract class DriverFont : DriverResource {
    //w == int.max for unlimited text
    //fore, back, border_color: Color.Invalid to use predefined color
    abstract Vector2i draw(Canvas canvas, Vector2i pos, string text);
    abstract Vector2i textSize(string text, bool forceHeight);
}

//creates DriverFont from Font
abstract class FontDriver : ResDriver {
}

final class Font : ResourceT!(DriverFont) {
    private {
        FontProperties mProps;
    }

    this(FontProperties props) {
        mProps = props;
    }

    private DriverFont get() {
        auto drv = gFontManager.driver;
        assert(!!drv);
        auto df = castStrict!(DriverFont)(drv.requireDriverResource(this));
        assert(!!df);
        return df;
    }

    /// draw UTF8 encoded text
    /// returns position beyond last drawn glyph
    Vector2i drawText(Canvas canvas, Vector2i pos, string text) {
        return get.draw(canvas, pos, text);
    }

    /// return pixel width/height of the text
    /// forceHeight: if true (default), an empty string will return
    ///              (0, fontHeight) instead of (0,0)
    Vector2i textSize(string text, bool forceHeight = true) {
        return get.textSize(text, forceHeight);
    }

    ///return length of text that fits into width w (size(text[0..return]) <= w)
    ///atWhitespace = true to prefer including only whole words (by str.iswhite)
    ///disallow_nofit = if true, return 0 if the text can't be broken on a
    /// word/whitespace boundary
    //added long after findIndex, because findIndex seems to have quadratic
    //  complexity, and doesn't quite compute what we want
    uint textFit(string text, int w, bool atWhitespace = false,
        bool disallow_nofit = false)
    {
        if (w <= 0)
            return 0;
        disallow_nofit &= atWhitespace;
        size_t i = 0;
        size_t lastWhite = 0;
        while (i < text.length) {
            size_t i2 = i;
            dchar ch = str.decode(text, i2);
            if (atWhitespace && str.iswhite(ch)) {
                lastWhite = i2;
            }
            int cw = textSize(text[i..i2]).x;
            if (cw > w)
                break;
            w -= cw;
            i = i2;
        }
        if (disallow_nofit) {
            return (lastWhite && i < text.length) ? lastWhite : 0;
        } else {
            return (lastWhite && i < text.length) ? lastWhite : i;
        }
    }

    ///return the utf character index closest to posX
    ///(0 for start, text.length for end)
    ///posX is relative to left edge of text
    public uint findIndex(string text, int posX) {
        int twold = 0, ilast = 0, i = 0;
        //check width from start until it is over the requested position
        while (i < text.length) {
            i += str.stride(text, i);
            int twidth = textSize(text[0..i]).x;
            if (twidth > posX) {
                //over-shot position -> clicked between current and last pos
                //determine distance to center of last character
                int rel = posX - (twold + (twidth-twold)/2);
                if (rel > 0)
                    //after center -> next index
                    return i;
                else
                    return ilast;
            }
            twold = twidth;
            ilast = i;
        }
        //no match -> must be after the string
        return text.length;
    }

    FontProperties properties() {
        return mProps;
    }

    void free() {
        unload();
    }
}

/// Manages fonts (surprise!)
/// get with gFontManager
class FontManager : ResourceManagerT!(FontDriver) {
    private {
        struct FaceStyles {
            //for each style, the font file loaded into memory
            FontData[FaceStyle.max+1] styles;
        }

        Font[string] mIDtoFont;
        ConfigNode mNodes;
        FaceStyles[string] mFaces;
        Font[FontProperties] mCache;
    }

    this() {
        super("font");
    }

    /// Read a font definition file. See data/fonts.conf
    public void readFontDefinitions(ConfigNode node) {
        foreach (ConfigNode n; node.getSubNode("faces")) {
            string[] faces = n.getCurValue!(string[])();
            foreach (int idx, string faceFile; faces) {
                if (idx > FaceStyle.max)
                    break;
                scope st = gFS.open(faceFile);
                scope(exit) st.close();
                ubyte[] ms = st.readAll();
                scope(exit) delete ms;
                FontData data = new BigArray!(ubyte);
                data.length = ms.length;
                data[][] = ms[];
                if (!(n.name in mFaces)) {
                    FaceStyles fstyles;
                    fstyles.styles[cast(FaceStyle)idx] = data;
                    mFaces[n.name] = fstyles;
                } else
                    mFaces[n.name].styles[cast(FaceStyle)idx] = data;
            }
        }
        mNodes = node.getSubNode("styles").copy();
        mNodes.templatetifyNodes("template");
    }

    /// Create the specified font
    //for now does some caching; because the cache is never released, this may
    //  lead to memory leaks in some situations
    Font create(FontProperties props, bool tryHard = true) {
        //xxx: tryHard etc.
        if (auto pfont = props in mCache)
            return *pfont;
        auto font = new Font(props);
        mCache[props] = font;
        return font;
    }

    /// Create (or return cached result of) a font with properties according
    /// to the corresponding entry in the font config file.
    /// tryHard = never return null (but throw an exception)
    Font loadFont(string id, bool tryHard = true) {
        if (id in mIDtoFont)
            return mIDtoFont[id];

        auto p = getStyle(id, false);

        auto f = create(p);
        if (!f) {
            if (tryHard)
                throwError("font >%s< not found (1)", id);
            return null;
        }

        mIDtoFont[id] = f;
        return f;
    }

    ///return the font style for that id
    /// fail_exception = if it couldn't be found, raise an exception
    ///   (else return a default)
    FontProperties getStyle(string id, bool fail_exception = false) {
        assert(!!mNodes, "not initialized using readFontDefinitions()");

        ConfigNode font = mNodes.findNode(id);
        if (!font) {
            if (fail_exception)
                throwError("font >%s< not found (2)", id);
            //Trace.formatln("not found: >%s<", id);
            font = mNodes.getSubNode("normal");
        }

        return font.getCurValue!(FontProperties)();
    }

    //driver uses this
    FontData findFace(string face, FaceStyle style = FaceStyle.normal) {
        FaceStyles* fstyles = face in mFaces;
        if (!fstyles)
            return null;
        if (fstyles.styles[style] !is null)
            return fstyles.styles[style];
        return fstyles.styles[FaceStyle.normal];
    }

    //for driver: determine if a face with passed style is available
    //note that while a face does not need to have all styles,
    //  it always has FaceStyle.normal
    bool faceExists(string face, FaceStyle style = FaceStyle.normal) {
        FaceStyles* fstyles = face in mFaces;
        if (!fstyles)
            return false;
        return cast(bool)(fstyles.styles[style]);
    }
}

