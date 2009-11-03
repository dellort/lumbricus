//OpenGL renderer
module framework.drivers.draw_opengl;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.opengl.extension.arb.texture_non_power_of_two;
import framework.framework;
import framework.drawing;
import tango.math.Math;
import tango.stdc.stringz;
import str = utils.string;
import utils.misc;
import cstdlib = tango.stdc.stdlib;

//when an OpenGL surface is created, and the framework surface has caching
//  enabled, the framework surface's pixel memory is free'd and stored in the
//  OpenGL texture instead
//if the framework surface wants to access the pixel memory, it has to call
//  DriverSurface.getPixelData(), which in turn will read back texture memory
const bool cStealSurfaceData = true;


char[] glErrorToString(GLenum errCode) {
    char[] res = fromStringz(cast(char*)gluErrorString(errCode));
    //hur, the man page said, "The string is in ISO Latin 1 format." (!=ASCII?)
    //so check it, not that invalid utf-8 strings leak into the GUI or so
    str.validate(res);
    return res;
}

private bool checkGLError(char[] msg, bool crash = false) {
    GLenum err = glGetError();
    if (err == GL_NO_ERROR)
        return false;
    debug Trace.formatln("Warning: GL error at '{}': {}", msg,
        glErrorToString(err));
    if (crash)
        assert(false, "not continuing");
    return true;
}

class GLDrawDriver : DrawDriver {
    private {
        Vector2i mScreenSize;
        GLCanvas mCanvas;
        bool mStealData, mLowQuality, mUseSubSurfaces, mBatchSubTex;
    }

    this(ConfigNode config) {
        DerelictGL.load();
        DerelictGLU.load();

        mStealData = config.getBoolValue("steal_data", true);
        mLowQuality = config.getBoolValue("lowquality", false);
        mUseSubSurfaces = config.getValue!(bool)("subsurfaces", true);
        mBatchSubTex = config.getValue!(bool)("batch_subtex", false);

        mCanvas = new GLCanvas(this);
    }

    override DriverSurface createSurface(SurfaceData data) {
        return new GLSurface(this, data);
    }

    override Canvas startScreenRendering() {
        mCanvas.startScreenRendering();
        return mCanvas;
    }

    override void stopScreenRendering() {
        mCanvas.stopScreenRendering();
    }

    override void initVideoMode(Vector2i screen_size) {
        assert(screen_size.quad_length > 0);
        mScreenSize = screen_size;
        DerelictGL.loadExtensions();
        debug Trace.formatln("GL supports non-power-of-two: {}",
            ARBTextureNonPowerOfTwo.isEnabled);

        //initialize some static OpenGL context attributes
        if (!mLowQuality) {
            glEnable(GL_LINE_SMOOTH);
        } else {
            glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);
            //glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_DECAL);
            glShadeModel(GL_FLAT);
        }

        glDisable(GL_DITHER);
        glDisable(GL_DEPTH_TEST); //??

        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glAlphaFunc(GL_GREATER, 0.1f);

        //setup viewport (2D, screen coordinates)
        glViewport(0, 0, mScreenSize.x, mScreenSize.y);

        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        //standard top-zero coordinates
        glOrtho(0, mScreenSize.x, 0, mScreenSize.y, 0, 128);

        glMatrixMode(GL_MODELVIEW);
    }

    override Surface screenshot() {
        Surface res = new Surface(mScreenSize, Transparency.None);
        //get screen contents, (0, 0) is bottom left in OpenGL, so
        //  image will be upside-down
        Color.RGBA32* ptr;
        uint pitch;
        res.lockPixelsRGBA32(ptr, pitch);
        assert(pitch == res.size.x);
        glReadPixels(0, 0, mScreenSize.x, mScreenSize.y, GL_RGBA,
            GL_UNSIGNED_BYTE, ptr);
        //checkGLError("glReadPixels");
        //mirror image on x axis
        res.getData().doMirrorX();
        res.unlockPixels(res.rect());
        return res;
    }

    override int getFeatures() {
        return mCanvas.features();
    }

    override void destroy() {
        DerelictGLU.unload();
        DerelictGL.unload();
    }

    static this() {
        DrawDriverFactory.register!(typeof(this))("opengl");
    }
}

//corresponds to GL_T2F_V3F
//relies on Vector2f's byte layout (struct of two floats)
struct Vertex_T2F_V3F {
    Vector2f t;
    Vector2f p;
    float p3 = 0.0f; //z
}

final class GLSurface : DriverSurface {
    const GLuint GLID_INVALID = 0;

