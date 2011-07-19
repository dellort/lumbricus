module game.levelgen.generator;

import game.levelgen.landscape;
import game.levelgen.level;
import game.levelgen.renderer;
import game.levelgen.genrandom;
import game.levelgen.placeobjects;
import framework.config;
import framework.surface;
import framework.filesystem;
import framework.imgread;
import common.resources;
import common.resset;
import utils.color;
import utils.configfile;
import utils.vector2;
import utils.log;
import utils.array;
import utils.factory;
import utils.random : rngShared;
import utils.misc;
import utils.rect2;

debug {
    import utils.perf;
}

private {
    Log mLog;
    Factory!(LevelGenerator, LevelGeneratorShared, ConfigNode)
        mGeneratorFactory;
}

static this() {
    mLog = registerLog("levelgen");
    mGeneratorFactory = new typeof(mGeneratorFactory);
}

private enum cLoadTemplateName = "load_defaults";

Surface createPixelSurface(Color c) {
    auto s = new Surface(Vector2i(1));
    s.fill(s.rect, c);
    return s;
}

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

        generatorConfig = loadConfig("levelgenerator.conf");
        foreach (ConfigNode v; generatorConfig.getSubNode("preview_colors")) {
            previewColors[parseMarker(v.name)] = Color.fromString(v.value);
        }
        defaults = generatorConfig.getSubNode("defaults_templates");
        //so that templates can get defaults from other templates, yay
        //(probably not used yet)
        defaults.templatetifyNodes(cLoadTemplateName);
    }
}

struct LevelProperties {
    bool isCave;
    bool placeObjects;
    bool[4] impenetrable;
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
    ///just render the landscape mask, not the image
    abstract LandscapeBitmap renderData();
    ///create and render the previously loaded/generated Level and return it
    /// render_bitmaps: if false, don't render bitmaps, which are e.g. saved in
    ///                 a savegame anyway
    abstract Level render(bool render_bitmaps = true);

    ///helper function for the gui, to determine what will be generated
    ///  (and set button states accordingly)
    abstract LevelProperties properties();
}

///generate/render a level from a template
//actually, this handles a lot more
//to say the truth, this is a rewrite-candidate
class GenerateFromTemplate : LevelGenerator {
    protected {
        LevelGeneratorShared mShared;
        LevelTheme mCurTheme;
        LevelTemplate mTemplate;
        bool mGenerated;
        Level mUnrendered;

        //bawww, I made it too complicated again
        static class Land {
            LevelLandscape land; //last generated one
            string prerender_id;
            LandscapeTemplate geo_template;
            LandscapeGeometry geo_generated;
            LandscapeBitmap geo_pregenerated;
            bool placeObjects;
            LandscapeObjects objects, gen_objects;
        }

        //indexed by LevelLandscape.name
        Land[string] mLand;
    }

    //prerender_id -> landscape
    LandscapeBitmap[string] prerendered;
    LandscapeTheme[string] prerendered_theme; //parallel array

    void selectTheme(LevelTheme theme) {
        mCurTheme = theme;
    }

    //selected theme or null; the autoselected theme after render()
    LevelTheme theme() {
        return mCurTheme;
    }

    //only supports levels with one landscape, which are generated from
    //templates (feel free to extend it)
    //probably should call generate() before this
    override Surface preview(Vector2i size) {
        LandscapeGeometry geo;
        LandscapeBitmap lex;
        if (mLand.length == 1) {
            geo = mLand.values[0].geo_generated;
            lex = mLand.values[0].geo_pregenerated;
            string pre_id = mLand.values[0].prerender_id;
            if (!lex && pre_id.length > 0 && pre_id in prerendered) {
                lex = prerendered[pre_id];
            }
        }
        if (!geo && !lex)
            return null;
        if (lex)
            return lex.renderPreview(size, mShared.previewColors);
        else
            return landscapeRenderPreview(geo, size, mShared.previewColors);
    }

