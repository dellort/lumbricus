//OpenGL renderer
module framework.drivers.draw_opengl;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.opengl.extension.arb.texture_non_power_of_two;
import framework.globalsettings;
import framework.drawing;
import framework.driver_base;
import framework.surface;
import tango.math.Math;
import tango.stdc.stringz;
import utils.configfile;
import utils.misc;
import utils.transform;
import utils.log;

import marray = utils.array;
import str = utils.string;
import cstdlib = tango.stdc.stdlib;

const GLuint GLID_INVALID = 0;

const cDrvName = "draw_opengl";

private LogStruct!("OpenGL") mLog;

private struct Options {
    //when an OpenGL surface is created, and the framework surface has caching
    //  enabled, the framework surface's pixel memory is free'd and stored in the
    //  OpenGL texture instead
    //if the framework surface wants to access the pixel memory, it has to call
    //  DriverSurface.getPixelData(), which in turn will read back texture memory
    bool steal_data = true;
    //use fastest OpenGL options, avoid alpha blending; will look fugly
    //(NOTE: it uses alpha test, which may be slower on modern GPUs)
    bool low_quality = false;
    bool batch_draw_calls = true;
    //some cards can't deal with NPOT textures (even if they "support" it)
    bool non_power_of_two = false;
}

char[] glErrorToString(GLenum errCode) {
    char[] res = fromStringz(cast(char*)gluErrorString(errCode));
    //hur, the man page said, "The string is in ISO Latin 1 format." (!=ASCII?)
    //so check it, not that invalid utf-8 strings leak into the GUI or so
    str.validate(res);
    return res;
}

private bool checkGLError(lazy char[] operation, bool crash = false) {
    char[][] errors;
    //an OpenGL driver can have multiple error flags, so you to call glGetError
    //  multiple times to reset them all
    for (;;) {
        GLenum err = glGetError();
        if (err == GL_NO_ERROR)
            break;
        errors ~= glErrorToString(err);
    }
    if (!errors.length)
        return false;
    char[] msg = operation;
    debug mLog.warn("GL error at '{}': {}", msg, errors);
    if (crash)
        throw new Exception(myformat("OpenGL error: '{}': {}", msg, errors));
    return true;
}

class GLDrawDriver : DrawDriver {
    private {
        Vector2i mScreenSize;
        GLCanvas mCanvas;
        Options opts;
    }

    this() {
        DerelictGL.load();
        DerelictGLU.load();

        opts = getSettingsStruct!(Options)(cDrvName);

        mCanvas = new GLCanvas(this);
    }

    override DriverSurface createDriverResource(Resource surface) {
        return new GLSurface(this, castStrict!(Surface)(surface));
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
        mLog.minor("GL supports non-power-of-two: {}",
            ARBTextureNonPowerOfTwo.isEnabled);

        //initialize some static OpenGL context attributes
        if (!opts.low_quality) {
            glEnable(GL_LINE_SMOOTH);
        } else {
            glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);
            //glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_DECAL);
            glShadeModel(GL_FLAT);
        }

        glDisable(GL_DITHER);
        glDisable(GL_DEPTH_TEST);

        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glAlphaFunc(GL_GEQUAL, Color.fromByte(cAlphaTestRef));

        //setup viewport (2D, screen coordinates)
        glViewport(0, 0, mScreenSize.x, mScreenSize.y);

        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        //standard top-zero coordinates
        glOrtho(0, mScreenSize.x, mScreenSize.y, 0, 0, 128);

        glMatrixMode(GL_MODELVIEW);
    }

    override Surface screenshot() {
        Surface res = new Surface(mScreenSize);
        //get screen contents, (0, 0) is bottom left in OpenGL, so
        //  image will be upside-down
        Color.RGBA32* ptr;
        uint pitch;
        res.lockPixelsRGBA32(ptr, pitch);
        assert(pitch == res.size.x);
        glReadPixels(0, 0, mScreenSize.x, mScreenSize.y, GL_RGBA,
            GL_UNSIGNED_BYTE, ptr);
        checkGLError("glReadPixels");
        res.unlockPixels(res.rect());
        //mirror image on x axis
        res.mirror(true, false);
        return res;
    }

    override int getFeatures() {
        return mCanvas.features();
    }

    override void destroy() {
        super.destroy();
        DerelictGLU.unload();
        DerelictGL.unload();
    }

    static this() {
        registerFrameworkDriver!(typeof(this))(cDrvName);
        addSettingsStruct!(Options)(cDrvName);
    }
}

