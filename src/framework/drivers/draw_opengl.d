//OpenGL renderer
module framework.drivers.draw_opengl;

import derelict.opengl.gl;
import derelict.opengl.glu;
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

final class GLSurface : DriverSurface {
    const GLuint GLID_INVALID = 0;

    GLDrawDriver mDrawDriver;
    SurfaceData mData;

    GLuint mTexId = GLID_INVALID;
    Vector2f mTexMax;
    Vector2i mTexSize;
    bool mError;

    //GL display lists for drawing sub surfaces
    //in sync with mData.subsurfaces / SubSurface.index()
    GLuint[] mSubSurfaces;

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
        foreach (GLuint s; mSubSurfaces) {
            glDeleteLists(s, 1);
        }
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

    void prepareDraw() {
        undirty();

        glEnable(GL_TEXTURE_2D);

        //activate blending for proper alpha display
        switch (mData.transparency) {
            case Transparency.Colorkey:
                glEnable(GL_ALPHA_TEST);
                glAlphaFunc(GL_GREATER, 0.1f);
                break;
            case Transparency.Alpha:
                glEnable(GL_BLEND);
                glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
                break;
            default:
        }

        glBindTexture(GL_TEXTURE_2D, mTexId);

        //

        checkGLError("prepareDraw", true);
    }

    void endDraw() {
        glDisable(GL_TEXTURE_2D);
        glDisable(GL_ALPHA_TEST);
        glDisable(GL_BLEND);

        checkGLError("endDraw", true);
    }

    override void newSubSurface(SubSurface ss) {
        createSubSurfaces(mData.subsurfaces[ss.index..ss.index+1]);
    }

    private void createSubSurfaces(SubSurface[] subs) {
        static assert(mSubSurfaces[0].init == GLID_INVALID); //array init, hurf

        if (!mDrawDriver.mUseSubSurfaces)
            return;

        foreach (s; subs) {
            if (s.index() >= mSubSurfaces.length) {
                mSubSurfaces.length = s.index() + 1;
            }
            if (mSubSurfaces[s.index] != GLID_INVALID)
                continue;
            GLuint nid = glGenLists(1);
            if (nid == GLID_INVALID) {
                checkGLError("out of display lists?");
                assert(false); //shouldn't happen; must have generated GL error
            }
            glNewList(nid, GL_COMPILE);
                prepareDraw();
                simpleDraw(s.origin, Vector2i(0), s.size);
                endDraw();
            glEndList();
            mSubSurfaces[s.index] = nid;
        }
    }

    final void simpleDraw(Vector2i sourceP, Vector2i destP,
        Vector2i destS, bool mirrorY = false)
    {
        Vector2i p1 = destP;
        Vector2i p2 = destP + destS;
        Vector2f t1, t2;

        //select the right part of the texture (in 0.0-1.0 coordinates)
        t1.x = cast(float)sourceP.x / mTexSize.x;
        t1.y = cast(float)sourceP.y / mTexSize.y;
        t2.x = cast(float)(sourceP.x+destS.x) / mTexSize.x;
        t2.y = cast(float)(sourceP.y+destS.y) / mTexSize.y;

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
    }


    char[] toString() {
        return myformat("GLSurface, {}, id={}, data={}",
            mData ? mData.size : Vector2i(-1), mTexId,
            mData ? mData.data.length : -1);
    }
}

class GLCanvas : Canvas {
    private {
        GLDrawDriver mDrawDriver;
    }

    this(GLDrawDriver drv) {
        mDrawDriver = drv;
    }

