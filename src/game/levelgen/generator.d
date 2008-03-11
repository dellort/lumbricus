module game.levelgen.generator;

import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.levelgen.genrandom;
import game.levelgen.placeobjects;
import game.animation;
import framework.restypes.bitmap;
import framework.framework;
import framework.filesystem;
import framework.resset;
import utils.configfile;
import utils.vector2;
import utils.output;
import utils.log;
import utils.array;
import utils.factory;
import std.stream;
import str = std.string;
import conv = std.conv;
import rand = std.random;
import utils.misc;

debug {
    import utils.perf;
}

private {
    Log mLog;
    Factory!(LevelGenerator, LevelGeneratorShared, ConfigNode)
        mGeneratorFactory;
}

static this() {
    mLog = registerLog("LevelGenerator");
    mGeneratorFactory = new typeof(mGeneratorFactory);
}

private const cLoadTemplateName = "load_defaults";

//keeps some stuff from the disk in memory during level generation, like the
//template and theme list - recreate to update this data
class LevelGeneratorShared {
    //all fields are read-only from outside
    package {
        ConfigNode generatorConfig; //this is levelgenerator.conf
        ConfigNode defaults;
        Color[Lexel] previewColors;
    }
    LevelTemplates templates;
    LevelThemes themes;

    this() {
        themes = new LevelThemes();
        templates = new LevelTemplates();
        themes.update();
        templates.update();

        generatorConfig = gFramework.loadConfig("levelgenerator");
        foreach (ConfigValue v; generatorConfig.getSubNode("preview_colors")) {
            Color c;
            c.parse(v.value);
            previewColors[parseMarker(v.name)] = c;
        }
        defaults = generatorConfig.getSubNode("defaults_templates");
        //so that templates can get defaults from other templates, yay
        //(probably not used yet)
        defaults.templatetifyNodes(cLoadTemplateName);
    }
}

///there's now a LevelGenerator instance for each level that is generated
///this class is abstract - there are different subclasses for these cases:
/// - random level generation out of templates
/// - loading saved/prerendered/pregenerated levels from files
/// - loading bitmaps as levels
///all have a render() and preview() method, so this stuff could be handled in a
///unified way.
///also, any of these can be stored to/loaded from files (but there's no support
///for load/saving in-game levels through this)
abstract class LevelGenerator {
    ///fast ugly preview - level must be prepared for render() (see subclasses)
    ///return null if not supported
    abstract Surface preview(Vector2i size);
    ///aspect ratio of the preview picture, returns size_x/size_y
    abstract float previewAspect();
    ///create and render the previously loaded/generated Level and return it
    abstract Level render();
}

///generate/render a level from a template
class GenerateFromTemplate : LevelGenerator {
    protected {
        LevelGeneratorShared mShared;
        LevelTheme mCurTheme;
        LevelTemplate mTemplate;
        bool mGenerated;
        Level mUnrendered;

        //bawww, I made it too complicated again
        static class Land {
            LevelLandscape land;
            char[] prerender_id;
            LandscapeTemplate geo_template;
            LandscapeGeometry geo_generated;
            bool placeObjects;
            LandscapeObjects objects;
        }

        //indexed by LevelLandscape.name
        Land[char[]] mLand;
    }

    //prerender_id -> landscape
    Landscape[char[]] prerendered;

    void selectTheme(LevelTheme theme) {
        mCurTheme = theme;
    }

    //only supports levels with one landscape, which are generated from
    //templates (feel free to extend it)
    //probably should call generate() before this
    override Surface preview(Vector2i size) {
        LandscapeGeometry geo;
        if (mLand.length == 1) {
            geo = mLand.values[0].geo_generated;
        }
        if (!geo)
            return null;
        return landscapeRenderPreview(geo, size, mShared.previewColors);
    }

    override float previewAspect() {
        LandscapeGeometry geo;
        if (mLand.length == 1) {
            geo = mLand.values[0].geo_generated;
        }
        if (!geo)
            return float.nan;
        return cast(float)geo.size.x/geo.size.y;
    }

