module framework.font;
import framework.framework;
import utils.configfile;
import utils.log;
import utils.factory;
import utils.color;
import utils.vector2;
import utils.weaklist;

import utils.stream;
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
    char[] face = "default";
    int size = 14;
    Color back = {0.0f,0.0f,0.0f,0.0f};
    Color fore = {0.0f,0.0f,0.0f,1.0f};
    bool bold;
    bool italic;
    bool underline;
    //border in pixels (0 means disabled)
    int border_width;
    Color border_color;
    //distance of the shadow from the real text in pixels (0 means disabled)
    int shadow_offset;
    Color shadow_color;

    FaceStyle getFaceStyle() {
        if (bold && italic)  return FaceStyle.boldItalic;
        if (bold && !italic) return FaceStyle.bold;
        if (!bold && italic) return FaceStyle.italic;
        return FaceStyle.normal;
    }
}

abstract class DriverFont : DriverResource {
    //w == int.max for unlimited text
    //fore, back, border_color: Color.Invalid to use predefined color
    abstract Vector2i draw(Canvas canvas, Vector2i pos, char[] text);
    abstract Vector2i textSize(char[] text, bool forceHeight);
}

abstract class FontDriver : Driver {
    abstract DriverFont createFont(FontProperties props);
}

final class Font : FrameworkResourceT!(DriverFont) {
    private {
        FontProperties mProps;
    }

    this(FontProperties props) {
        mProps = props;
    }

    override DriverFont createDriverResource() {
        return gFontManager.driver.createFont(mProps);
    }

    /// draw UTF8 encoded text (use framework singleton to instantiate it)
    /// returns position beyond last drawn glyph
    Vector2i drawText(Canvas canvas, Vector2i pos, char[] text) {
        return get().draw(canvas, pos, text);
    }

    /// return pixel width/height of the text
    /// forceHeight: if true (default), an empty string will return
    ///              (0, fontHeight) instead of (0,0)
    Vector2i textSize(char[] text, bool forceHeight = true) {
        return get.textSize(text, forceHeight);
    }

    ///return length of text that fits into width w (size(text[0..return]) <= w)
    //added long after findIndex, because findIndex seems to have quadratic
    //  complexity, and doesn't quite compute what we want
    uint textFit(char[] text, int w) {
        int i = 0;
        while (i < text.length) {
            int i2 = i + str.stride(text, i);
            int cw = textSize(text[i..i2]).x;
            if (cw > w)
                break;
            w -= cw;
            i = i2;
        }
        return i;
    }

    ///return the utf character index closest to posX
    ///(0 for start, text.length for end)
    ///posX is relative to left edge of text
    public uint findIndex(char[] text, int posX) {
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
class FontManager : ResourceManagerT!(FontDriver, Font) {
    private {
        struct FaceStyles {
            //xxx: it'd be better to just keep a file handle to the font file,
            //     or to share all FT_Face-s across all FTGlyphCache-s (srsly),
            //     but for now I'm doing this due to various circumstances
            //     FT doesn't seem to have stream abstractions either
            //for each style, the font file loaded into memory
            ubyte[][FaceStyle.max+1] styles;
        }

        Font[char[]] mIDtoFont;
        ConfigNode mNodes;
        FaceStyles[char[]] mFaces;
        Font[FontProperties] mCache;
    }

    this() {
        super("font");
    }

    /// Read a font definition file. See data/fonts.conf
    public void readFontDefinitions(ConfigNode node) {
        foreach (ConfigNode n; node.getSubNode("faces")) {
            char[][] faces = n.getCurValue!(char[][])();
            foreach (int idx, char[] faceFile; faces) {
                if (idx > FaceStyle.max)
                    break;
                scope st = gFS.open(faceFile);
                scope(exit) st.close();
                ubyte[] ms = st.readAll();
                if (!(n.name in mFaces)) {
                    FaceStyles fstyles;
                    fstyles.styles[cast(FaceStyle)idx] = ms;
                    mFaces[n.name] = fstyles;
                } else
                    mFaces[n.name].styles[cast(FaceStyle)idx] = ms;
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
    Font loadFont(char[] id, bool tryHard = true) {
        if (id in mIDtoFont)
            return mIDtoFont[id];

        auto p = getStyle(id, false);

        auto f = create(p);
        if (!f) {
            if (tryHard)
                throw new Exception("font >" ~ id ~ "< not found (1)");
            return null;
        }

        mIDtoFont[id] = f;
        return f;
    }

    ///return the font style for that id
    /// fail_exception = if it couldn't be found, raise an exception
    ///   (else return a default)
    FontProperties getStyle(char[] id, bool fail_exception = false) {
        FontProperties p;
        p.back.a = 0;
        char[] filename;

        if (!mNodes)
            throw new Exception("not initialized using readFontDefinitions()");

        ConfigNode font = mNodes.findNode(id);
        if (!font) {
            if (fail_exception)
                throw new Exception("font >" ~ id ~ "< not found (2)");
            //Trace.formatln("not found: >{}<", id);
            font = mNodes.getSubNode("normal");
        }

        p.back = font.getValue("backcolor", p.back);
        p.border_color = font.getValue("bordercolor", p.back);
        p.fore = font.getValue("forecolor", p.fore);

        //xxx not needed anymore?
        //p.back.a = font.getFloatValue("backalpha", p.back.a);
        //p.fore.a = font.getFloatValue("forealpha", p.fore.a);

        p.size = font.getIntValue("size", 12);
        p.border_width = font.getIntValue("borderwidth", 0);

        p.face = font.getStringValue("face", "default");

        p.bold = font.getBoolValue("bold", p.bold);
        p.italic = font.getBoolValue("italic", p.italic);
        p.underline = font.getBoolValue("underline", p.underline);

        return p;
    }

    //driver uses this
    ubyte[] findFace(char[] face, FaceStyle style = FaceStyle.normal) {
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
    bool faceExists(char[] face, FaceStyle style = FaceStyle.normal) {
        FaceStyles* fstyles = face in mFaces;
        if (!fstyles)
            return false;
        return cast(bool)(fstyles.styles[style]);
    }
}

