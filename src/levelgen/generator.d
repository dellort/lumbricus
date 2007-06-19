module levelgen.generator;

import levelgen.level;
import levelgen.renderer;
import levelgen.genrandom : GenRandomLevel, LevelGeometry, GeneratorConfig;
import levelgen.placeobjects;
import game.animation;
import game.common;
import game.bmpresource;
import framework.framework;
import framework.filesystem;
import utils.configfile;
import utils.vector2;
import utils.output;
import utils.log;
import std.stream;
import str = std.string;
import conv = std.conv;
import rand = std.random;

debug {
    import std.perf;
    import utils.time;
}

private Log mLog;

static this() {
    mLog = registerLog("LevelGenerator");
}

class LevelObjects {
}

/// geometry template, all information from an item in levelgen.conf
public class LevelTemplate {
    private char[] mName;
    private char[] mDescription;
    private LevelGeometry mGeometry;
    private GeneratorConfig mConfig;
    private uint mWaterLevel;

    /// template node as in levelgen.conf
    this(ConfigNode from) {
        mName = from.name;
        mDescription = from["description"];

        mGeometry = new LevelGeometry();
        mGeometry.loadFrom(from);
        mConfig.loadFrom(from);

        float waterLevel = from.getFloatValue("waterlevel");
        //level needs absolute pixel value
        mWaterLevel = cast(uint)(waterLevel*mGeometry.size.y);
    }

    bool isCave() {
        return mGeometry.caveness != Lexel.Null;
    }

    LevelGeometry geometry() {
        return mGeometry;
    }

    uint waterLevel() {
        return mWaterLevel;
    }

    char[] name() {
        return mName;
    }

    /// generate subdivided geometry from this level
    /// (final subdivision for smooth level curves is done in renderer.d)
    public LevelGeometry generate() {
        auto gen = new GenRandomLevel();
        gen.readFrom(mGeometry);
        gen.setConfig(mConfig);

        mLog("rendering level...");

        auto res = gen.generate();

        mLog("done.");

        return res;
    }
}

public class LevelTheme {
    char[] name;

    Color borderColor;
    Surface backImage;
    Surface skyGradient;
    Surface skyBackdrop;
    Color skyColor;
    AnimationResource skyDebris;
    //incredibly evil hack
    Surface[] objects;
    Surface[3] bridge;
    Surface[Lexel] markerTex;
    Border[] borders;

    struct Border {
        bool[2] action;
        Lexel[2] markers;
        Surface[2] textures;
    }

    private ConfigNode gfxTexNode;
    private char[] mGfxPath;