    override Level render() {
        if (!mCurTheme) {
            mCurTheme = mShared.themes.findRandom();
            if (!mCurTheme)
                throw new Exception("no level themes found");
        }

        generate(false); //in the rare case it wasn't already called

        Level nlevel = mUnrendered.copy();
        nlevel.theme = mCurTheme.environmentTheme;

        auto saveto = new ConfigNode();
        nlevel.saved = saveto;

        saveto.setStringValue("type", "level_renderer");

        saveto.setStringValue("theme", mCurTheme.name);
        saveto.setStringValue("world_size", str.format("%s %s",
            nlevel.worldSize.x, nlevel.worldSize.y));
        saveto.setBoolValue("airstrike_allow", nlevel.airstrikeAllow);
        saveto.setIntValue("airstrike_y", nlevel.airstrikeY);
        saveto.setIntValue("water_bottom_y", nlevel.waterBottomY);
        saveto.setIntValue("water_top_y", nlevel.waterTopY);
        saveto.setIntValue("sky_top_y", nlevel.skyTopY);

        auto objsnode = saveto.getSubNode("objects");

        foreach (ref LevelItem o; nlevel.objects) {
            LevelItem new_item;

            auto onode = objsnode.getSubNode(o.name);

            //this is so stupid because you must check and copy for each
            //possible class type, need better way
            if (o.classinfo is LevelLandscape.classinfo) {
                //possibly render landscape
                auto land = castStrict!(LevelLandscape)(o);

                Land rland = mLand[land.name];
                Landscape rendered;
                char[] type;
                if (rland.geo_generated) {
                    auto renderer =
                        new LandscapeBitmap(rland.geo_generated.size,
                            mCurTheme.landscapeTheme);
                    auto gt = mCurTheme.genTheme();
                    landscapeRenderGeometry(renderer, rland.geo_generated, gt);
                    LandscapeObjects objs = rland.objects;
                    //never place objects in generated levels
                    onode.setBoolValue("allow_place_objects", false);
                    if (rland.placeObjects && !objs) {
                        objs = landscapePlaceObjects(renderer, gt);
                        //don't set rland.objects, because rland.objects is
                        //only for objects which were loaded, not generated
                    }
                    if (objs) {
                        landscapeRenderObjects(renderer, objs, gt);
                        objs.saveTo(onode.getSubNode("objects"));
                    }
                    rendered = renderer.createLandscape(true);
                    rland.geo_generated.saveTo(onode.getSubNode("geometry"));
                    type = "landscape_generated";
                } else if (rland.prerender_id != "") {
                    auto p = rland.prerender_id in prerendered;
                    if (!p) {
                        throw new Exception("level generator: landscape id '"
                            ~ rland.prerender_id ~ "' not found");
                    }
                    rendered = *p;
                    onode.setStringValue("prerender_id", rland.prerender_id);
                    type = "landscape_prerendered";
                } else {
                    assert(false, "nothing to render?");
                }
                assert(!!rendered, "no landscape was rendered");
                land.landscape = rendered;
                onode.setStringValue("type", type);
                onode.setStringValue("position", str.format("%s %s",
                    land.position.x, land.position.y));
            } else {
                assert(false);
            }

            assert(!!o);
        }

        return nlevel;
    }

    //several calls to this method could create different levels (depends from
    //if there is a generateable landscape)
    //there's some stupidity in this method: this doesn't place level objects
    //  yet, but in return you don't have to wait for object placement and also
    //  no level theme has to be selected/loaded yet (which is needed for the
    //  object definitions...)
    //justification for this silliness: WWP also seems to do it this way
    void generate(bool regenerate = true) {
        foreach (land; mLand) {
            if (land.geo_template && (regenerate || !land.geo_generated)) {
                land.geo_generated = land.geo_template.generate();
            }
        }
    }

    //create a Level again from its Level.saved member (all generated levels can
    //be saved and regenerated again)
    this(LevelGeneratorShared shared, ConfigNode saved) {
        mShared = shared;

        loadStuff(saved);
        if (!mCurTheme) {
            throw new Exception("no theme?");
        }
    }

