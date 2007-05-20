module levelgen.generator;

import levelgen.level;
import levelgen.renderer;
import levelgen.genrandom : GenRandomLevel;
import levelgen.placeobjects;
import framework.framework;
import utils.configfile : ConfigNode;
import utils.vector2;
import utils.log;
import std.stream;
import str = std.string;
import conv = std.conv;
import rand = std.random;

debug {
    import std.perf;
    import utils.time;
}

/// level generator
public class LevelGenerator {
    private ConfigNode mConfig;
    private Log mLog;

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
            Stream s = gFramework.fs.open(value);
            res = getFramework.loadImage(s, Transparency.Colorkey);
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

    //maybe this should rather be implemented by genrandom.d?
    private void readParams(ConfigNode node, GenRandomLevel g) {
        //tedious, maybe should replaced by an associative array or so
        float tmp = node.getFloatValue("pix_epsilon");
        if (tmp == tmp) {
            g.config_pix_epsilon = tmp;
        }
        tmp = node.getFloatValue("pix_filter");
        if (tmp == tmp)
            g.config_pix_filter = tmp;
        int tmpint = node.getIntValue("subdivision_steps", -1);
        if (tmpint >= 0)
            g.config_subdivision_steps = tmpint;
        tmp = node.getFloatValue("removal_aggresiveness");
        if (tmp == tmp)
            g.config_removal_aggresiveness = tmp;
        tmp = node.getFloatValue("min_subdiv_length");
        if (tmp == tmp)
            g.config_min_subdiv_length = tmp;
        tmp = node.getFloatValue("front_len_ratio_add");
        if (tmp == tmp)
            g.config_front_len_ratio_add = tmp;
        tmp = node.getFloatValue("len_ratio_add");
        if (tmp == tmp)
            g.config_len_ratio_add = tmp;
        tmp = node.getFloatValue("front_len_ratio_remove");
        if (tmp == tmp)
            g.config_front_len_ratio_remove = tmp;
        tmp = node.getFloatValue("len_ratio_remove");
        if (tmp == tmp)
            g.config_len_ratio_remove = tmp;
        tmp = node.getFloatValue("remove_or_add");
        if (tmp == tmp)
            g.config_remove_or_add = tmp;
    }

    private Level generateRandom(uint width, uint height,
        ConfigNode template_node)
    {
        Surface loadBorderTex(ConfigNode texNode)
        {
            Surface tex;
            char[] tex_name = texNode.getStringValue("texture");
            if (tex_name.length > 0) {
                tex = readTexture(tex_name, false);
            } else {
                //sucky color-border hack
                int height = texNode.getIntValue("height", 1);
                tex = getFramework.createSurface(Vector2i(1, height),
                    DisplayFormat.Best, Transparency.None);
                auto col = Color(0,0,0);
                parseColor(texNode.getStringValue("color"), col);
                auto canvas = tex.startDraw();
                canvas.drawFilledRect(Vector2i(0, 0), tex.size, col);
                canvas.endDraw();
            }
            return tex;
        }

        auto gen = new GenRandomLevel(width, height);

        bool isCave = template_node.getBoolValue("is_cave");
        if (isCave) {
            auto tex = readTexture(template_node.getStringValue("texture"),
                false);
            auto marker = parseMarker(template_node.getStringValue("marker"));
            gen.setAsCave(tex, marker);
        }

        readParams(template_node, gen);

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

        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }

        mLog("generating level...");

        gen.generate();

        debug {
            counter.stop();
            mLog("%s", timeMusecs(counter.microseconds));
            counter.start();
        }

        mLog("rendering level...");

        LevelRenderer renderer = new LevelRenderer(width, height, mLog);
        gen.preRender(renderer);

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
            Surface tex_up, tex_down;
            if (border.findNode("texture_both")) {
                tex_up = loadBorderTex(border.getSubNode("texture_both"));
                tex_down = tex_up;
            } else {
                if (do_up)
                    tex_up = loadBorderTex(border.getSubNode("texture_up"));
                if (do_down)
                    tex_down = loadBorderTex(border.getSubNode("texture_down"));
            }
            renderer.drawBorder(marker_a, marker_b, do_up, do_down, tex_up, tex_down);
        }

        debug {
            counter.stop();
            mLog("%s", timeMusecs(counter.microseconds));

            gen.dumpDebuggingStuff(renderer);
        }

        mLog("placing objects");

        PlaceableObject[3] bridge;
        auto placer = new PlaceObjects(mLog, renderer);
        bridge[0] = placer.createObject(readTexture("bridge.png", false));
        bridge[1] = placer.createObject(readTexture("bridge-l.png", false));
        bridge[2] = placer.createObject(readTexture("bridge-r.png", false));
        placer.placeBridges(10,10, bridge);

        auto ret = renderer.render();
        ret.isCave = isCave;

        //water level from bottom, relative value
        float waterLevel = template_node.getFloatValue("waterlevel");
        //level needs absolute pixel value
        ret.waterLevel = cast(uint)(waterLevel*height);

        mLog("done.");
        return ret;
    }

    /// generate a random level based on a template
    public Level generateRandom(uint width, uint height, char[] templatename) {
        mLog("template '%s', %dx%d", templatename, width, height);

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

        if (count == 0) {
            mLog("no level templates!");
            return null;
        }

        //not found, pick a random one instead
        uint pick = rand.rand() % count;
        foreach(char[] name, ConfigNode template_node; templates) {
            if (pick == 0) {
                mLog("picked random template: '%s'", template_node
                    .getStringValue("name"));
                return generateRandom(width, height, template_node);
            }
            pick--;
        }

        assert(false);
        return null;
    }

    /// like in Worms(tm): allow user images, but auto-place worms, boxes, etc.
    public Level generateFromImage(Surface image) {
        //TODO: add code
        return null;
    }

    public this() {
        mLog = registerLog("LevelGenerator");
    }
}