    void startScreenRendering() {
        initFrame(mDrawDriver.mScreenSize);

        initGLViewport();

        clear(Color(0,0,0));

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

    private void initGLViewport() {
        auto scrsize = mDrawDriver.mScreenSize;

        glViewport(0, 0, scrsize.x, scrsize.y);

        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        //standard top-zero coordinates
        glOrtho(0, scrsize.x, 0, scrsize.y, 0, 128);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glScalef(1, -1, 1);
        glTranslatef(0, -scrsize.y, 0);
        //glTranslatef(0, 1, 0);

        glDisable(GL_SCISSOR_TEST);

        bool lowquality = mDrawDriver.mLowQuality;
        if (!lowquality) {
            glEnable(GL_LINE_SMOOTH);
        } else {
            glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);
            glDisable(GL_DITHER);
            //glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_DECAL);
            glShadeModel(GL_FLAT);
        }

        glDisable(GL_DEPTH_TEST); //??

        checkGLError("initGLViewport", true);
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
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

        checkGLError("clear", true);
    }

    public void drawCircle(Vector2i center, int radius, Color color) {
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(color.ptr);
        stroke_circle(center.x, center.y, radius);
        glColor3f(1.0f, 1.0f, 1.0f);

        glDisable(GL_BLEND);

        checkGLError("drawCircle", true);
    }

    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(color.ptr);
        fill_circle(center.x, center.y, radius);
        glColor3f(1.0f, 1.0f, 1.0f);

        glDisable(GL_BLEND);