    //generate a level from templ; if this is null, pick a random one
    this(LevelGeneratorShared shared, LevelTemplate templ) {
        mShared = shared;

        if (!templ) {
            templ = mShared.templates.findRandom();
        }
        if (!templ) {
            throw new Exception("no level templates found");
        }

        //probably quite useless, we only need the .data member, but this is
        //modified below
        mTemplate = templ;

        auto node = mTemplate.data.copy();

        //mixin a template, easy way to make level templates simpler
        char[] tval = node.getStringValue(cLoadTemplateName);
        if (tval.length > 0) {
            auto tnode = mShared.defaults.findNode(tval);
            if (!tnode)
                throw new LoadException(templ.name,
                    "default template not found: '" ~ tval ~ "'");
            node.mixinNode(tnode, false);
        }

        loadStuff(node);

        //mUnrendered.name = templ.name;
        //mUnrendered.description = templ.description;
    }

    private void loadStuff(ConfigNode node) {
        //actually load the full template or saved generated level

        mUnrendered = new Level();

        mUnrendered.worldSize = readVector(node["world_size"]);
        mUnrendered.airstrikeAllow = node.getBoolValue("airstrike_allow");
        mUnrendered.airstrikeY = node.getIntValue("airstrike_y");
        mUnrendered.waterBottomY = node.getIntValue("water_bottom_y");
        mUnrendered.waterTopY = node.getIntValue("water_top_y");
        //mUnrendered.skyBottomY = node.readIntValue("sky_bottom_y");
        mUnrendered.skyTopY = node.getIntValue("sky_top_y");

        //theme doesn't need to be there (like in templates)
        char[] th = node.getStringValue("theme");
        if (th != "") {
            mCurTheme = mShared.themes.find(th);
        }

        foreach (ConfigNode onode; node.getSubNode("objects")) {
            //probably add a factory lol
            auto t = onode.getStringValue("type");
            bool is_landtemplate = (t == "landscape_template");
            bool is_landrendered = (t == "landscape_prerendered");
            bool is_landgen = (t == "landscape_generated");
            if (is_landtemplate || is_landrendered || is_landgen) {
                auto land = new LevelLandscape();
                mUnrendered.objects ~= land;
                land.owner = mUnrendered;
                land.name = onode.name;
                land.position = readVector(onode["position"]);
                Land l2 = new Land();
                mLand[land.name] = l2;
                l2.placeObjects = onode.getBoolValue("allow_place_objects",
                    true);
                if (auto objs = onode.findNode("objects")) {
                    l2.objects = new LandscapeObjects();
                    l2.objects.loadFrom(objs);
                }
                if (is_landtemplate) {
                    l2.geo_template = new LandscapeTemplate(onode);
                } else if (is_landgen) {
                    l2.geo_generated = new LandscapeGeometry();
                    l2.geo_generated.loadFrom(onode.getSubNode("geometry"));
                } else if (is_landrendered) {
                    l2.prerender_id = onode.getStringValue("prerender_id");
                } else {
                    assert(false);
                }
            } else {
                throw new Exception("unknown object type '"~t~"' in level"
                    " template");
            }
        }
    }

    static this() {
        mGeneratorFactory.register!(typeof(this))("level_renderer");
    }
}

//implementation of this is really silly: this prepares a custom LevelTemplate,
//which is then passed to a GenerateFromTemplate
class GenerateFromBitmap : LevelGenerator {
    private {
        LevelGeneratorShared mShared;
        GenerateFromTemplate mGenerate;
        bool mIsCave, mPlaceObjects;
        LevelTheme mTheme;
        Surface mBitmap;
        char[] mFilename;
        Landscape mLandscape;
    }

    //make sure mGenerate is not null
    //mGenerate still can be null if the stuff set so far isn't enough
    //(each time the settings are changed, the outdated mGenerate is destroyed)
    private void update() {
        if (mGenerate)
            return;
        updateTheme();
        updateLandscape();
        if (!mLandscape)
            return;
        auto gc = mShared.generatorConfig;
        auto node = gc.getSubNode("import_from_bitmap").clone();
        auto cave_node = "import_" ~ (mIsCave ? "cave" : "nocave");
        node.mixinNode(gc.getSubNode(cave_node), false, true);
        if (mPlaceObjects) {
            node.mixinNode(gc.getSubNode("import_placeobjects"), true, true);
        }
        auto templ = new LevelTemplate(node, "imported");
        mGenerate = new GenerateFromTemplate(mShared, templ);
        mGenerate.prerendered["import0"] = mLandscape;
        mGenerate.selectTheme(mTheme);
    }