    GLDrawDriver mDrawDriver;
    SurfaceData mData;

    GLuint mTexId = GLID_INVALID;
    Vector2f mTexMax;
    Vector2i mTexSize;
    bool mError;

    //vertex array for all subrects, cVertCount vertices for each subrect
    //in sync with mData.subsurfaces / SubSurface.index()
    Vertex_T2F_V3F[] mSubSurfaces;
    const cVertCount = 4;

    //for mBatchSubTex; region that needs to be updated
    bool mIsDirty;
    Rect2i mDirtyRect;

    //create from Framework's data
    this(GLDrawDriver draw_driver, SurfaceData data) {
        mDrawDriver = draw_driver;
        mData = data;
        assert(data.data !is null);
        reinit();
    }

    void releaseSurface() {
        if (mTexId != GLID_INVALID) {
            getPixelData(); //possibly read back memory
            glDeleteTextures(1, &mTexId);
            mTexId = GLID_INVALID;
        }
        freeSubsurfaces();
        mError = false;
        if (mData) {
            assert(mData.data !is null);
        }
    }

    private void freeSubsurfaces() {
        mSubSurfaces = null;
    }

    override void kill() {
        releaseSurface();
        mData = null;
    }

    void reinit() {
        //releaseSurface();
        assert(mTexId == GLID_INVALID);

        //OpenGL textures need width and heigth to be a power of two
        //could use GL_ARB_texture_non_power_of_two
        mTexSize = Vector2i(powerOfTwo(mData.size.x),
            powerOfTwo(mData.size.y));
        if (mTexSize == mData.size) {
            //image width and height are already a power of two
            mTexMax.x = 1.0f;
            mTexMax.y = 1.0f;
        } else {
            //image is smaller, parts of the texture will be unused
            mTexMax.x = cast(float)mData.size.x / mTexSize.x;
            mTexMax.y = cast(float)mData.size.y / mTexSize.y;
        }

        //generate texture and set parameters
        glGenTextures(1, &mTexId);
        assert(mTexId != GLID_INVALID);
        glBindTexture(GL_TEXTURE_2D, mTexId);
        checkGLError("glBindTexture", true);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        checkGLError("texpar", true);

        //since GL 1.1, pixels pointer can be null, which will just
        //reserve uninitialized memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, mTexSize.x, mTexSize.y, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, null);

        checkGLError("load texture", true);

        //check for errors (textures larger than maximum size
        //supported by GL/hardware will fail to load)
        if (checkGLError("loading texture")) {
            //set error flag to prevent changing the texture data
            mError = true;
            debug Trace.formatln("Failed to create texture of size {}.",
                mTexSize);
            //throw new Exception(
            //    "glTexImage2D failed, probably texture was too big. "
            //    ~ "Requested size: "~mTexSize.toString);

            //create a red replacement texture so the error is well-visible
            uint red = 0xff0000ff; //wee, endian doesn't matter here
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0,
                GL_RGBA, GL_UNSIGNED_BYTE, &red);
        } else {
            do_update(Rect2i(mData.size));
        }

        steal();