    private static Surface readTexture(char[] value, bool accept_null) {
        Surface res;
        if (value == "-" || value == "") {
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

    private Surface loadBorderTex(ConfigNode texNode) {
        Surface tex;
        char[] tex_name = texNode.getStringValue("texture");
        if (tex_name.length > 0) {
            tex = globals.resources.resource!(BitmapResource)
                (texNode.getPathValue("texture")).get();
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

    private Surface readMarkerTex(char[] markerId, bool accept_null) {
        Surface res;
        char[] texFile = gfxTexNode.getStringValue(markerId);
        if (texFile == "-" || texFile == "") {
            if (accept_null)
                return null;
        } else {
            res = globals.resources.resource!(BitmapResource)
                (gfxTexNode.getPathValue(markerId)).get();
        }
        if (res is null) {
            throw new Exception("couldn't load texture for marker: "~markerId);
        }
        return res;
    }

    this(ConfigNode gfxNode) {
        globals.resources.loadResources(gfxNode);
        gfxTexNode = gfxNode.getSubNode("marker_textures");
        name = gfxNode["name"];

        //the least important part is the longest
        ConfigNode cborders = gfxNode.getSubNode("borders");
        foreach(char[] name, ConfigNode border; cborders) {
            Border b;
            b.markers[0] = parseMarker(border.getStringValue("marker_a"));
            b.markers[1] = parseMarker(border.getStringValue("marker_b"));
            int dir = border.selectValueFrom("direction", ["up", "down"]);
            if (dir == 0) {
                b.action[0] = true;
            } else if (dir == 1) {
                b.action[1] = true;
            } else {
                b.action[0] = b.action[1] = true;
            }
            if (border.findNode("texture_both")) {
                b.textures[0] = loadBorderTex(border.getSubNode("texture_both"));
                b.textures[1] = b.textures[0];
            } else {
                if (b.action[0])
                    b.textures[0] = loadBorderTex(border.getSubNode("texture_up"));
                if (b.action[1])
                    b.textures[1] = loadBorderTex(border.getSubNode("texture_down"));
            }

            borders ~= b;
        }

        mLog("not placing objects");

        ConfigNode bridgeNode = gfxNode.getSubNode("bridge");
        /*PlaceableObject[3] bridge;
        auto placer = new PlaceObjects(mLog, renderer);
        bridge[0] = placer.createObject(readTexture(gfxPath ~
            bridgeNode.getStringValue("segment"), false));
        bridge[1] = placer.createObject(readTexture(gfxPath ~
            bridgeNode.getStringValue("left"), false));
        bridge[2] = placer.createObject(readTexture(gfxPath ~
            bridgeNode.getStringValue("right"), false));
        placer.placeBridges(10,10, bridge);*/
        bridge[0] = globals.resources.resource!(BitmapResource)
            (bridgeNode.getPathValue("segment")).get();
        bridge[1] = globals.resources.resource!(BitmapResource)
            (bridgeNode.getPathValue("left")).get();
        bridge[2] = globals.resources.resource!(BitmapResource)
            (bridgeNode.getPathValue("right")).get();

        ConfigNode objectsNode = gfxNode.getSubNode("objects");
        foreach (char[] id, ConfigNode onode; objectsNode) {
            objects ~= globals.resources.resource!(BitmapResource)
            (onode.getPathValue("image")).get();
        }

        ConfigNode skyNode = gfxNode.getSubNode("sky");
        char[] skyGradientTex = skyNode.getPathValue("gradient");
        if (skyGradientTex.length > 0)
            skyGradient = globals.resources.resource!(BitmapResource)
                (skyGradientTex).get();
        parseColor(skyNode.getStringValue("skycolor"),skyColor);
        char[] skyBackTex = skyNode.getPathValue("backdrop");
        if (skyBackTex.length > 0)
            skyBackdrop = globals.resources.resource!(BitmapResource)
                (skyBackTex).get();
        if (skyNode.exists("debris")) {
            skyDebris = globals.resources.resource!(AnimationResource)
                (skyNode.getPathValue("debris"));
        }

        backImage = globals.resources.resource!(BitmapResource)
            (gfxNode.getPathValue("soil_tex")).get();
        parseColor(gfxNode.getStringValue("bordercolor"),
            borderColor);

        //hmpf, read all known markers
        markerTex[Lexel.SolidSoft] = readMarkerTex("LAND", false);
        markerTex[Lexel.SolidHard] = readMarkerTex("SOLID_LAND", false);
    }
}

/// level generator
public class LevelGenerator {
    private ConfigNode mConfig;

    /// node must correspond to the "levelgen" section
    public void config(ConfigNode node) {
        mConfig = node;
    }

    private void doRenderGeometry(LevelBitmap renderer, LevelGeometry geometry,
        LevelTheme gfx)
    {
        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }

        //geometry
        foreach (LevelGeometry.Polygon p; geometry.polygons) {
            auto surface = gfx.markerTex[p.marker];
            Vector2i texoffset;
            texoffset.x = cast(int)(p.texoffset.x * surface.size.x);
            texoffset.y = cast(int)(p.texoffset.y * surface.size.y);
            renderer.addPolygon(p.points, p.nochange, p.visible, texoffset,
                surface, p.marker);
        }

        debug {
            counter.stop();
            mLog("geometry: %s", timeMusecs(counter.microseconds));
            counter = new PerformanceCounter();
            counter.start();
        }

        //borders, must come after geometry
        foreach (LevelTheme.Border b; gfx.borders) {
            renderer.drawBorder(b.markers[0], b.markers[1], b.action[0],
                b.action[1], b.textures[0], b.textures[1]);
        }

        debug {
            counter.stop();
            mLog("borders: %s", timeMusecs(counter.microseconds));
        }
    }

    //fill in most of Level members
    private Level doCreateLevel(Level level, LevelTemplate level_templ,
        LevelTheme gfx)
    {
        level.waterLevel = level_templ.waterLevel;
        level.isCave = level_templ.isCave;

        level.mBorderColor = gfx.borderColor;
        level.mBackImage = gfx.backImage;

        level.skyGradient = gfx.skyGradient;
        level.skyBackdrop = gfx.skyBackdrop;
        level.skyColor = gfx.skyColor;
        level.skyDebris = gfx.skyDebris;

        return level;
    }

    /// render a level using (already generated) geometry in "geometry",
    /// object placments in "objects", graphics from "gfx",
    /// and the rest in "level_templ"
    public Level renderLevel(LevelGeometry geometry, LevelObjects objects,
        LevelTemplate level_templ, LevelTheme gfx)
    {
        auto renderer = new LevelBitmap(geometry.size);
        doRenderGeometry(renderer, geometry, gfx);
        //xxx: render objects, using the placements in "objects"
        //create the level; don't ask me why the renderer creates it
        Level level = renderer.createLevel(true);
        doCreateLevel(level, level_templ, gfx);
        return level;
    }

    /// render a level, auto-generated geometry
    ///     saveto = if !is null, store generated metadata into it
    public Level renderLevel(LevelTemplate level_templ, LevelTheme gfx,
        ConfigNode saveto = null)
    {
        auto gen = level_templ.generate();
        //actual rendering etc. goes on here
        Level level = renderLevel(gen, null, level_templ, gfx);
        //maybe save
        if (saveto !is null) {
            //general
            saveto["template"] = level_templ.name;
            saveto["gfx"] = gfx.name;
            //geometry
            gen.saveTo(saveto);
            //xxx object positions
        }
        return level;
    }

    public Level renderSavedLevel(ConfigNode saved) {
        //load
        LevelTemplate templ = findTemplate(saved["template"]);
        LevelTheme gfx = findGfx(saved["gfx"]);
        LevelGeometry geo = new LevelGeometry();
        geo.loadFrom(saved);

        //render
        Level level = renderLevel(geo, null, templ, gfx);

        return level;
    }

    public Level generateRandom(LevelTemplate templ, LevelTheme gfx) {
        mLog("generating level... template='%s', gfx='%s'", templ.name, gfx.name);

        debug {
            auto counter = new PerformanceCounter();
            counter.start();
        }

        Level level = renderLevel(templ, gfx);

        debug {
            counter.stop();
            mLog("done in %s", timeMusecs(counter.microseconds));
            counter.start();
        }

        return level;
    }

    public LevelTheme findGfx(char[] name) {
        //open graphics set
        char[] gfxPath = "/level/" ~ name ~ "/";
        ConfigNode gfxNode = globals.loadConfig(gfxPath ~ "level");
        //use some violence!
        gfxNode["gfxpath"] = gfxPath;
        gfxNode["name"] = name;
        return new LevelTheme(gfxNode);
    }

    public LevelTemplate findTemplate(char[] name, bool canfail = false) {
        auto res = mConfig.getSubNode("templates").findNode(name);
        if (!res) {
            if (!canfail)
                throw new Exception("template '" ~ name ~ " not found");
            return null;
        }
        return new LevelTemplate(res);
    }

    /// generate a random level based on a template
    public Level generateRandom(char[] templatename, char[] gfxSet)
    {
        mLog("template '%s'", templatename ? templatename : "[random]");

        LevelTheme gfx = findGfx(gfxSet);
        LevelTemplate templ = findRandomTemplate(templatename);

        return generateRandom(templ, gfx);
    }

    /// pick a template with name 'name'; if 'name' is not found, return a
    /// random template from the list
    public LevelTemplate findRandomTemplate(char[] name = "") {
        LevelTemplate templ = findTemplate(name, true);

        if (templ)
            return templ;

        auto templates = mConfig.getSubNode("templates");
        uint count = templates.count;
        if (count == 0) {
            mLog("no level templates!");
            return null;
        }

        //not found, pick a random one instead
        uint pick = rand.rand() % count;
        foreach(ConfigNode template_node; templates) {
            assert(template_node !is null);
            if (pick == 0) {
                mLog("picked random template: '%s'", template_node.name);
                return findTemplate(template_node.name);
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
}
