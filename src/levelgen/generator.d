module levelgen.generator;

import levelgen.level;
import levelgen.renderer;
import levelgen.genrandom : GenRandomLevel, LevelGeometry, GeneratorConfig;
import levelgen.placeobjects;
import game.animation;
import framework.restypes.bitmap;
import framework.framework;
import framework.filesystem;
import utils.configfile;
import utils.vector2;
import utils.output;
import utils.log;
import utils.array;
import std.stream;
import str = std.string;
import conv = std.conv;
import rand = std.random;
import utils.misc;

debug {
    import std.perf;
    import utils.time;
}

private Log mLog;

static this() {
    mLog = registerLog("LevelGenerator");
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

    Vector2i size() {
        return mGeometry.size;
    }

    uint waterLevel() {
        return mWaterLevel;
    }

    char[] name() {
        return mName;
    }

    char[] description() {
        return mDescription;
    }

    /// generate subdivided geometry from this level
    /// (final subdivision for smooth level curves is done in renderer.d)
    public LevelGeometry generate() {
        auto gen = new GenRandomLevel();
        gen.readFrom(mGeometry);
        gen.setConfig(mConfig);

        mLog("generating level...");

        auto res = gen.generate();

        mLog("done.");

        return res;
    }
}

//xxx are those generic enough to be moved to utils.array?
//    relies on item.name() to exist

///Find a named item in an array and fill res with a reference to it
///Works with structs and classes, but items need to have a property ".name"
///returns true on success, false if item was not found
private bool find(T)(T[] items, out T res, char[] name) {
    foreach (ref T t; items) {
        if (t.name == name) {
            res = t;
            return true;
        }
    }
    return false;
}

///Like find(), but chooses a random item if the specified item was not found
///returns false if the array was empty
private bool findRandom(T)(T[] items, out T res, char[] name = "") {
    if (items.find(res, name))
        return true;

    if (items.length > 0) {
        uint pick = rand.rand() % items.length;
        res = items[pick];
        return true;
    }

    return false;
}

public class LevelTheme {
    char[] name;

    Color borderColor;
    Surface backImage;
    Surface skyGradient;
    Surface skyBackdrop;
    Color skyColor;
    AnimationResource skyDebris;
    PlaceableObject[char[]] objects;
    PlaceableObject[3] bridge;
    Surface[Lexel] markerTex;
    Border[] borders;

    struct Border {
        bool[2] action;
        Lexel[2] markers;
        Surface[2] textures;
    }

    private ConfigNode gfxTexNode;
    private char[] mGfxPath;

    public PlaceableObject findObject(char[] name) {
        return objects[name];
    }

    private static Surface readTexture(char[] value, bool accept_null) {
        Surface res;
        if (value == "-" || value == "") {
            if (accept_null)
                return null;
        } else {
            Stream s = gFramework.fs.open(value);
            res = gFramework.loadImage(s, Transparency.Colorkey);
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
            tex = gFramework.resources.resource!(BitmapResource)
                (texNode.getPathValue("texture")).get();
        } else {
            //sucky color-border hack
            int height = texNode.getIntValue("height", 1);
            tex = gFramework.createSurface(Vector2i(1, height),
                Transparency.None);
            auto col = Color(0,0,0);
            col.parse(texNode.getStringValue("color"));
            auto canvas = gFramework.startOffscreenRendering(tex);
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
            res = gFramework.resources.resource!(BitmapResource)
                (gfxTexNode.getPathValue(markerId)).get();
        }
        if (res is null) {
            throw new Exception("couldn't load texture for marker: "~markerId);
        }
        return res;
    }