    //make sure mTheme is not null (randomly select one if it is)
    private void updateTheme() {
        if (!mTheme)
            mTheme = mShared.themes.findRandom();
    }

    //if mLandscape is null, recreate it from mBitmap
    private void updateLandscape() {
        if (mLandscape)
            return;
        if (!mBitmap)
            return;
        updateTheme();
        //hurrrr isn't it fun
        auto bmp = new LandscapeBitmap(mBitmap, mTheme.landscapeTheme());
        mLandscape = bmp.createLandscape(true);
    }

    void isCave(bool set) {
        mIsCave = set;
        mGenerate = null;
    }

    void selectTheme(LevelTheme theme) {
        mTheme = theme;
        mGenerate = null;
        mLandscape = null; //also uses a small part of the theme
    }

    //set the level bitmap - the transparency setting are taken from the Surface
    //you can modify the colorkey of s to make a specific color transparent
    //filename is an optional path to the file, so it can be saved and reloaded
    //(the saved config file will contain the filename)
    //XXX: probably take only the filename directly, then this class also could
    //handle things like fixing up the transparency of the bitmap etc.
    void bitmap(Surface s, char[] filename = "") {
        mBitmap = s;
        mFilename = filename.dup;
        mGenerate = null;
        mLandscape = null;
    }

    //if objects from the theme should be placed on the bitmap (randomly)
    void placeObjects(bool set) {
        mPlaceObjects = set;
        mGenerate = null;
        mLandscape = null;
    }

    Surface preview(Vector2i size) {
        update();
        return mGenerate ? mGenerate.preview(size) : null;
    }
    float previewAspect() {
        update();
        return mGenerate ? mGenerate.previewAspect() : float.nan;
    }
    Level render() {
        update();
        Level res = mGenerate ? mGenerate.render() : null;
        if (res) {
            if (mFilename == "") {
                res.saved = null; //hopeless
            } else {
                //modify the .saved thingy to recreate the level in our way
                //NOTE: actually, we only need to recreate the Landscape, and we
                //could reuse the created and saved LevelTemplate, and only the
                //landscape thing would need to be reloaded etc.
                auto s = new ConfigNode();
                s.setStringValue("type", "import_bitmap");
                s.setStringValue("filename", mFilename);
                s.setBoolValue("is_cave", mIsCave);
                s.setStringValue("theme", mTheme.name);
                s.setBoolValue("place_objects", mPlaceObjects);
                res.saved = s;
            }
        }
        return res;
    }

    this(LevelGeneratorShared shared) {
        assert(!!shared);
        mShared = shared;
    }

    //load saved stuff
    this(LevelGeneratorShared shared, ConfigNode from) {
        mShared = shared;

        mIsCave = from.getBoolValue("is_cave");
        mPlaceObjects = from.getBoolValue("place_objects");
        mFilename = from.getStringValue("filename");
        char[] theme = from.getStringValue("theme");

        mTheme = mShared.themes.find(theme);

        mBitmap = gFramework.loadImage(mFilename);
    }

    static this() {
        mGeneratorFactory.register!(typeof(this))("import_bitmap");
    }
}

///a LevelGenerator which can render levels which were saved to config files
//actually a read-only proxy for loading/rendering saved levels
//why a proxy? I don't know, it feels more robust lol
//(you can't call methods which would modify the saved level again, like
// generate())
class GenerateFromSaved : LevelGenerator {
    private {
        LevelGenerator mReal;
    }

    override Surface preview(Vector2i size) {
        return mReal.preview(size);
    }

    override Level render() {
        return mReal.render();
    }

    override float previewAspect() {
        return mReal.previewAspect();
    }

