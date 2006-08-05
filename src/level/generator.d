module level.generator;

import level.level;
import level.renderer;
import level.genrandom;// : GenRandomLevel;
import framework.framework;// : Surface;
import utils.configfile;// : ConfigNode;
import filesystem;
import std.stream;
import str = std.string;
import conv = std.conv;
import rand = std.random;

/// level generator
public class LevelGenerator {
    private ConfigNode mConfig;

    /// node must correspond to the "levelgen" section
    public void config(ConfigNode node) {
        mConfig = node;
    }
    
    private static Lexel parseMarker(char[] value) {
        static char[][] marker_strings = ["FREE", "LAND", "SOLID_LAND"];
        static Lexel[] marker_values = [Lexel.FREE, Lexel.LAND,
            Lexel.SOLID_LAND];
        for (uint i = 0; i < marker_strings.length; i++) {
            if (str.icmp(value, marker_strings[i]) == 0) {
                return marker_values[i];
            }
        }
        //else explode
        throw new Exception("invalid marker value in configfile");
    }
    
    private static Surface readTexture(char[] value, bool accept_null) {
        Surface res;
        if (value == "-") {
            if (accept_null)
                return null;
        } else {
            Stream s = gFileSystem.openData(value);
            res = getFramework.loadImage(s);
            s.close();
        }
        if (res is null) {
            throw new Exception("couldn't load texture: "~value);
        }
        return res;
    }
    
    //some of this stuff maybe should be moved into configfile.d
    private template ReadListTemplate(T) {
         T[] readList(ConfigNode node, T delegate(char[] item) translate) {
            T[] res;
            //(the name isn't needed (and should be empty))
            foreach(char[] name, char[] value; node) {
                T item = translate(value);
                res ~= item;
            }
            return res;
         }
    }
    
    private Vector2f[] readPointList(ConfigNode node) {
        //is that horrible or beautiful?
        return ReadListTemplate!(Vector2f).readList(node, (char[] item) {
            //a bit inefficient, but that doesn't matter
            //(as long as nobody puts complete vector graphics there...)
            char[][] items = str.split(item);
            if (items.length != 2) {
                throw new Exception("invalid point value");
            }
            Vector2f pt;
            pt.x = conv.toFloat(items[0]);
            pt.y = conv.toFloat(items[1]);
            return pt;
        });
    }
    private uint[] readUIntList(ConfigNode node) {
        return ReadListTemplate!(uint).readList(node, (char[] item) {
            return conv.toUint(item);
        });
    }
    
    private bool parseColor(char[] s, Color color) {
        char[][] values = str.split(s);
        if (values.length < 3 || values.length > 4)
            return false;
        try {
            float r = conv.toFloat(values[0]);
            float g = conv.toFloat(values[1]);
            float b = conv.toFloat(values[2]);
            float a = 1.0f;
            if (values.length > 3) {
                a = conv.toFloat(values[3]);
            }
            color = Color(r, g, b, a);
            return true;
        } catch (conv.ConvOverflowError e) {
        } catch (conv.ConvError e) {
        }
        return false;
    }
    
    private Level generateRandom(uint width, uint height,
        ConfigNode template_node)
    {
        auto gen = new GenRandomLevel(width, height);
        
        if (template_node.getBoolValue("is_cave")) {
            auto tex = readTexture(template_node.getStringValue("texture"),
                false);
            auto marker = parseMarker(template_node.getStringValue("marker"));
            gen.setAsCave(tex, marker);
        }
        
        ConfigNode polys = template_node.getSubNode("polygons");
        foreach(char[] name, ConfigNode polygon; polys) {
            Vector2f[] points = readPointList(polygon.getSubNode("points"));
            //scale the points
            for (uint i = 0; i < points.length; i++) {
                points[i].x *= width;
                points[i].y *= height;
            }
            uint[] nosubdiv = readUIntList(polygon.getSubNode("nochange"));
            auto tex = readTexture(polygon.getStringValue("texture"), true);
            auto marker = parseMarker(polygon.getStringValue("marker"));
            auto visible = polygon.getBoolValue("visible", true);
            auto changeable = polygon.getBoolValue("changeable", true);
            gen.addPolygon(points, nosubdiv, tex, marker, changeable, visible);
        }
        
        auto ckey = Color(0,0,0,0);
        LevelRenderer renderer = new LevelRenderer(width, height, ckey);
        gen.generate(renderer);
        
        //the least important part is the longest
        ConfigNode borders = template_node.getSubNode("borders");
        foreach(char[] name, ConfigNode border; borders) {
            auto marker_a = parseMarker(border.getStringValue("marker_a"));
            auto marker_b = parseMarker(border.getStringValue("marker_b"));
            bool do_up = false, do_down = false;
            char[] dir = border.getStringValue("direction");
            if (str.icmp(dir, "up") == 0) {
                do_up = true;
            } else if (str.icmp(dir, "down") == 0) {
                do_down = true;
            } else {
                do_up = do_down = true;
            }
            char[] tex_name = border.getStringValue("texture");
            Surface tex;
            if (tex_name.length > 0) {
                tex = readTexture(tex_name, false);
            } else {
                //sucky color-border hack
                int height = border.getIntValue("height", 1);
                tex = getFramework.createSurface(1, height);
                auto col = Color(0,0,0);
                parseColor(border.getStringValue("color"), col);
                auto canvas = tex.startDraw();
                canvas.drawFilledRect(Vector2i(0, 0), tex.size, col);
                tex.endDraw();
            }
            if (do_up)
                renderer.drawBorder(marker_a, marker_b, true, tex);
            if (do_down)
                renderer.drawBorder(marker_a, marker_b, false, tex);
        }
        
        return renderer.render();
    }
    
    /// generate a random level based on a template
    public Level generateRandom(uint width, uint height, char[] templatename) {
        //search template
        ConfigNode templates = mConfig.getSubNode("templates");
        uint count = 0;
        foreach(char[] name, ConfigNode template_node; templates) {
            //xxx needs a weaker string comparision
            if (templatename.length > 0 &&
                template_node.getStringValue("name", "") == templatename)
            {
                return generateRandom(width, height, template_node);
            }
            count++;
        }
        
        //not found, pick a random one instead
        uint pick = rand.rand() % count;
        foreach(char[] name, ConfigNode template_node; templates) {
            if (pick == 0) {
                return generateRandom(width, height, template_node);
            }
            pick--;
        }
        
        return null;
    }

    /// like in Worms(tm): allow user images, but auto-place worms, boxes, etc.
    public Level generateFromImage(Surface image) {
        //TODO: add code
        return null;
    }
}