        checkGLError("drawFilledCircle", true);
    }

    //Code from Luigi, www.dsource.org/projects/luigi, BSD license
    //Copyright (C) 2006 William V. Baxter III
    //Luigi begin -->
    void fill_circle(float x, float y, float radius, int slices=16)
    {
        glTranslatef(x,y,0);
        glBegin(GL_TRIANGLE_FAN);
        glVertex2f(0,0);
        float astep = 2*PI/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = i*astep;
            float c = radius*cos(a);
            float s = radius*sin(a);
            glVertex2f(c,s);
        }
        glEnd();
        glTranslatef(-x,-y,0);

        checkGLError("full_circle", true);
    }

    void stroke_circle(float x, float y, float radius=1, int slices=16)
    {
        glTranslatef(x,y,0);
        glBegin(GL_LINE_LOOP);
        float astep = 2*PI/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = i*astep;
            float c = radius*cos(a);
            float s = radius*sin(a);
            glVertex2f(c,s);
        }
        glEnd();
        glTranslatef(-x,-y,0);

        checkGLError("stroke_circle", true);
    }

    void fill_arc(float x, float y, float radius, float start, float radians,
        int slices=16)
    {
        glTranslatef(x,y,0);
        glBegin(GL_TRIANGLE_FAN);
        glVertex2f(0,0);
        float astep = radians/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = start+i*astep;
            float c = radius*cos(a);
            float s = -radius*sin(a);
            glVertex2f(c,s);
        }
        glEnd();
        glTranslatef(-x,-y,0);

        checkGLError("fill_arc", true);
    }

    void stroke_arc(float x, float y, float radius, float start, float radians,
        int slices=16)
    {
        glTranslatef(x,y,0);
        glBegin(GL_LINE_LOOP);
        glVertex2f(0,0);
        float astep = radians/slices;
        for(int i=0; i<slices+1; i++)
        {
            float a = start+i*astep;
            float c = radius*cos(a);
            float s = -radius*sin(a);
            glVertex2f(c,s);
        }
        glEnd();
        glTranslatef(-x,-y,0);

        checkGLError("stroke_arc", true);
    }
    //<-- Luigi end

    public void drawLine(Vector2i p1, Vector2i p2, Color color, int width = 1) {
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glLineWidth(width);

        glColor4fv(color.ptr);

        float trans = width%2==0?0f:0.5f;

        //fixes blurry lines with GL_LINE_SMOOTH
        glTranslatef(trans, trans, 0);
        glBegin(GL_LINES);
            glVertex2i(p1.x, p1.y);
            glVertex2i(p2.x, p2.y);
        glEnd();
        glTranslatef(-trans, -trans, 0);

        glColor3f(1.0f, 1.0f, 1.0f);
        glDisable(GL_BLEND);
        glLineWidth(1);

        checkGLError("drawLine", true);
    }

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        p2.x -= 1; //border exclusive
        p2.y -= 1;

        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(color.ptr);

        //fixes blurry lines with GL_LINE_SMOOTH
        glTranslatef(0.5f, 0.5f, 0);
        glBegin(GL_LINE_LOOP);
            glVertex2i(p1.x, p1.y);
            glVertex2i(p1.x, p2.y);
            glVertex2i(p2.x, p2.y);
            glVertex2i(p2.x, p1.y);
        glEnd();
        glTranslatef(-0.5f, -0.5f, 0);

        glColor3f(1.0f, 1.0f, 1.0f);
        glDisable(GL_BLEND);

        checkGLError("drawRect", true);
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
        Color[2] c;
        c[0] = c[1] = color;
        doDrawRect(p1, p2, c);
    }

    void doDrawRect(Vector2i p1, Vector2i p2, Color[2] c) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;

        if (c[0].hasAlpha() || c[1].hasAlpha()) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }

        glBegin(GL_QUADS);
            glColor4fv(c[0].ptr);
            glVertex2i(p2.x, p1.y);
            glVertex2i(p1.x, p1.y);
            glColor4fv(c[1].ptr);
            glVertex2i(p1.x, p2.y);
            glVertex2i(p2.x, p2.y);
        glEnd();

        glDisable(GL_BLEND);
        glColor3f(1.0f, 1.0f, 1.0f);

        checkGLError("doDrawRect", true);
    }

    public void drawVGradient(Rect2i rc, Color c1, Color c2) {
        Color[2] c;
        c[0] = c1;
        c[1] = c2;
        doDrawRect(rc.p1, rc.p2, c);
    }

    public void drawPercentRect(Vector2i p1, Vector2i p2, float perc, Color c) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        //0 -> nothing visible
        if (perc < float.epsilon)
            return;

        if (c.hasAlpha()) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }

        //calculate arc angle from percentage (0% is top with an angle of pi/2)
        //increasing percentage adds counter-clockwise
        //xxx what about reversing rotation?
        float a = (perc+0.25)*2*PI;
        //the "do-it-yourself" tangens (invert y -> math to screen coords)
        Vector2f av = Vector2f(cos(a)/abs(sin(a)), -sin(a)/abs(cos(a)));
        av = av.clipAbsEntries(Vector2f(1f));
        Vector2f center = toVector2f(p1+p2)/2.0f;
        //this is the arc end-point on the rectangle border
        Vector2f pOuter = center + ((0.5f*av) ^ toVector2f(p2-p1));

        void doVertices() {
            glVertex2f(center.x, center.y);
            glVertex2f(center.x, p1.y);
            scope(exit) glVertex2f(pOuter.x, pOuter.y);
            //not all corners are always visible
            if (perc<0.125) return;
            glVertex2i(p1.x, p1.y);
            if (perc<0.375) return;
            glVertex2i(p1.x, p2.y);
            if (perc<0.625) return;
            glVertex2i(p2.x, p2.y);
            if (perc<0.875) return;
            glVertex2i(p2.x, p1.y);
        }

        //triangle fan is much faster than polygon
        glBegin(GL_TRIANGLE_FAN);
            glColor4fv(c.ptr);
            doVertices();
        glEnd();

        glDisable(GL_BLEND);
        glColor3f(1.0f, 1.0f, 1.0f);

        checkGLError("drawClockRect", true);
    }

    public void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize,
        bool mirrorY = false)
    {
        drawTextureInt(source, sourcePos, sourceSize, destPos, sourceSize,
            mirrorY);
    }

    override void drawFast(SubSurface source, Vector2i destPos,
        bool mirrorY = false)
    {
        if (!mDrawDriver.mUseSubSurfaces) {
            //disabled; normal code path
            super.drawFast(source, destPos, mirrorY);
            return;
        }

        //on my nvidia card, this brings a slight speed up
        //and nvidia is known for having _good_ opengl drivers
        if (!visibleArea.intersects(destPos, destPos + source.size))
            return;

        GLSurface glsurf = cast(GLSurface)source.surface.getDriverSurface();

        glsurf.undirty();

        glTranslatef(destPos.x, destPos.y, 0.0f);
        if (mirrorY) {
            glTranslatef(source.size.x, 0.0f, 0.0f);
            glScalef(-1.0f, 1.0f, 1.0f);
        }
        glCallList(glsurf.mSubSurfaces[source.index]);
        if (mirrorY) {
            glScalef(-1.0f, 1.0f, 1.0f);
            glTranslatef(-source.size.x, 0.0f, 0.0f);
        }
        glTranslatef(-destPos.x, -destPos.y, 0.0f);
    }

    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        drawTextureInt(source, Vector2i(0,0), source.size, destPos, destSize);
    }

    //this will draw the texture source tiled in the destination area
    //optimized if no tiling needed or tiling can be done by OpenGL
    //tiling only works for the above case (i.e. when using the whole texture)
    private void drawTextureInt(Texture source, Vector2i sourcePos,
        Vector2i sourceSize, Vector2i destPos, Vector2i destSize,
        bool mirrorY = false)
    {
        //clipping, discard anything that would be invisible anyway
        if (!visibleArea.intersects(destPos, destPos + destSize))
            return;

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();
        assert(glsurf !is null);

        //glPushAttrib(GL_ENABLE_BIT);
        checkGLError("draw texture - begin", true);
        glsurf.prepareDraw();


        //tiling can be done by OpenGL if texture space is fully used
        bool glTilex = glsurf.mTexMax.x == 1.0f;
        bool glTiley = glsurf.mTexMax.y == 1.0f;

        //check if either no tiling is needed, or it can be done entirely by GL
        bool noTileSpecial = (glTilex || destSize.x <= sourceSize.x)
            && (glTiley || destSize.y <= sourceSize.y);

        if (noTileSpecial) {
            //pure OpenGL drawing (and tiling)
            glsurf.simpleDraw(sourcePos, destPos, destSize, mirrorY);
        } else {
            //manual tiling code, partially using OpenGL tiling if possible
            //xxx sorry for code duplication, but the differences seemed too big
            int w = glTilex?destSize.x:sourceSize.x;
            int h = glTiley?destSize.y:sourceSize.y;
            int x;
            Vector2i tmp;

            auto varea = visibleArea();

            int y = 0;
            while (y < destSize.y) {
                tmp.y = destPos.y + y;
                int resty = ((y+h) < destSize.y) ? h : destSize.y - y;
                //check visibility (y coordinate)
                if (tmp.y + resty > varea.p1.y
                    && tmp.y < varea.p2.y)
                {
                    x = 0;
                    while (x < destSize.x) {
                        tmp.x = destPos.x + x;
                        int restx = ((x+w) < destSize.x) ? w : destSize.x - x;
                        //visibility check for x coordinate
                        if (tmp.x + restx > varea.p1.x
                            && tmp.x < varea.p2.x)
                        {
                            glsurf.simpleDraw(Vector2i(0, 0), tmp,
                                Vector2i(restx, resty), mirrorY);
                        }
                        x += restx;
                    }
                }
                y += resty;
            }
        }

        glsurf.endDraw();

        checkGLError("draw texture - end", true);
    }

    public void drawQuad(Surface source, Vertex2i[4] quad) {
        //xxx code duplication with above, sorry I was too lazy

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();
        assert(glsurf !is null);

        //glPushAttrib(GL_ENABLE_BIT);
        checkGLError("draw texture 2", true);
        glsurf.prepareDraw();


        glBegin(GL_QUADS);

        for (int i = 0; i < 4; i++) {
            auto tx = cast(float)quad[i].t.x / glsurf.mTexSize.x;
            auto ty = cast(float)quad[i].t.y / glsurf.mTexSize.y;
            glTexCoord2f(tx, ty);
            glVertex2i(quad[i].p.x, quad[i].p.y);
        }

        glEnd();

        glsurf.endDraw();
    }

}