    this(LevelGeneratorShared shared, ConfigNode from) {
        auto t = from.getStringValue("type");
        mReal = mGeneratorFactory.instantiate(t, shared, from);
    }
}

///load saved level, use GenerateFromSaved directly to have more control
Level loadSavedLevel(LevelGeneratorShared shared, ConfigNode from) {
    auto gen = new GenerateFromSaved(shared, from);
    return gen.render();
}

//-------------

/// template to be used for GenerateFromTemplate
class LevelTemplate {
    //hurrrr isn't it lame? this also sucks a lot, must do better
    char[] name, description;
    ConfigNode data;

    this(char[] path, char[] a_name) {
        auto f = gFramework.loadConfig(path, true);
        name = a_name;
        data = f;
        description = data["description"];
        if (!name.length || !description.length) {
            throw new LoadException(path, "not a level template?");
        }
    }

    this(ConfigNode f, char[] a_name) {
        name = a_name;
        data = f;
        description = data["description"];
    }
}

/// geometry template, all information from an item in levelgen/*.conf
public class LandscapeTemplate {
    private LandscapeGeometry mGeometry;
    private GeneratorConfig mConfig;

    /// landscape subnode as in levelgen/*.conf
    this(ConfigNode from) {
        mGeometry = new LandscapeGeometry();
        mGeometry.loadFrom(from);
        mConfig.loadFrom(from);
    }

    LandscapeGeometry geometry() {
        return mGeometry;
    }

    Vector2i size() {
        return mGeometry.size;
    }

    /// generate subdivided geometry from this level
    /// (final subdivision for smooth level curves is done in renderer.d)
    public LandscapeGeometry generate() {
        auto gen = new GenRandomLandscape();
        gen.readFrom(mGeometry);
        gen.setConfig(mConfig);

        mLog("generating landscape...");

        auto res = gen.generate();

        mLog("done.");

        return res;
    }
}

//information needed for full landscape generation (rendering from geometry,
//placing additional static bitmap objects)
//corresponds to a level.conf "landscapegen" node
class LandscapeGenTheme {
    PlaceableObject[char[]] objects;
    PlaceableObject[3] bridge;
    Surface[Lexel] markerTex;
    Border[] borders;

    struct Border {
        bool[2] action;
        Lexel[2] markers;
        Surface[2] textures;
    }

    public PlaceableObject findObject(char[] name) {
        return objects[name];
    }

    this(ConfigNode node) {
        ResourceSet resources;

        Surface loadBorderTex(ConfigNode texNode) {
            Surface tex;
            char[] tex_name = texNode.getStringValue("texture");
            if (tex_name.length > 0) {
                tex = resources.get!(Surface)(texNode["texture"]);
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

        Surface readMarkerTex(ConfigNode texNode, char[] markerId) {
            Surface res;
            char[] texFile = texNode.getStringValue(markerId);
            if (texFile == "-" || texFile == "") {
            } else {
                res = resources.get!(Surface)(texNode[markerId]);
            }
            //xxx I believe it allowed to return null sometimes in older
            //versions? (but in the last version it wasn't used at all)
            if (!res)
                throw new LoadException("couldn't load texture for marker",
                    markerId);
            return res;
        }

        resources = gFramework.resources.loadResSet(node);

        //the least important part is the longest
        ConfigNode cborders = node.getSubNode("borders");
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
            auto bmp = resources.get!(Surface)(bitmap);
            //use ressource name as id
            auto po = new PlaceableObject(bitmap, bmp, try_place);
            objects[po.id] = po;
            return po;
        }

        ConfigNode bridgeNode = node.getSubNode("bridge");
        bridge[0] = createObject(bridgeNode["segment"], false);
        bridge[1] = createObject(bridgeNode["left"], false);
        bridge[2] = createObject(bridgeNode["right"], false);

        ConfigNode objectsNode = node.getSubNode("objects");
        foreach (char[] id, ConfigNode onode; objectsNode) {
            createObject(onode["image"], true);
        }

        //hmpf, read all known markers
        auto texnode = node.getSubNode("marker_textures");
        markerTex[Lexel.SolidSoft] = readMarkerTex(texnode, "LAND");
        markerTex[Lexel.SolidHard] = readMarkerTex(texnode, "SOLID_LAND");
    }
}

public class LevelTheme {
    char[] name;