//relies on the byte layout of the members;
//  Vector2f's = struct of two floats
//  Color = struct of 4 floats (r,g,b,a)
//the order and offset of the members is arbitrary (see set_vertex_array())
struct MyVertex {
    Vector2f p;
    Vector2f t;
    //normally not needed
    Color c;
}

final class GLSurface : DriverSurface {
    GLDrawDriver mDrawDriver;
    Vector2i mSize;
    bool mNoCache;

    bool mLocked; //just a loose flag

    GLuint mTexId = GLID_INVALID;
    Vector2f mTexMax;
    Vector2i mTexSize;
    bool mError;

    //create from Framework's data
    this(GLDrawDriver draw_driver, Surface surface) {
        assert(!!surface);
        mDrawDriver = draw_driver;
        mSize = surface.size;
        mNoCache = !surface.enableCaching;

        assert(mTexId == GLID_INVALID);

        //OpenGL textures need width and height to be a power of two
        //at least with older GL drivers
        if (!ARBTextureNonPowerOfTwo.isEnabled
            || !mDrawDriver.opts.non_power_of_two)
        {
            mTexSize = Vector2i(powerOfTwoRoundUp(mSize.x),
                powerOfTwoRoundUp(mSize.y));
        } else {
            mTexSize = mSize;
        }

        bool wantInit;

        if (mTexSize == mSize) {
            //image width and height are already a power of two
            mTexMax.x = 1.0f;
            mTexMax.y = 1.0f;
        } else {
            //image is smaller, parts of the texture will be unused
            mTexMax.x = cast(float)mSize.x / mTexSize.x;
            mTexMax.y = cast(float)mSize.y / mTexSize.y;
            wantInit = true;
        }

        //generate texture and set parameters
        glGenTextures(1, &mTexId);
        assert(mTexId != GLID_INVALID);

        mDrawDriver.mCanvas.rawBindTex(mTexId);

        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);

        //since GL 1.1, pixels pointer can be null, which will just
        //  reserve uninitialized memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, mTexSize.x, mTexSize.y, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, null);

        if (wantInit)
            clearTexBorders(mTexSize, mSize);