    this(ConfigNode gfxNode) {
        gFramework.resources.loadResources(gfxNode);
        gfxTexNode = gfxNode.getSubNode("marker_textures");
        name = gfxNode["name"];
        assert(name.length > 0);

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

        //xxx fix this (objects should have more than just a bitmap)
        PlaceableObject createObject(char[] bitmap, bool try_place) {
            auto bmp = gFramework.resources.resource!(BitmapResource)(bitmap).get();
            //use ressource name as id
            auto po = new PlaceableObject(bitmap, bmp, try_place);
            objects[po.id] = po;
            return po;
        }

        ConfigNode bridgeNode = gfxNode.getSubNode("bridge");
        bridge[0] = createObject(bridgeNode.getPathValue("segment"), false);
        bridge[1] = createObject(bridgeNode.getPathValue("left"), false);
        bridge[2] = createObject(bridgeNode.getPathValue("right"), false);

        ConfigNode objectsNode = gfxNode.getSubNode("objects");
        foreach (char[] id, ConfigNode onode; objectsNode) {
            createObject(onode.getPathValue("image"), true);
        }

        ConfigNode skyNode = gfxNode.getSubNode("sky");
        char[] skyGradientTex = skyNode.getPathValue("gradient");
        if (skyGradientTex.length > 0)
            skyGradient = gFramework.resources.resource!(BitmapResource)
                (skyGradientTex).get();
        skyColor.parse(skyNode.getStringValue("skycolor"));
        char[] skyBackTex = skyNode.getPathValue("backdrop");
        if (skyBackTex.length > 0)
            skyBackdrop = gFramework.resources.resource!(BitmapResource)
                (skyBackTex).get();
        if (skyNode.exists("debris")) {
            skyDebris = gFramework.resources.resource!(AnimationResource)
                (skyNode.getPathValue("debris"));
        }

        backImage = gFramework.resources.resource!(BitmapResource)
            (gfxNode.getPathValue("soil_tex")).get();
        borderColor.parse(gfxNode.getStringValue("bordercolor"));

        //hmpf, read all known markers
        markerTex[Lexel.SolidSoft] = readMarkerTex("LAND", false);
        markerTex[Lexel.SolidHard] = readMarkerTex("SOLID_LAND", false);
    }
}

