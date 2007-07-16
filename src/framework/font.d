module framework.font;
import framework.framework;
import utils.configfile;
import utils.log;

struct FontProperties {
    int size = 14;
    Color back = {0.0f,0.0f,0.0f,1.0f};
    Color fore = {1.0f,1.0f,1.0f,1.0f};
    bool bold;
    bool italic;
    bool underline;
}

public class Font {
    /// draw UTF8 encoded text (use framework singleton to instantiate it)
    public abstract void drawText(Canvas canvas, Vector2i pos, char[] text);
    /// like drawText(), but try not to draw beyond "width"
    /// instead the text is cut and, unlike clipping, will be ended with "..."
    public abstract void drawTextLimited(Canvas canvas, Vector2i pos, int width,
        char[] text);
    /// same for UTF-32
    //public abstract void drawText(Canvas canvas, Vector2i pos, dchar[] text);
    /// return pixel width/height of the text
    public abstract Vector2i textSize(char[] text);
    //public abstract Vector2i textSize(dchar[] text);

    public abstract FontProperties properties();
}

//NOTE: this class is considered to be "abstract", and must be created by the
//  framework singleton
//i.e. framework implementations can replace this
class FontManager {
    private Font[char[]] mIDtoFont;
    private ConfigNode mNodes;

    /// Create (or return cached result of) a font with properties according
    /// to the corresponding entry in the font config file.
    /// tryHard = never return null (but throw an exception)
    public Font loadFont(char[] id, bool tryHard = true) {
        if (id in mIDtoFont)
            return mIDtoFont[id];

        FontProperties p;
        p.back.a = 0;
        char[] filename;

        if (!mNodes)
            throw new Exception("not initialized using readFontDefinitions()");

        ConfigNode font = mNodes.findNode(id);
        if (!font) {
            //std.stdio.writefln("not found: >%s<", id);
            font = mNodes.getSubNode("default");
        }

        Color tmp;
        if (parseColor(font.getStringValue("backcolor"), tmp)) {
            p.back = tmp;
        }
        if (parseColor(font.getStringValue("forecolor"), tmp)) {
            p.fore = tmp;
        }

        p.back.a = font.getFloatValue("backalpha", p.back.a);
        p.fore.a = font.getFloatValue("forealpha", p.fore.a);

        p.size = font.getIntValue("size", 12);

        filename = font.getStringValue("filename");

        if (!gFramework.fs.exists(filename)) {
            filename = mNodes.getSubNode("default")
                .getStringValue("filename", "font.ttf");
        }

        p.bold = font.getBoolValue("bold", p.bold);
        p.italic = font.getBoolValue("italic", p.italic);
        p.underline = font.getBoolValue("underline", p.underline);

        Font f = gFramework.loadFont(gFramework.fs.open(filename), p);

        if (!f) {
            if (tryHard)
                throw new Exception("font >" ~ id ~ "< not found");
            return null;
        }

        mIDtoFont[id] = f;
        return f;
    }

    /// Read a font definition file. See data/fonts.conf
    public void readFontDefinitions(ConfigNode node) {
        mNodes = node.clone();
        mNodes.templatetifyNodes("template");
    }
}