        //recreate all SubSurfaces
        createSubSurfaces(mData.subsurfaces);
    }

    private void do_update(Rect2i rc) {
        //clip rc to the texture area
        rc.fitInsideB(Rect2i(mData.size));

        mIsDirty = false;

        if (rc.size.x <= 0 || rc.size.y <= 0)
            return;

        if (mError)
            return;  //texture failed to load and contains only 1 pixel

        assert(mTexId != GLID_INVALID);
        glBindTexture(GL_TEXTURE_2D, mTexId);

        Color.RGBA32* texData = mData.data.ptr;
        assert(!!texData);

        //make GL read the right data from the full-image array
        glPixelStorei(GL_UNPACK_ROW_LENGTH, mData.size.x); //pitch
        glPixelStorei(GL_UNPACK_SKIP_ROWS, rc.p1.y);
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, rc.p1.x);

        glTexSubImage2D(GL_TEXTURE_2D, 0, rc.p1.x, rc.p1.y, rc.size.x,
            rc.size.y, GL_RGBA, GL_UNSIGNED_BYTE, texData);

        //reset unpack values
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);

        checkGLError("update texture", true);
    }

    void updatePixels(in Rect2i rc) {
        if (rc.size.x <= 0 || rc.size.y <= 0)
            return;

        if (mDrawDriver.mBatchSubTex) {
            //defer update to later when it's needed (on drawing)
            if (!mIsDirty) {
                mIsDirty = true;
                mDirtyRect = rc;
            }
            mDirtyRect.extend(rc);
        } else {
            do_update(rc);
        }
    }

    //ensure all updatePixels() updates are applied
    package void undirty() {
        if (mIsDirty) {
            do_update(mDirtyRect);
        }
    }

    void steal() {
        if (mError)
            return;

        assert(mTexId != GLID_INVALID);

        if (!(cStealSurfaceData && mDrawDriver.mStealData))
            return;

        if (mData.data !is null && mData.canSteal()) {
            assert(!mData.data_locked);
            //there's no glGetTexSubImage, only glGetTexImage
            // => only works for textures with exact size
            if (mTexSize == mData.size) {
                mData.pixels_free();
            }
        }
    }

    void getPixelData() {
        if (mError)
            return;

        assert(mTexId != GLID_INVALID);

        if (mData.data is null) {
            assert(cStealSurfaceData); //can only happen in this mode
            assert (mTexSize == mData.size);

            //copy pixels OpenGL surface => mData.data
            mData.pixels_alloc();

            glBindTexture(GL_TEXTURE_2D, mTexId);
            checkGLError("glBindTexture", true);

            auto d = mData.data;

            debug {
                GLint w, h;
                glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_WIDTH,
                    &w);
                glGetTexLevelParameteriv(GL_TEXTURE_2D, 0, GL_TEXTURE_HEIGHT,
                    &h);
                assert(Vector2i(w,h) == mTexSize);
                assert((cast(ubyte[])d).length >= w*h*4);
            }

            glGetTexImage(GL_TEXTURE_2D, 0, GL_RGBA, GL_UNSIGNED_BYTE, d.ptr);
            checkGLError("glGetTexImage", true);
        }

        assert(mData.data !is null);
    }

    void getInfos(out char[] desc, out uint extra_data) {
        desc = myformat("GLSurface, texid={}", mTexId);
    }

    override void newSubSurface(SubSurface ss) {
        createSubSurfaces(mData.subsurfaces[ss.index..ss.index+1]);
    }

    private void createSubSurfaces(SubSurface[] subs) {
        if (!mDrawDriver.mUseSubSurfaces)
            return;

        foreach (s; subs) {
            if (s.index() * cVertCount >= mSubSurfaces.length) {
                mSubSurfaces.length = (s.index() + 1) * cVertCount;
            }

            int base = s.index * cVertCount;

            void add(int tx, int ty, int px, int py) {
                auto vert = &mSubSurfaces[base++];
                vert.p = Vector2f(px, py);
                vert.t = Vector2f(tx, ty) / toVector2f(mTexSize);
            }

            static assert(cVertCount == 4);
            add(s.rect.p1.x, s.rect.p1.y, 0,        0);
            add(s.rect.p1.x, s.rect.p2.y, 0,        s.size.y);
            add(s.rect.p2.x, s.rect.p2.y, s.size.x, s.size.y);
            add(s.rect.p2.x, s.rect.p1.y, s.size.x, 0);
        }
    }

    final void bind() {
        //the glEnable(GL_TEXTURE_2D) and the other ones are handled by canvas
        glBindTexture(GL_TEXTURE_2D, mTexId);

        if (mDrawDriver.mUseSubSurfaces) {
            Vertex_T2F_V3F* pverts = mSubSurfaces.ptr;
            glInterleavedArrays(GL_T2F_V3F, Vertex_T2F_V3F.sizeof, pverts);
        }

        //xxx this could break if the user updates the texture during
        //  drawing, because set_tex() early exits if the texture is the
        //  same
        undirty();
    }

    final void complicatedDraw(SubSurface sub) {
        glDrawArrays(GL_QUADS, sub.index*cVertCount, cVertCount);
    }

    final void simpleDraw(Vector2i destP, Vector2i sourceP, Vector2i destS,
        bool mirrorY = false)
    {
        Vector2i p1 = destP;
        Vector2i p2 = destP + destS;
        Vector2f t1, t2;

        //select the right part of the texture (in 0.0-1.0 coordinates)
        t1.x = cast(float)sourceP.x / mTexSize.x;
        t1.y = cast(float)sourceP.y / mTexSize.y;
        t2.x = cast(float)(sourceP.x+destS.x) / mTexSize.x;
        t2.y = cast(float)(sourceP.y+destS.y) / mTexSize.y;

        checkGLError("before draw");

        //draw textured rect
        glBegin(GL_QUADS);

        if (!mirrorY) {
            glTexCoord2f(t1.x, t1.y); glVertex2i(p1.x, p1.y);
            glTexCoord2f(t1.x, t2.y); glVertex2i(p1.x, p2.y);
            glTexCoord2f(t2.x, t2.y); glVertex2i(p2.x, p2.y);
            glTexCoord2f(t2.x, t1.y); glVertex2i(p2.x, p1.y);
        } else {
            glTexCoord2f(t2.x, t1.y); glVertex2i(p1.x, p1.y);
            glTexCoord2f(t2.x, t2.y); glVertex2i(p1.x, p2.y);
            glTexCoord2f(t1.x, t2.y); glVertex2i(p2.x, p2.y);
            glTexCoord2f(t1.x, t1.y); glVertex2i(p2.x, p1.y);
        }

        glEnd();

        checkGLError("after draw");
    }


    char[] toString() {
        return myformat("GLSurface, {}, id={}, data={}",
            mData ? mData.size : Vector2i(-1), mTexId,
            mData ? mData.data.length : -1);
    }
}