        //check for errors (textures larger than maximum size
        //supported by GL/hardware will fail to load)
        if (checkGLError("loading texture")) {
            //set error flag to prevent changing the texture data
            mError = true;

            //create a red replacement texture so the error is well-visible
            uint red = 0xff0000ff; //wee, endian doesn't matter here
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0,
                GL_RGBA, GL_UNSIGNED_BYTE, &red);
        }

        ctor(draw_driver, surface);

        do_update(surface.rect);

        steal();

        if (mError)
            mLog.error("Failed to create texture of size {}.", mTexSize);
    }

    override void destroy() {
        do_destroy(false);
        super.destroy();
    }

    override void loseDataAndDestroy() {
        do_destroy(true);
        //will call do_destroy() again (through destroy()), but that's fine
        super.loseDataAndDestroy();
    }

    private void do_destroy(bool killdata) {
        if (mTexId != GLID_INVALID) {
            if (!killdata)
                lockData(); //possibly read back memory
            mLocked = false;
            glDeleteTextures(1, &mTexId);
            mTexId = GLID_INVALID;
            mDrawDriver.mCanvas.rawBindTex(GLID_INVALID);
        }
        mError = false;
    }

    //initialize borders with 0 (sucks, but otherwise there will be visible
    //  borders of random pixels when scaling/rotating)
    //actually, only the borders need to be initialized
    //assumes GL_RGBA/GL_UNSIGNED_BYTE texture format
    private void clearTexBorders(Vector2i tex, Vector2i bmp) {
        //xxx my solution (you were faster, damn)
        /+uint[] zero = new uint[max(bmp.x + 1, bmp.y + 1)];
        //bottom border
        if (bmp.y < tex.y)
            glTexSubImage2D(GL_TEXTURE_2D, 0, 0, bmp.y, min(bmp.x + 1, tex.x),
                1, GL_RGBA, GL_UNSIGNED_BYTE, zero.ptr);
        //right border
        if (bmp.x < tex.x)
            glTexSubImage2D(GL_TEXTURE_2D, 0, bmp.x, 0, 1,
                min(bmp.y + 1, tex.y), GL_RGBA, GL_UNSIGNED_BYTE, zero.ptr);
        delete zero;+/

        const cSizePx = 4;
        const uint[cSizePx*cSizePx] zero;

        auto clip = Rect2i(tex);

        //clear a small rect starting at pos
        void clearat(Vector2i pos) {
            auto rc = Rect2i.Span(pos, Vector2i(cSizePx));
            //clip for safety, I wonder how drivers would react to out of bounds
            rc.fitInside(clip);
            auto sz = rc.size;
            if (sz.x <= 0 || sz.y <= 0)
                return;
            glTexSubImage2D(GL_TEXTURE_2D, 0, pos.x, pos.y, sz.x, sz.y,
                GL_RGBA, GL_UNSIGNED_BYTE, zero.ptr);
        }

        //bottom border from left to right
        for (int x = 0; x < bmp.x + cSizePx; x += cSizePx) {
            clearat(Vector2i(x, bmp.y));
        }

        //right border from top to bottom
        for (int y = 0; y < bmp.y + cSizePx; y += cSizePx) {
            clearat(Vector2i(bmp.x, y));
        }
    }

    private void do_update(Rect2i rc) {
        //clip rc to the texture area
        rc.fitInsideB(Rect2i(mSize));

        if (rc.size.x <= 0 || rc.size.y <= 0)
            return;

        if (mError)
            return;  //texture failed to load and contains only 1 pixel

        Surface surface = getSurface();
        assert(!!surface); //was deallocated?

        assert(mTexId != GLID_INVALID);
        mDrawDriver.mCanvas.rawBindTex(mTexId);

        Color.RGBA32* texData = surface._rawPixels.ptr;
        assert(!!texData); //was "stolen"? (then update shouldn't be called)

        //make GL read the right data from the full-image array
        glPixelStorei(GL_UNPACK_ROW_LENGTH, mSize.x); //pitch
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

    //ensure all updatePixels() updates are applied and the texture can be used
    package void undirty() {
        //nop
    }

    private void steal() {
        if (mError)
            return;

        if (mLocked || mNoCache)
            return;

        assert(mTexId != GLID_INVALID);

        if (!mDrawDriver.opts.steal_data)
            return;

        if (auto s = getSurface()) {
            //there's no glGetTexSubImage, only glGetTexImage
            // => only works for textures with exact size
            if (mTexSize == mSize) {
                s._pixelsFree();
            }
        }
    }

    override void lockData() {
        mLocked = true;

        if (mError)
            return;

        if (mNoCache)
            return;

        assert(mTexId != GLID_INVALID);

        Surface surface = getSurface();

        if (surface && surface._rawPixels().ptr is null) {
            //can only happen in this mode
            assert(mDrawDriver.opts.steal_data);
            assert(mTexSize == mSize);

            //copy pixels OpenGL surface => Surface pixel array

            mDrawDriver.mCanvas.rawBindTex(mTexId);

            surface._pixelsAlloc();
            Color.RGBA32[] d = surface._rawPixels;
            assert(!!d);

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
    }

    override void unlockData(in Rect2i rc) {
        mLocked = false;
        do_update(rc);
    }
}

class GLCanvas : Canvas3DHelper {
    private {
        GLDrawDriver mDrawDriver;
        //some lazy state managment, because they say glEnable etc. are slow
        Surface state_texture, requested_texture;
        bool state_blend, state_alpha_test;
        GLuint state_bindtexid;
        Vector2f mScale; //switched with transform matrix

        //Vector2f mTranslate;
        Color mBlendColor;

        //lazy drawing; assuming reducing the number of glDrawArrays calls
        //  improves performance
        marray.BigArray!(MyVertex) mVertices;
        size_t mVertexCount;
        int mCurrentVertexMode; //primitive type, as in GL_QUADS etc.
    }

    this(GLDrawDriver drv) {
        mDrawDriver = drv;
        mVertices = new typeof(mVertices)(10000);
    }

    package void startScreenRendering() {
        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

        //some initial states, see set_tex()
        glDisable(GL_TEXTURE_2D);
        state_texture = null;
        glDisable(GL_ALPHA_TEST);
        state_alpha_test = false;
        glEnable(GL_BLEND);
        state_blend = true;

        state_bindtexid = GLID_INVALID;

        mScale = Vector2f(1.0);
        //mTranslate = Vector2f(0.0);

        //flush() and glDrawArrays use this implicitly
        set_vertex_array(mVertices.ptr);

        checkGLError("start rendering", true);

        initFrame(mDrawDriver.mScreenSize);
    }

    package void stopScreenRendering() {
        flush();
        uninitFrame();
        disable_vertex_array();
        requested_texture = null;
    }

    //convience function for glEnable/gdDisable
    private void setGLEnable(int state, bool enable) {
        if (enable)
            glEnable(state);
        else
            glDisable(state);
    }

    private void rawBindTex(GLuint texid) {
        if (texid != GLID_INVALID && texid != state_bindtexid) {
            glBindTexture(GL_TEXTURE_2D, texid);
            //checkGLError("glBindTexture", true);
        }
        state_bindtexid = texid;
    }

    //set vertex pointer + define the vertex format (basically)
    //NOTE: the stuff I used before (GL_T2F_V3F) is just legacy crap
    private void set_vertex_array(MyVertex* ptr) {
        //commonly used "trick" to define an interleaved vertex array
        const stride = MyVertex.sizeof;
        glVertexPointer(2, GL_FLOAT, stride, &ptr[0].p);
        glTexCoordPointer(2, GL_FLOAT, stride, &ptr[0].t);
        glColorPointer(4, GL_FLOAT, stride, &ptr[0].c);
        glEnableClientState(GL_VERTEX_ARRAY);
        glEnableClientState(GL_TEXTURE_COORD_ARRAY);
        glEnableClientState(GL_COLOR_ARRAY);
    }
    private void disable_vertex_array() {
        glDisableClientState(GL_VERTEX_ARRAY);
        glDisableClientState(GL_TEXTURE_COORD_ARRAY);
        glDisableClientState(GL_COLOR_ARRAY);
    }

    //draw everything what's in the mVertices buffer and "clear" the buffer
    //should be called before every change to the GL state
    private void flush() {
        if (!mVertexCount)
            return;

        fix_states();

        //assumes surface is the same value as passed to begin_verts()
        GLSurface surface = state_texture
            ? cast(GLSurface)mDrawDriver.requireDriverResource(state_texture)
            : null;

        if (surface) {
            float ts_x = 1.0f / surface.mTexSize.x;
            float ts_y = 1.0f / surface.mTexSize.y;

            foreach (ref v; mVertices[0..mVertexCount]) {
                v.t.x *= ts_x;
                v.t.y *= ts_y;
            }

            rawBindTex(surface.mTexId);
            surface.undirty();
        }

        if (mBlendColor.valid) {
            //this would be infinitely faster with shaders
            //the fixed pipeline ("normal" GL) probably has something that we
            //  could use, but I wouldn't know
            foreach (ref v; mVertices[0..mVertexCount]) {
                v.c = v.c * mBlendColor;
            }
        }

        assert(mVertexCount <= mVertices.length);
        glDrawArrays(mCurrentVertexMode, 0, mVertexCount);
        mVertexCount = 0;
    }

    private void fix_states() {
        bool want_blend = !mDrawDriver.opts.low_quality;
        bool want_atest = !want_blend;

        if (requested_texture && requested_texture !is state_texture) {
            //xxx not sure about this, may make no sense
            if (mDrawDriver.opts.low_quality) {
                want_blend = true;
                want_atest = false;
            }
        }

        void state(bool want_enable, ref bool cur_state, int glstate) {
            if (want_enable != cur_state) {
                setGLEnable(glstate, want_enable);
                cur_state = want_enable;
            }
        }

        state(want_blend, state_blend, GL_BLEND);
        state(want_atest, state_alpha_test, GL_ALPHA_TEST);

        bool texdummy = !!state_texture;
        state_texture = requested_texture;
        state(!!state_texture, texdummy, GL_TEXTURE_2D);
    }

    //allocate count vertices from the mVertices buffer, and return them
    //the returned vertices get drawn with the next flush()
    //  tex = see set_tex
    //  primitive = primitive type, e.g. GL_QUADS (what's passed to glBegin)
    //  count = number of vertices
    //call end_verts() with returned vertex array after this
    //the vertices' texture coords will be scaled by end_verts()
    private MyVertex[] begin_verts(Surface tex, int primitive,
        size_t count)
    {
        if (mVertexCount + count > mVertices.length)
            flush();

        if (count > mVertices.length) {
            //could handle this, but when does it happen anyway? the caller code
            //  is probably buggy for wanting so many vertices at once
            assert(false, "too many vertices");
        }

        if (requested_texture !is tex) {
            flush();
            requested_texture = tex;
        }

        //you can't just "append" e.g. triangle strips; this breaks (I think)
        static bool can_combine(int vmode) {
            switch (vmode) {
                case GL_LINES, GL_TRIANGLES, GL_QUADS: return true;
                default: return false;
            }
        }

        if (mCurrentVertexMode != primitive || !can_combine(primitive))
            flush();

        mCurrentVertexMode = primitive;

        auto res = mVertices[mVertexCount..mVertexCount+count];
        mVertexCount += count;

        return res;
    }

    private void end_verts(MyVertex[] verts) {
        /+foreach (ref v; verts) {
            v.p += mTranslate;
        }+/

        //may help with state bugs etc.
        if (!mDrawDriver.opts.batch_draw_calls) {
            assert(mVertexCount == verts.length);
            flush();
        }
    }

    public int features() {
        return DriverFeatures.canvasScaling | DriverFeatures.transformedQuads
            | DriverFeatures.usingOpenGL;
    }

    final void do_draw(Surface surface, Vector2i destP, Vector2i sourceP,
        Vector2i destS, Transform2f* tr, Color col = Color(1.0f))
    {
        //fun fact: writing int[2] bla = [1,2]; allocates memory on the heap
        Vector2f[2] p = void, t = void;

        p[0] = toVector2f(destP);
        p[1] = toVector2f(destP + destS);

        //pixel coords; will be refitted to 0.0-1.0 in end_verts()
        t[0] = toVector2f(sourceP);
        t[1] = toVector2f(sourceP+destS);

        MyVertex[] verts = begin_verts(surface, GL_QUADS, 4);

        verts[0].t = Vector2f(t[0].x, t[0].y);
        verts[0].p = Vector2f(p[0].x, p[0].y);
        verts[0].c = col;

        verts[1].t = Vector2f(t[0].x, t[1].y);
        verts[1].p = Vector2f(p[0].x, p[1].y);
        verts[1].c = col;

        verts[2].t = Vector2f(t[1].x, t[1].y);
        verts[2].p = Vector2f(p[1].x, p[1].y);
        verts[2].c = col;

        verts[3].t = Vector2f(t[1].x, t[0].y);
        verts[3].p = Vector2f(p[1].x, p[0].y);
        verts[3].c = col;

        /+ is this better or worse than the code above?
        static const int[4] cX = [0, 0, 1, 1], cY = [0, 1, 1, 0];
        foreach (int i, ref v; verts) {
            int x = cX[i], y = cY[i];
            v.p.x = p[x].x;
            v.p.y = p[y].y;
            v.t.x = t[x].x;
            v.t.y = t[y].y;
        }
        +/

        if (tr) {
            //you also could construct a 4D matrix out of tr, and do
            //  glPushMatrix; glMultMatrixf; glPopMatrix
            //but it would be slower
            foreach (ref v; verts) {
                v.p = tr.transform(v.p);
            }
        }

        end_verts(verts);
    }

    override void lineWidth(int width) {
        flush();

        glLineWidth(width);
    }

    override void lineStipple(int length) {
        flush();

        setGLEnable(GL_LINE_STIPPLE, length > 0);
        if (length > 0) {
            //first parameter is essentially the length of each bit in pixels
            glLineStipple(length, 0b1010_1010_1010_1010);
        }
    }

    override void updateTransform(Vector2i trans, Vector2f scale) {
        //using mTranslate is commented because no measureable speed advantage
        //if (mScale != scale) {
            flush();

            mScale = scale;

            glLoadIdentity();
            glTranslatef(trans.x, trans.y, 0); //not when mTranslate is used
            glScalef(mScale.x, mScale.y, 1);
            checkGLError("update transform", true);
        //}

        //mTranslate = toVector2f(trans);
        mBlendColor = currentBlend();
    }

    override void updateClip(Vector2i p1, Vector2i p2) {
        flush();

        glEnable(GL_SCISSOR_TEST);
        //negative w/h values generate GL errors
        auto sz = (p2 - p1).max(Vector2i(0));
        glScissor(p1.x, realSize.y-p2.y, sz.x, sz.y);
        checkGLError("doClip", true);
    }

    public void clear(Color color) {
        flush();

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
        MyVertex[] verts2 = begin_verts(tex, cPrimMap[primitive], verts.length);

        //this is silly, but who cares; better be independent from Vertex2f
        foreach (size_t i, v; verts) {
            verts2[i].p = v.p;
            verts2[i].t = toVector2f(v.t);
            verts2[i].c = v.c;
        }

        end_verts(verts2);
    }

    override void drawSprite(SubSurface source, Vector2i destPos,
        BitmapEffect* effect = null)
    {
        //on my nvidia card, this brings a slight speed up
        //and nvidia is known for having _good_ opengl drivers
        if (!spriteVisible(source, destPos, effect))
            return;

        if (!effect)
            effect = &BitmapEffect.init;

        //create an explicit 2D matrix according to BitmapEffect
        //the version using glTranslate etc. is still in r920 in drawFast()

        Transform2f tr = effect.getTransform(source.size, destPos);

        do_draw(source.surface, Vector2i(0), source.origin, source.size, &tr,
            effect.color);
    }

    //Note: GL-specific tiling code removed with r932

    override void drawPart(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        //clipping, discard anything that would be invisible anyway
        if (!visibleArea.intersects(destPos, destPos + sourceSize))
            return;

        do_draw(source, destPos, sourcePos, sourceSize, null);
    }
}