    override float previewAspect() {
        LandscapeGeometry geo;
        LandscapeBitmap lex;
        if (mLand.length == 1) {
            geo = mLand.values[0].geo_generated;
            lex = mLand.values[0].geo_pregenerated;
            string pre_id = mLand.values[0].prerender_id;
            if (!lex && pre_id.length > 0 && pre_id in prerendered) {
                lex = prerendered[pre_id];
            }
        }
        if (lex)
            return (cast(float)lex.size.x)/lex.size.y;
        if (geo)
            return (cast(float)geo.size.x)/geo.size.y;
        return float.nan;
    }

    override LandscapeBitmap renderData() {
        LandscapeGeometry geo;
        if (mLand.length == 1) {
            if (mLand.values[0].geo_pregenerated)
                return mLand.values[0].geo_pregenerated;
            string pre_id = mLand.values[0].prerender_id;
            if (pre_id.length > 0 && pre_id in prerendered) {
                return prerendered[pre_id];
            }
            geo = mLand.values[0].geo_generated;
        }
        if (!geo)
            return null;
        return landscapeRenderData(geo, geo.size);
    }

    override Level render(bool render_bitmaps = true) {
        if (!mCurTheme) {
            mCurTheme = mShared.themes.findRandom();
            if (!mCurTheme)
                throw new CustomException("no level themes found");
        }

        generate(false); //in the rare case it wasn't already called

        Level nlevel = mUnrendered.copy();
        nlevel.theme = mCurTheme.environmentTheme;
        nlevel.landBounds = Rect2i.Abnormal();

        auto saveto = new ConfigNode();
        //the following code generates a level and. at the same time, saves the
        //result to a confignode - the result can be loaded later again, which
        //means the following code has to be exact
        //(the code has lots of potential to break network games / savegames)
        nlevel.saved = saveto;

        saveto.setStringValue("type", "level_renderer");

        saveto.setStringValue("theme", mCurTheme.name);
        saveto.setStringValue("world_size", myformat("%s %s",
            nlevel.worldSize.x, nlevel.worldSize.y));
        saveto.setBoolValue("airstrike_allow", nlevel.airstrikeAllow);
        saveto.setIntValue("airstrike_y", nlevel.airstrikeY);
        saveto.setIntValue("water_bottom_y", nlevel.waterBottomY);
        saveto.setIntValue("water_top_y", nlevel.waterTopY);
        saveto.setIntValue("sky_top_y", nlevel.skyTopY);

        auto saveto_objsnode = saveto.getSubNode("objects");

        foreach (ref LevelItem o; nlevel.objects) {
            LevelItem new_item;

            auto saveto_obj = saveto_objsnode.getSubNode(o.name);

            //this is so stupid because you must check and copy for each
            //possible class type, need better way
            if (o.classinfo is LevelLandscape.classinfo) {
                //possibly render landscape
                auto land = castStrict!(LevelLandscape)(o);

                Land rland = mLand[land.name];
                LandscapeBitmap rendered;
                LandscapeTheme rendered_theme;
                string type;
                if (rland.geo_generated || rland.geo_pregenerated) {
                    if (rland.geo_generated)
                        land.size = rland.geo_generated.size;
                    else
                        land.size = rland.geo_pregenerated.size;
                    auto gt = mCurTheme.genTheme();
                    LandscapeBitmap renderer;
                    if (render_bitmaps) {
                        if (rland.geo_generated) {
                            renderer = landscapeRenderGeometry(
                                rland.geo_generated, gt);
                        } else {
                            renderer = landscapeRenderPregenerated(
                                rland.geo_pregenerated, gt);
                        }
                    }
                    LandscapeObjects objs = rland.objects;
                    //never place objects in generated levels
                    saveto_obj.setBoolValue("allow_place_objects", false);
                    if (rland.placeObjects && !objs) {
                        //NOTE: of course this needs a rendered level, no matter
                        //      what, and without we can't place the objects
                        assert(render_bitmaps);
                        objs = landscapePlaceObjects(renderer, gt);
                        //don't set rland.objects, because rland.objects is
                        //only for objects which were loaded, not generated
                    }
                    rland.gen_objects = objs;
                    if (objs) {
                        if (render_bitmaps)
                            landscapeRenderObjects(renderer, objs, gt);
                        rland.gen_objects.saveTo(
                            saveto_obj.getSubNode("objects"));
                    }
                    rendered = renderer; //what
                    rendered_theme = mCurTheme.landscapeTheme;
                    if (rland.geo_generated) {
                        rland.geo_generated.saveTo(
                            saveto_obj.getSubNode("geometry"));
                        type = "landscape_generated";
                    } else {
                        saveLevelLexels(rland.geo_pregenerated,
                            saveto_obj.getSubNode("lexeldata"));
                        type = "landscape_pregenerated";
                    }
                } else if (rland.prerender_id != "") {
                    auto p = rland.prerender_id in prerendered;
                    if (!p) {
                        throw new CustomException("level generator: landscape id '"
                            ~ rland.prerender_id ~ "' not found");
                    }
                    rendered = *p;
                    land.size = rendered.size;
                    rendered_theme = prerendered_theme[rland.prerender_id];
                    saveto_obj.setStringValue("prerender_id",
                        rland.prerender_id);
                    type = "landscape_prerendered";
                } else {
                    assert(false, "nothing to render?");
                }
                if (render_bitmaps)
                    assert(!!rendered, "no landscape was rendered");
                assert(!!rendered_theme, "no landscape theme selected");
                land.landscape = rendered;
                land.landscape_theme = rendered_theme;
                rland.land = land;
                saveto_obj.setStringValue("type", type);
                saveto_obj.setStringValue("position", myformat("%s %s",
                    land.position.x, land.position.y));
                //onode.setStringValue("size", myformat("%s %s",
                  //  land.size.x, land.size.y));
                foreach (int i, val; land.impenetrable) {
                    saveto_obj.setValue(LevelLandscape.cWallNames[i], val);
                }
                nlevel.landBounds.extend(Rect2i.Span(land.position, land.size));
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

    //used by the level editor to display the generated geometry
    //this sucks of course because there should be a "proper" public data
    //structure which can contain templates/generated/rendered levels
    struct Generated {
        LevelLandscape ls;
        LandscapeGeometry geo;
        LandscapeObjects objs;
    }
    Generated[] listGenerated() {
        Generated[] res;
        foreach (land; mLand) {
            Generated d;
            d.ls = land.land;
            d.geo = land.geo_generated;
            if (!d.geo && land.geo_template)
                d.geo = land.geo_template.geometry();
            d.objs = land.gen_objects;
            res ~= d;
        }
        return res;
    }

    //create a Level again from its Level.saved member (all generated levels can
    //be saved and regenerated again)
    this(LevelGeneratorShared shared, ConfigNode saved) {
        mShared = shared;

        loadStuff(saved);
        if (!mCurTheme) {
            throw new CustomException("no theme?");
        }
    }

    //generate a level from templ; if this is null, pick a random one
    this(LevelGeneratorShared shared, LevelTemplate templ,
        LandscapeBitmap data = null)
    {
        mShared = shared;

        if (!templ) {
            templ = mShared.templates.findRandom();
        }
        if (!templ) {
            throw new CustomException("no level templates found");
        }

        //probably quite useless, we only need the .data member, but this is
        //modified below
        mTemplate = templ;

        ConfigNode node = mTemplate.data.copy();

        //mixin a template, easy way to make level templates simpler
        string tval = node.getStringValue(cLoadTemplateName);
        if (tval.length > 0) {
            auto tnode = mShared.defaults.findNode(tval);
            if (!tnode)
                throw new LoadException(templ.name,
                    "default template not found: '" ~ tval ~ "'");
            node.mixinNode(tnode, false);
        }

        loadStuff(node, data);

        //mUnrendered.name = templ.name;
        //mUnrendered.description = templ.description;
    }

    private void loadStuff(ConfigNode node, LandscapeBitmap data = null) {
        //actually load the full template or saved generated level

        mUnrendered = new Level();

        mUnrendered.worldSize = node.getValue!(Vector2i)("world_size");
        mUnrendered.airstrikeAllow = node.getBoolValue("airstrike_allow");
        mUnrendered.airstrikeY = node.getIntValue("airstrike_y");
        mUnrendered.waterBottomY = node.getIntValue("water_bottom_y");
        mUnrendered.waterTopY = node.getIntValue("water_top_y");
        //mUnrendered.skyBottomY = node.readIntValue("sky_bottom_y");
        mUnrendered.skyTopY = node.getIntValue("sky_top_y");

        //theme doesn't need to be there (like in templates)
        string th = node.getStringValue("theme");
        if (th != "") {
            mCurTheme = mShared.themes.find(th);
        }

        foreach (ConfigNode onode; node.getSubNode("objects")) {
            //probably add a factory lol
            auto t = onode.getStringValue("type");
            bool is_landtemplate = (t == "landscape_template");
            bool is_landrendered = (t == "landscape_prerendered");
            bool is_landgen = (t == "landscape_generated");
            bool is_landpregen = (t == "landscape_pregenerated");
            if (is_landtemplate || is_landrendered || is_landgen
                || is_landpregen)
            {
                auto land = new LevelLandscape();
                mUnrendered.objects ~= land;
                land.owner = mUnrendered;
                land.name = onode.name;
                land.position = onode.getValue!(Vector2i)("position");
                foreach (int i, ref val; land.impenetrable) {
                    val = onode.getValue(LevelLandscape.cWallNames[i], false);
                }
                //no airstrikes if we have a top wall
                if (land.impenetrable[0])
                    mUnrendered.airstrikeAllow = false;
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
                } else if (is_landpregen) {
                    if (data) {
                        l2.geo_pregenerated = data;
                    } else {
                        l2.geo_pregenerated = loadLevelLexels(
                            onode.getSubNode("lexeldata"));
                    }
                } else {
                    assert(false);
                }
            } else {
                throwError("unknown object type '%s' in level template at %s",
                    t, onode.locationString);
            }
        }
    }

    override LevelProperties properties() {
        LevelProperties ret;
        ret.isCave = !mUnrendered.airstrikeAllow;
        assert("land0" in mLand);
        ret.placeObjects = mLand["land0"].placeObjects;
        if (mUnrendered.objects.length) {
            auto land = cast(LevelLandscape)mUnrendered.objects[0];
            if (land) {
                ret.impenetrable[] = land.impenetrable;
            }
        }
        return ret;
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
        string mFilename;
        LandscapeBitmap mLandscape;
        LandscapeTheme mLandscapeTheme;
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
        auto node = gc.getSubNode("import_from_bitmap").copy();
        auto cave_node = "import_" ~ (mIsCave ? "cave" : "nocave");
        node.mixinNode(gc.getSubNode(cave_node), false, true);
        if (mPlaceObjects) {
            node.mixinNode(gc.getSubNode("import_placeobjects"), true, true);
        }
        auto templ = new LevelTemplate(node, "imported");
        mGenerate = new GenerateFromTemplate(mShared, templ);
        mGenerate.prerendered["import0"] = mLandscape;
        mGenerate.prerendered_theme["import0"] = mLandscapeTheme;
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
        mLandscape = new LandscapeBitmap(mBitmap);
        mLandscapeTheme = mTheme.landscapeTheme();
        assert (!!mLandscapeTheme);
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
    void bitmap(Surface s, string filename = "") {
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
    override LandscapeBitmap renderData() {
        return mGenerate ? mGenerate.renderData() : null;
    }
    Level render(bool render_stuff = true) {
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
        string theme = from.getStringValue("theme");

        mTheme = mShared.themes.find(theme);

        mBitmap = loadImage(mFilename);
    }

    override LevelProperties properties() {
        LevelProperties ret;
        //xxx does mIsCave even work? I thought is_cave had been removed
        ret.isCave = mIsCave;
        ret.placeObjects = mPlaceObjects;
        return ret;
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

    override LandscapeBitmap renderData() {
        return mReal.renderData();
    }

    override Level render(bool render_bitmaps = true) {
        return mReal.render(render_bitmaps);
    }

    override float previewAspect() {
        return mReal.previewAspect();
    }

    override LevelProperties properties() {
        return mReal.properties();
    }

    this(LevelGeneratorShared shared, ConfigNode from) {
        auto t = from.getStringValue("type");
        mReal = mGeneratorFactory.instantiate(t, shared, from);
    }
}

///load saved level, use GenerateFromSaved directly to have more control
Level loadSavedLevel(LevelGeneratorShared shared, ConfigNode from,
    bool renderBitmaps = true)
{
    auto gen = new GenerateFromSaved(shared, from);
    return gen.render(renderBitmaps);
}

//-------------

/// template to be used for GenerateFromTemplate
class LevelTemplate {
    //hurrrr isn't it lame? this also sucks a lot, must do better
    string name, description;
    ConfigNode data;

    this(string path, string a_name) {
        auto f = loadConfig(path);
        name = a_name;
        data = f;
        description = data["description"];
        if (!name.length || !description.length) {
            throw new LoadException(path, "not a level template?");
        }
    }

    this(ConfigNode f, string a_name) {
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
        mConfig = from.getCurValue!(GeneratorConfig)();
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

        mLog.minor("generating landscape...");

        auto res = gen.generate();

        mLog.minor("done.");

        return res;
    }
}

//information needed for full landscape generation (rendering from geometry,
//placing additional static bitmap objects)
//corresponds to a level.conf "landscapegen" node
class LandscapeGenTheme {
    PlaceableObject[string] objects;
    PlaceableObject[3] bridge;
    Surface[Lexel] markerTex;
    Border[] borders;

    struct Border {
        bool[2] action;
        Lexel[2] markers;
        Surface[2] textures;
    }

    public PlaceableObject findObject(string name) {
        return objects[name];
    }

    this(ConfigNode node) {
        ResourceSet resources;

        Surface loadBorderTex(ConfigNode texNode) {
            Surface tex;
            string tex_name = texNode.getStringValue("texture");
            if (tex_name.length > 0) {
                tex = resources.get!(Surface)(texNode["texture"]);
            } else {
                //sucky color-border hack
                int height = texNode.getIntValue("height", 1);
                tex = new Surface(Vector2i(1, height));
                auto col = texNode.getValue("color", Color(0,0,0));
                tex.fill(Rect2i(tex.size), col);
            }
            return tex;
        }

        Surface readMarkerTex(ConfigNode texNode, string markerId) {
            Surface res;
            string texFile = texNode.getStringValue(markerId);
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

        resources = gResources.loadResSet(node);

        //the least important part is the longest
        ConfigNode cborders = node.getSubNode("borders");
        foreach(ConfigNode border; cborders) {
            Border b;
            b.markers[0] = parseMarker(border.getStringValue("marker_a"));
            b.markers[1] = parseMarker(border.getStringValue("marker_b"));
            switch (border["direction"]) {
                case "up":
                    b.action[0] = true;
                    break;
                case "down":
                    b.action[1] = true;
                    break;
                default:
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
        PlaceableObject createObject(string bitmap, bool try_place) {
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
        foreach (ConfigNode onode; objectsNode) {
            createObject(onode["image"], true);
        }

        //hmpf, read all known markers
        auto texnode = node.getSubNode("marker_textures");
        markerTex[Lexel.SolidSoft] = readMarkerTex(texnode, "LAND");
        markerTex[Lexel.SolidHard] = readMarkerTex(texnode, "SOLID_LAND");
    }
}

public class LevelTheme {
    string name;

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

    this(string path, string a_name) {
        //use this function because we want to load resources from it later
        auto conf = gResources.loadConfigForRes(path);

        land = conf.findNode("landscape");
        gen = conf.findNode("landscapegen");
        env = conf.findNode("environment");

        name = a_name;

        if (!land || !gen || !env || !name.length) {
            throw new LoadException(path, "not a level theme or invalid/buggy one");
        }
    }
}

LandscapeBitmap loadLevelLexels(ConfigNode node) {
    auto size = node.getValue!(Vector2i)("size");
    auto levelData = cast(Lexel[])node.getValue!(ubyte[])("data");
    scope(exit) delete levelData;
    if (size.x == 0 || size.y == 0 || levelData.length != size.x*size.y) {
        throw new CustomException("Pregenerated level failed to load");
    }
    return new LandscapeBitmap(size, true, levelData);
}

//store level's size/lexel array into node
void saveLevelLexels(LandscapeBitmap level, ConfigNode node) {
    node.setValue("size", level.size);
    node.setValue!(ubyte[])("data", cast(ubyte[])level.peekLexels());
}

//level is expected to be a data-only level and is taken by reference
GenerateFromTemplate generatorFromLevelLexels(LandscapeBitmap level,
    LevelGeneratorShared shared, bool isCave, bool placeObjects, bool[4] walls)
{
    auto gc = shared.generatorConfig;
    auto node = gc.getSubNode("import_pregenerated").copy();
    auto cave_node = "import_" ~ (isCave ? "cave" : "nocave");
    node.mixinNode(gc.getSubNode(cave_node), false, true);
    if (placeObjects) {
        node.mixinNode(gc.getSubNode("import_placeobjects"), true, true);
    }
    //duplicated from somewhere else and thus sucks donkey balls
    //but I'm not going to de-PITA levelgen/*.d right now, see TODO
    auto landscape = node.getSubNode("objects").getSubNode("land0");
    foreach (int i, ref val; walls) {
        landscape.setValue(LevelLandscape.cWallNames[i], val);
    }
    //
    auto templ = new LevelTemplate(node, "imported");
    return new GenerateFromTemplate(shared, templ, level);
}

//common code for LevelThemes/LevelTemplates ("list" managment)
//T is expected to have a property/member named "name"
template BlaList(T : Object) {
    private {
        T[] mItems;
    }

    T find(string name, bool canfail = false) {
        foreach (T t; mItems) {
            if (t.name == name) {
                return t;
            }
        }
        if (!canfail)
            throw new CustomException("item '" ~ name ~ "' not found");
        return null;
    }

    T findRandom(string name = "") {
        T res = find(name, true);

        if (res)
            return res;

        //pick randomly
        if (mItems.length > 0) {
            uint pick = rngShared.next() % mItems.length;
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

    string[] names() {
        return arrayMap(mItems, (T t) {return t.name;});
    }
}

enum cLevelsPath = "/level";
enum cTemplatesPath = "/levelgen";

//list of found level themes, created from a directory listing on instantiation
//must call update() to read the stuff from disk
class LevelThemes {
    mixin BlaList!(LevelTheme);

    void update() {
        mItems = null;
        gFS.listdir(cLevelsPath, "*", true,
            (string path) {          //path is relative to "level" dir
                LevelTheme theme;
                auto filename = cLevelsPath ~ "/" ~ path ~ "level.conf";

                //xxx how to correctly cut that '/' off? the name is important
                //  to know and must be OS independent
                auto name = path;

                if (!name.length) //yyy tangobos does this
                    return true;

                assert(name.length > 0 && name[$-1] == '/');
                name = name[0..$-1];

                Exception err;
                try {
                    theme = new LevelTheme(filename, name);
                } catch (FilesystemException e) {
                    //seems it wasn't a valid gfx dir, do nothing, config==null
                    //i.e. the data directory contains .svn
                    err = e;
                } catch (CustomException e) {
                    //or some stupid other exception, also do nothing
                    err = e;
                }
                if (theme) {
                    mItems ~= theme;
                } else {
                    mLog.warn("could not load '%s' as LevelTheme: %s", filename,
                        err);
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
        gFS.listdir(cTemplatesPath, "*.conf", false,
            (string path) {
                auto npath = cTemplatesPath ~ "/" ~ path; //uh, relative path
                LevelTemplate templ;
                //xxx error handling is duplicated code from above
                Exception err;
                try {
                    templ = new LevelTemplate(npath, path);
                } catch (FilesystemException e) {
                    err = e;
                } catch (CustomException e) {
                    err = e;
                }
                if (templ) {
                    mItems ~= templ;
                } else {
                    mLog.warn("could not load '%s' as LevelTemplate: %s", path,
                        err);
                }
                return true;
            }
        );
    }
}

//---- and finally, the actual render functions

LandscapeBitmap landscapeRenderGeometry(LandscapeGeometry geometry,
    LandscapeGenTheme gfx)
{
    auto renderer = new LandscapeBitmap(geometry.size);
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
        if (p.visible) {
            renderer.addPolygon(p.points, texoffset, surface,
                p.marker, p.changeable, p.nochange);
        }
    }

    debug {
        counter.stop();
        mLog.minor("geometry: %s", counter.time());
        counter.reset();
        counter.start();
    }

    //borders, must come after geometry
    foreach (b; gfx.borders) {
        renderer.drawBorder(b.markers[0], b.markers[1],
            b.action[0] ? b.textures[0] : null,
            b.action[1] ? b.textures[1] : null);
    }

    debug {
        counter.stop();
        mLog.minor("borders: %s", counter.time());
    }
    return renderer;
}

//lexelData is expected to be a data-only level; returns a texturized copy
LandscapeBitmap landscapeRenderPregenerated(LandscapeBitmap lexelData,
    LandscapeGenTheme gfx)
{
    auto renderer = lexelData.copy();
    assert(renderer && lexelData && gfx);

    renderer.addImage();

    //geometry is already done, so just apply textures
    Surface[] textures;
    for (Lexel i = Lexel.Null; i <= Lexel.Max; i++) {
        textures ~= aaIfIn(gfx.markerTex, i);
    }
    renderer.texturizeData(textures, null);

    //borders, must come after geometry
    foreach (b; gfx.borders) {
        renderer.drawBorder(b.markers[0], b.markers[1],
            b.action[0] ? b.textures[0] : null,
            b.action[1] ? b.textures[1] : null);
    }
    return renderer;
}

/// render a fast, ugly preview; just to see the geometry
/// returns a surface, which shall be freed by the user himself
Surface landscapeRenderPreview(LandscapeGeometry land, Vector2i size,
    Color[Lexel] colors)
{
    //just the fallback for markers[]
    auto nocolor = createPixelSurface(Color(0, 0, 0));

    //oh well...
    Surface[Lexel.Max+1] markers;
    for (Lexel lex = Lexel.Null; lex <= Lexel.Max; lex++) {
        if (lex in colors)
            markers[lex] = createPixelSurface(colors[lex]);
        else
            markers[lex] = nocolor;
    }

    Vector2f scale = toVector2f(size) / toVector2f(land.size);

    auto renderer = new LandscapeBitmap(size);

    //draw background (not drawn when it's not a cave!)
    //(actually, a FillRect would be enough, but...)
    renderer.addPolygon([Vector2i(), size.X, size, size.Y],
        Vector2i(), markers[Lexel.Null], Lexel.Null, false);

    foreach (LandscapeGeometry.Polygon p; land.polygons) {
        //scale down the points first
        auto color = (p.marker <= Lexel.Max) ? markers[p.marker] : nocolor;
        if (p.visible) {
            renderer.addPolygonScaled(scale, p.points, Vector2i(0, 0),
                color, p.marker, false, /+p.changeable,+/ p.nochange);
        }
    }

    foreach (bitmap; markers) {
        bitmap.free();
    }
    nocolor.free();

    Surface s = renderer.createImage();
    renderer.free();
    return s;
}

/// render only the Landscape data, no image
LandscapeBitmap landscapeRenderData(LandscapeGeometry geo, Vector2i size) {
    Vector2f scale = toVector2f(size) / toVector2f(geo.size);
    auto renderer = new LandscapeBitmap(size, true);

    //draw background (not drawn when it's not a cave!)
    //(actually, a FillRect would be enough, but...)
    renderer.addPolygon([Vector2i(), size.X, size, size.Y],
        Vector2i(), null, Lexel.Null, false);

    foreach (LandscapeGeometry.Polygon p; geo.polygons) {
        if (p.visible) {
            renderer.addPolygonScaled(scale, p.points, Vector2i(0, 0),
                null, p.marker, p.changeable, p.nochange);
        }
    }

    return renderer;
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
        mLog.minor("placed objects in %s", counter.time());
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
        mLog.minor("rendered objects in %s", counter.time());
    }
}