class GLCanvas : Canvas3DHelper {
    private {
        GLDrawDriver mDrawDriver;
        //some lazy state managment, because they say glEnable etc. are slow
        GLSurface state_texture;
        bool state_blend, state_alpha_test;
    }

    this(GLDrawDriver drv) {
        mDrawDriver = drv;
    }

    void startScreenRendering() {
        auto scrsize = mDrawDriver.mScreenSize;

        initFrame(scrsize);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glScalef(1, -1, 1);
        glTranslatef(0, -scrsize.y, 0);

        //some initial states, see set_tex()
        glDisable(GL_TEXTURE_2D);
        state_texture = null;
        glDisable(GL_ALPHA_TEST);
        state_alpha_test = false;
        glEnable(GL_BLEND);
        state_blend = true;

        checkGLError("start rendering", true);

        pushState();
    }

    void stopScreenRendering() {
        popState();
        uninitFrame();
    }

    public int features() {
        return DriverFeatures.canvasScaling | DriverFeatures.transformedQuads
            | DriverFeatures.usingOpenGL;
    }

    //pass null to enable untextured drawing (also enables alpha blending)
    private void set_tex(GLSurface tex) {
        if (state_texture is tex)
            return;

        bool want_tex = false;
        bool want_blend = false;
        bool want_atest = false;

        if (!tex) {
            want_blend = true; //blending for lines etc.
        } else {
            want_tex = true;
            tex.bind();
            switch (tex.mData.transparency) {
                case Transparency.Colorkey:
                    want_atest = true;
                    break;
                case Transparency.Alpha:
                    want_blend = true;
                    break;
                default:
            }
        }

        void state(bool want_enable, ref bool cur_state, int glstate) {
            if (want_enable && !cur_state) {
                glEnable(glstate);
            } else if (!want_enable && cur_state) {
                glDisable(glstate);
            }
            cur_state = want_enable;
        }

        state(want_blend, state_blend, GL_BLEND);
        state(want_atest, state_alpha_test, GL_ALPHA_TEST);

        bool texdummy = !!state_texture;
        state(want_tex, texdummy, GL_TEXTURE_2D);
        state_texture = tex;
    }

    override void lineWidth(int width) {
        glLineWidth(width);
    }

    override void updateTranslate(Vector2i offset) {
        glTranslatef(cast(float)offset.x, cast(float)offset.y, 0);
        checkGLError("glTranslatef", true);
    }

    override void updateClip(Vector2i p1, Vector2i p2) {
        glEnable(GL_SCISSOR_TEST);
        //negative w/h values generate GL errors
        auto sz = (p2 - p1).max(Vector2i(0));
        glScissor(p1.x, realSize.y-p2.y, sz.x, sz.y);
        checkGLError("doClip", true);
    }

    override void updateScale(Vector2f z) {
        glScalef(z.x, z.y, 1);
        checkGLError("glScalef", true);
    }

    override void pushState() {
        super.pushState();

        checkGLError("before pushState", true);
        glPushMatrix();
        checkGLError("pushState", true);
    }
    override void popState() {
        //this will call updateClip(), which calls glScissor
        //that is before glPopMatrix(); but glScissor uses window coordinates
        super.popState();

        checkGLError("before popState", true);
        glPopMatrix();
        checkGLError("popState", true);
    }

    public void clear(Color color) {
        //NOTE: glClear respects the scissor test (glScissor)
        glClearColor(color.r, color.g, color.b, color.a);
        glClear(GL_COLOR_BUFFER_BIT);

        checkGLError("clear", true);
    }