/// level generator
public class LevelGenerator {
    private {
        LevelTemplate[] mTemplates;
        ConfigNode mGfxNodes;
        char[][] mGfxThemes;
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
            Surface surface = aaIfIn(gfx.markerTex, p.marker);
            Vector2i texoffset;
            if (surface) {
                texoffset.x = cast(int)(p.texoffset.x * surface.size.x);
                texoffset.y = cast(int)(p.texoffset.y * surface.size.y);
            }
            renderer.addPolygon(p.points, p.visible, texoffset, surface,
                p.marker, p.changeable, p.nochange, 5, 0.25f);
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

    /// render a fast, ugly preview; just to see the geometry
    /// returns a surface, which shall be freed by the user itself
    //xxx completely untested
    public Surface renderPreview(LevelGeometry geo, Vector2i size, Color land,
        Color hard_land, Color free)
    {
        Surface createPixelSurface(Color c) {
            SurfaceData s;
            s.data.length = 4;
            s.pitch = 4;
            s.size = Vector2i(1);
            *cast(uint*)(s.data.ptr) = c.toRGBA32();
            return new Surface(s);
        }

        //oh well...
        Surface[Lexel] markers;
        markers[Lexel.SolidSoft] = createPixelSurface(land);
        markers[Lexel.SolidHard] = createPixelSurface(hard_land);
        markers[Lexel.Null] = createPixelSurface(free);

        Vector2f scale = toVector2f(size) / toVector2f(geo.size);
        auto renderer = new LevelBitmap(size);

        //draw background (not drawn when it's not a cave!)
        //(actually, a FillRect would be enough, but...)
        renderer.addPolygon([Vector2i(), size.X, size, size.Y], true,
            Vector2i(), markers[Lexel.Null], Lexel.Null, false, null, 0, 0);

        foreach (LevelGeometry.Polygon p; geo.polygons) {
            //scale down the points first
            auto npts = p.points.dup;
            foreach (inout Vector2i point; npts) {
                point = toVector2i(toVector2f(point).mulEntries(scale));
            }
            renderer.addPolygon(npts, p.visible, Vector2i(0, 0),
                markers[p.marker], p.marker, p.changeable, p.nochange, 1, 0.25f);
        }

        foreach (bitmap; markers) {
            bitmap.free();
        }

        return renderer.releaseImage();
    }

    //try to place the objects (listed in gfx) onto the level bitmap in renderer
    //both draws the objects into renderer and returns a list of placed obejcts
    //(this list is used to implement level saving/loading, else it's useless)
    //NOTE: this is how Worms(TM) obviously works, i.e. there you can paint
    //      your own level and Worms(TM) still can place objects into it
    //xxx: but maybe I'll use data from LevelTemplate to see in which areas
    //     object placement would be worth to try (reason for templ param)
    private LevelObjects doPlaceObjects(LevelBitmap renderer,
        LevelTemplate templ, LevelTheme gfx)
    {
        auto placer = new PlaceObjects(renderer);
        foreach (PlaceableObject o; gfx.objects) {
            if (o.tryPlace)
                placer.placeObjects(10, 10, o);
        }
        placer.placeBridges(10, 10, gfx.bridge);
        return placer.objects;
    }

    //render the same objects as doPlaceObjects() did, using its return value
    private void doRenderObjects(LevelBitmap renderer, LevelObjects objs,
        LevelTheme gfx)
    {
        foreach (LevelObjects.PlaceItem item; objs.items) {
            PlaceableObject obj = gfx.findObject(item.id);
            renderPlacedObject(renderer, obj.bitmap, item.params);
        }
    }

    //fill in most of Level members, destroy renderer (free its drawing surface)
    private Level doCreateLevel(LevelBitmap renderer, LevelTemplate level_templ,
        LevelTheme gfx)
    {
        Level level = new Level();

        renderer.createLevel(level, true);

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

    /// render a level, auto-generated geometry
    ///     saveto = if !is null, store generated metadata into it
    public Level renderLevel(LevelTemplate level_templ, LevelTheme gfx,
        ConfigNode saveto = null)
    {
        return renderLevelGeometry(level_templ, null, gfx, saveto);
    }

    /// like renderLevel(), but the geometry was already generated and is in g.
    /// if g id null, generate it from level_templ
    public Level renderLevelGeometry(LevelTemplate level_templ, LevelGeometry g,
        LevelTheme gfx, ConfigNode saveto = null)
    {
        assert(level_templ !is null);
        assert(gfx !is null);
        mLog("generating level... template='%s', gfx='%s'",
            level_templ.name, gfx.name);

        //actual rendering etc. goes on here
        auto renderer = new LevelBitmap(level_templ.size);
        auto gen = g ? g : level_templ.generate();
        doRenderGeometry(renderer, gen, gfx);
        auto objects = doPlaceObjects(renderer, level_templ, gfx);

        //maybe save
        if (saveto !is null) {
            //general
            saveto["template"] = level_templ.name;
            saveto["gfx"] = gfx.name;
            //geometry
            gen.saveTo(saveto.getSubNode("geometry"));
            //object positions
            objects.saveTo(saveto.getSubNode("objects"));
        }

        return doCreateLevel(renderer, level_templ, gfx);
    }

    public Level renderSavedLevel(ConfigNode saved) {
        //load
        LevelTemplate templ = findTemplate(saved["template"]);
        LevelTheme gfx = findGfx(saved["gfx"]);
        LevelGeometry geo = new LevelGeometry();
        geo.loadFrom(saved.getSubNode("geometry"));
        LevelObjects objs = new LevelObjects();
        objs.loadFrom(saved.getSubNode("objects"));

        //render
        auto renderer = new LevelBitmap(geo.size);
        doRenderGeometry(renderer, geo, gfx);
        doRenderObjects(renderer, objs, gfx);

        return doCreateLevel(renderer, templ, gfx);
    }

    ///return the list of known level templates
    public LevelTemplate[] templates() {
        return mTemplates;
    }

    ///returns identifier list of available gfx themes
    public char[][] gfxThemes() {
        return mGfxThemes;
    }

    //xxx: both find*()s generate new objects on the fly
    public LevelTheme findGfx(char[] name, bool canfail = false) {
        auto res = mGfxNodes.findNode(name);
        if (!res) {
            if (!canfail)
                throw new Exception("gfx-set '" ~ name ~ "' not found");
            return null;
        }
        return new LevelTheme(res);
    }
    public LevelTemplate findTemplate(char[] name, bool canfail = false) {
        LevelTemplate res;
        bool found = mTemplates.find(res, name);
        if (!found) {
            if (!canfail)
                throw new Exception("template '" ~ name ~ " not found");
            return null;
        }
        return res;
    }

    /// generate a random level based on a template
    public Level generateRandom(char[] templatename = "", char[] gfxSet = "")
    {
        mLog("template '%s'", templatename ? templatename : "[random]");
        mLog("gfx-set '%s'", gfxSet ? gfxSet : "[random]");

        LevelTheme gfx = findRandomGfx(gfxSet);
        LevelTemplate templ = findRandomTemplate(templatename);

        return renderLevel(templ, gfx);
    }

    private ConfigNode findRandomNode(ConfigNode node, char[] name = "") {
        ConfigNode res = node.findNode(name);

        if (res)
            return res;

        if (node.count > 0) {
            uint pick = rand.rand() % node.count;
            foreach(ConfigNode bres; node) {
                assert(bres !is null);
                if (pick == 0) {
                    return bres;
                }
                pick--;
            }
        }

        return null;
    }

    /// pick a template with name 'name'; if 'name' is not found, return a
    /// random one from the list
    public LevelTemplate findRandomTemplate(char[] name = "") {
        LevelTemplate res;
        bool found = mTemplates.findRandom(res, name);
        if (!found) {
            mLog("no level templates!");
            return null;
        }
        mLog("picked level template: '%s'", res.name);
        return res;
    }
    public LevelTheme findRandomGfx(char[] name = "") {
        ConfigNode node = findRandomNode(mGfxNodes, name);
        if (!node) {
            mLog("no level gfx-sets!");
            return null;
        }
        mLog("picked level gfx-set: '%s'", node.name);
        return findGfx(node.name, false);
    }

    /// like in Worms(tm): allow user images, but auto-place worms, boxes, etc.
    ///     placeObjects = place gfx objects into the level
    ///     gfx = gfx theme to use (still needed for i.e. the background)
    public Level generateFromImage(Surface image, bool placeObjects, char[] gfx)
    {
        if (placeObjects) {
            //TODO: add code
            assert(false);
        }
        auto rend = new LevelBitmap(image);
        //we still definitely need these for various stuff
        auto templ = findRandomTemplate();
        //xxx loads many graphics for nothing in this case
        auto theme = findRandomGfx(gfx);
        return doCreateLevel(rend, templ, theme);
    }

    const cLevelsPath = "/level";

    this() {
        mTemplates = loadTemplates();

        mGfxNodes = new ConfigNode();

        //find and load all gfx config nodes
        //(load them to see if it really exists)
        gFramework.fs.listdir(cLevelsPath, "*", true,
            (char[] path) {          //path is relative to "level" dir
                ConfigNode config;
                try {
                    config = gFramework.loadConfig(cLevelsPath ~ "/" ~ path
                        ~ "level");
                } catch (FilesystemException e) {
                    //seems it wasn't a valid gfx dir, do nothing, config==null
                    //i.e. the data directory contains .svn
                }
                if (config) {
                    //get the name of the config node from the path
                    //xxx store name in config file directly
                    assert(path[$-1] == '/');
                    char[] name = path[0..$-1];

                    config["gfxpath"] = cLevelsPath ~ "/" ~ path ~ "/";
                    config["name"] = name;
                    assert(!mGfxNodes.hasNode(name), "gfx name already exists");
                    mGfxThemes ~= name;
                    ConfigNode node = mGfxNodes.getSubNode(name);
                    //xxx: sorry, it just seemed to be too complicated to provide
                    //a function like ConfigNode.addSubNode(ConfigNode node);
                    //so, copy it into the new node
                    node.mixinNode(config);
                    //but this disgusting hack wasn't my idea
                    node.visitAllNodes(
                        (ConfigNode sub) {
                            sub.setFilePath(cLevelsPath ~ "/" ~ path);
                        }
                    );
                }
                return true;
            }
        );
    }
}

///load level generator templates; each node in the returned ConfigNode contains
///a single template which can be passed to the constructor of LevelTemplate
//xxx maybe rather return a LevelTemplate[]?
//    or only a char[][], and also a loader function
LevelTemplate[] loadTemplates() {
    LevelTemplate[] res;
    auto templNode = gFramework.loadConfig("levelgen")
        .getSubNode("levelgen_templates");
    foreach (ConfigNode sub; templNode) {
        res ~= new LevelTemplate(sub);
    }
    return res;
}