    private {
        //might all be null, loaded on demand from the confignodes
        LandscapeTheme mLandscapeTheme;
        EnvironmentTheme mEnvironmentTheme;
        LandscapeGenTheme mGenTheme;

        ConfigNode land, env, gen;
    }

    //loaded if a landscape is used (= always)
    LandscapeTheme landscapeTheme() {
        if (!mLandscapeTheme) {
            mLandscapeTheme = new LandscapeTheme(land);
        }
        return mLandscapeTheme;
    }

    //always loaded, but delay loading is to support theme listing without
    //actually loading any graphics
    EnvironmentTheme environmentTheme() {
        if (!mEnvironmentTheme) {
            mEnvironmentTheme = new EnvironmentTheme(env);
        }
        return mEnvironmentTheme;
    }

    //only loaded if a landscape is generated
    LandscapeGenTheme genTheme() {
        if (!mGenTheme) {
            mGenTheme = new LandscapeGenTheme(gen);
        }
        return mGenTheme;
    }

    this(char[] path, char[] a_name) {
        //use this function because we want to load resources from it later
        auto conf = gFramework.resources.loadConfigForRes(path);

        land = conf.findNode("landscape");
        gen = conf.findNode("landscapegen");
        env = conf.findNode("environment");

        name = a_name;

        if (!land || !gen || !env || !name.length) {
            throw new LoadException(path, "not a level theme or invalid/buggy one");
        }
    }
}

//common code for LevelThemes/LevelTemplates ("list" managment)
//T is expected to have a property/member named "name"
template BlaList(T : Object) {
    private {
        T[] mItems;
    }

    T find(char[] name, bool canfail = false) {
        foreach (T t; mItems) {
            if (t.name == name) {
                return t;
            }
        }
        if (!canfail)
            throw new Exception("item '" ~ name ~ " not found");
        return null;
    }

    T findRandom(char[] name = "") {
        T res = find(name, true);

        if (res)
            return res;

        //pick randomly
        if (mItems.length > 0) {
            uint pick = rand.rand() % mItems.length;
            foreach(bres; mItems) {
                assert(bres !is null);
                if (pick == 0) {
                    return bres;
                }
                pick--;
            }
        }

        //uh...
        return null;
    }

    T[] all() {
        return mItems.dup;
    }

    char[][] names() {
        return arrayMap(mItems, (T t) {return t.name;});
    }
}

const cLevelsPath = "/level";
const cTemplatesPath = "/levelgen";

//list of found level themes, created from a directory listing on instantiation
//must call update() to read the stuff from disk
class LevelThemes {
    mixin BlaList!(LevelTheme);

    void update() {
        mItems = null;
        gFramework.fs.listdir(cLevelsPath, "*", true,
            (char[] path) {          //path is relative to "level" dir
                LevelTheme theme;
                auto filename = cLevelsPath ~ "/" ~ path ~ "level.conf";

                //xxx how to correctly cut that '/' off? the name is important
                //  to know and must be OS independent
                auto name = path;
                assert(name.length > 0 && name[$-1] == '/');
                name = name[0..$-1];

                Exception err;
                try {
                    theme = new LevelTheme(filename, name);
                } catch (FilesystemException e) {
                    //seems it wasn't a valid gfx dir, do nothing, config==null
                    //i.e. the data directory contains .svn
                    err = e;
                } catch (LoadException e) {
                    //or some stupid other exception, also do nothing
                    err = e;
                }
                if (theme) {
                    mItems ~= theme;
                } else {
                    mLog("could not load '%s' as LevelTheme: %s", filename, err);
                }
                return true;
            }
        );
    }
}

class LevelTemplates {
    mixin BlaList!(LevelTemplate);