    private static const int[] cPrimMap = [
        Primitive.LINES : GL_LINES,
        Primitive.LINE_STRIP : GL_LINE_STRIP,
        Primitive.LINE_LOOP : GL_LINE_LOOP,
        Primitive.TRIS : GL_TRIANGLES,
        Primitive.TRI_STRIP : GL_TRIANGLE_STRIP,
        Primitive.TRI_FAN : GL_TRIANGLE_FAN,
        Primitive.QUADS : GL_QUADS,
    ];

    override void draw_verts(Primitive primitive, Surface tex,
        Vertex2f[] verts)
    {
        GLSurface glsurf = tex ? cast(GLSurface)tex.getDriverSurface() : null;
        assert(!!glsurf == !!tex);

        float ts_x = 1.0f, ts_y = 1.0f;

        set_tex(glsurf);

        if (glsurf) {
            ts_x = 1.0f / glsurf.mTexSize.x;
            ts_y = 1.0f / glsurf.mTexSize.y;
        }

        glBegin(cPrimMap[primitive]);
            foreach (ref v; verts) {
                glTexCoord2f(v.t.x * ts_x, v.t.y * ts_y);
                glColor4fv(v.c.ptr);
                glVertex2f(v.p.x, v.p.y);
            }
        glEnd();

        glEnable(GL_BLEND);

        glColor3f(1.0f, 1.0f, 1.0f);
    }

    override void drawFast(SubSurface source, Vector2i destPos,
        BitmapEffect* effect = null)
    {
        if (!mDrawDriver.mUseSubSurfaces) {
            //disabled; normal code path
            drawTextureInt(source.surface, destPos, source.origin, source.size,
                effect ? effect.mirrorY : false);
            return;
        }

        //on my nvidia card, this brings a slight speed up
        //and nvidia is known for having _good_ opengl drivers
        //NOTE: this clipping is incorrect for scaled/rotated bitmaps
        if (!visibleArea.intersects(destPos, destPos + source.size))
            return;

        GLSurface glsurf = cast(GLSurface)source.surface.getDriverSurface();

        set_tex(glsurf);

        if (effect) {
            glPushMatrix();
        }

        glTranslatef(destPos.x, destPos.y, 0.0f);
        if (effect) {
            //would it be faster to somehow create a direct matrix for all this?
            if (effect.scale != 1.0f) {
                glScalef(effect.scale, effect.scale, 0.0f);
            }
            if (effect.rotate != 0.0f) {
                glRotatef(effect.rotate/math.PI*180.0f, 0.0f, 0.0f, -1.0f);
            }
            glTranslatef(-effect.center.x, -effect.center.y, 0.0f);
            if (effect.mirrorY) {
                glTranslatef(source.size.x, 0.0f, 0.0f);
                glScalef(-1.0f, 1.0f, 1.0f);
            }
        }

        glsurf.complicatedDraw(source);

        if (effect) {
            glPopMatrix();
        } else {
            glTranslatef(-destPos.x, -destPos.y, 0.0f);
        }
    }

    override void drawTiled(Surface source, Vector2i destPos, Vector2i destSize)
    {
        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();

        //tiling can be done by OpenGL if texture space is fully used
        bool glTilex = glsurf.mTexMax.x == 1.0f;
        bool glTiley = glsurf.mTexMax.y == 1.0f;

        //check if either no tiling is needed, or it can be done entirely by GL
        bool noTileSpecial = (glTilex || destSize.x <= source.size.x)
            && (glTiley || destSize.y <= source.size.y);

        if (noTileSpecial) {
            //pure OpenGL drawing (and tiling)
            //because we want it super-efficient
            //I wonder if it really is, I bet OpenGL is not good at clipping
            //  down very big polygons
            drawTextureInt(source, destPos, Vector2i(0), destSize);
        } else {
            super.drawTiled(source, destPos, destSize);
        }
    }

    override void draw(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        debug {
            sourceSize = source.size.min(sourceSize);
            sourcePos = source.size.min(sourcePos);
        }
        drawTextureInt(source, destPos, sourcePos, sourceSize);
    }

    //this will draw the texture source tiled in the destination area
    //optimized if no tiling needed or tiling can be done by OpenGL
    //tiling only works for the above case (i.e. when using the whole texture)
    private void drawTextureInt(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i destSize, bool mirrorY = false)
    {
        //clipping, discard anything that would be invisible anyway
        if (!visibleArea.intersects(destPos, destPos + destSize))
            return;

        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();
        set_tex(glsurf);
        glsurf.simpleDraw(destPos, sourcePos, destSize, mirrorY);
    }
}