    void update() {
        mItems = null;
        gFramework.fs.listdir(cTemplatesPath, "*.conf", false,
            (char[] path) {
                auto npath = cTemplatesPath ~ "/" ~ path; //uh, relative path
                LevelTemplate templ;
                //xxx error handling is duplicated code from above
                Exception err;
                try {
                    templ = new LevelTemplate(npath, path);
                } catch (FilesystemException e) {
                    err = e;
                } catch (LoadException e) {
                    err = e;
                }
                if (templ) {
                    mItems ~= templ;
                } else {
                    mLog("could not load '%s' as LevelTemplate: %s", path, err);
                }
                return true;
            }
        );
    }
}

//---- and finally, the actual render functions

void landscapeRenderGeometry(LandscapeBitmap renderer,
    LandscapeGeometry geometry, LandscapeGenTheme gfx)
{
    assert(renderer && geometry && gfx);

    debug {
        auto counter = new PerfTimer();
        counter.start();
    }

    //geometry
    foreach (LandscapeGeometry.Polygon p; geometry.polygons) {
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
        mLog("geometry: %s", counter.time());
        counter.reset();
        counter.start();
    }

    //borders, must come after geometry
    foreach (b; gfx.borders) {
        renderer.drawBorder(b.markers[0], b.markers[1], b.action[0],
            b.action[1], b.textures[0], b.textures[1]);
    }

    debug {
        counter.stop();
        mLog("borders: %s", counter.time());
    }
}

/// render a fast, ugly preview; just to see the geometry
/// returns a surface, which shall be freed by the user himself
Surface landscapeRenderPreview(LandscapeGeometry geo, Vector2i size,
    Color[Lexel] colors)
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
    foreach (Lexel lex, Color c; colors) {
        markers[lex] = createPixelSurface(c);
    }

    //just the fallback for markers[]
    auto nocolor = createPixelSurface(Color(0, 0, 0));

    Vector2f scale = toVector2f(size) / toVector2f(geo.size);
    auto renderer = new LandscapeBitmap(size, null);

    //draw background (not drawn when it's not a cave!)
    //(actually, a FillRect would be enough, but...)
    renderer.addPolygon([Vector2i(), size.X, size, size.Y], true,
        Vector2i(), markers[Lexel.Null], Lexel.Null, false, null, 0, 0);

    foreach (LandscapeGeometry.Polygon p; geo.polygons) {
        //scale down the points first
        auto npts = p.points.dup;
        foreach (inout Vector2i point; npts) {
            point = toVector2i(toVector2f(point).mulEntries(scale));
        }
        auto color = (p.marker in markers) ? markers[p.marker] : nocolor;
        renderer.addPolygon(npts, p.visible, Vector2i(0, 0),
            color, p.marker, p.changeable, p.nochange, 1, 0.25f);
    }

    foreach (bitmap; markers) {
        bitmap.free();
    }

    return renderer.releaseImage();
}

//try to place the objects (listed in gfx) into the level bitmap in renderer
//both draws the objects into renderer and returns a list of placed objects
//(this list is used to implement level saving/loading, else it's useless)
//NOTE: this is how Worms(TM) obviously works, i.e. there you can paint
//      your own level and Worms(TM) still can place objects into it
LandscapeObjects landscapePlaceObjects(LandscapeBitmap renderer,
    LandscapeGenTheme gfx)
{
    debug {
        auto counter = new PerfTimer();
        counter.start();
    }

    auto placer = new PlaceObjects(renderer);
    foreach (PlaceableObject o; gfx.objects) {
        if (o.tryPlace)
            placer.placeObjects(10, 10, o);
    }
    placer.placeBridges(10, 10, gfx.bridge);

    debug {
        counter.stop();
        mLog("placed objects in %s", counter.time());
    }

    return placer.objects;
}

//render the same objects as landscapePlaceObjects() did, using its return value
void landscapeRenderObjects(LandscapeBitmap renderer, LandscapeObjects objs,
    LandscapeGenTheme gfx)
{
    debug {
        auto counter = new PerfTimer();
        counter.start();
    }

    foreach (LandscapeObjects.PlaceItem item; objs.items) {
        PlaceableObject obj = gfx.findObject(item.id);
        renderPlacedObject(renderer, obj.bitmap, item.params);
    }

    debug {
        counter.stop();
        mLog("rendered objects in %s", counter.time());
    }
}
