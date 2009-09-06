//contains the OpenGL part of the SDL driver, not as well separated as it
//should be
module framework.sdl.fwgl;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import framework.framework;
import framework.sdl.framework;
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

/*
abstract class DrawCache {
}

class DrawCacheGl : DrawCache {
    private {
        Texture mSource;
        Vector2i mDest, mSourcePos, mSourceSize, mAdvance;
        GLuint mListId = 0;
        GLuint mCachedTexId = 0;
    }

    this(Texture source, Vector2i destOffset,
        Vector2i sourcePos, Vector2i sourceSize, Vector2i advance)
    {
        mSource = source;
        mDest = destOffset;
        mSourcePos = sourcePos;
        mSourceSize = sourceSize;
        mAdvance = advance;
    }

    void validate() {
        assert(mSource !is null);
        GLSurface glsurf = cast(GLSurface)(mSource.getDriverSurface(
            SurfaceMode.NORMAL));
        assert(glsurf !is null);
        if (mListId == 0 || mCachedTexId != glsurf.mTexId) {
            mCachedTexId = glsurf.mTexId;
            mListId = glGenLists(1);
            assert(mListId > 0, "glGenLists failed");
            glNewList(mListId, GL_COMPILE);
            glsurf.prepareDraw2();
            GLCanvas.simpleDraw(mSourcePos, mDest, mSourceSize, glsurf, false);
            glTranslatef(cast(float)mAdvance.x, cast(float)mAdvance.y, 0f);
            glEndList();
        }
    }

    void call() {
        glCallList(mListId);
    }
}
*/

class GLSurface : SDLDriverSurface {
    const GLuint GLID_INVALID = 0;

    GLuint mTexId = GLID_INVALID;
    Vector2f mTexMax;
    Vector2i mTexSize;
    bool mError;

    //create from Framework's data
    this(SurfaceData data) {
        super(data);
        assert(data.data !is null);
        reinit();
    }

    void releaseSurface() {
        if (mTexId != GLID_INVALID) {
            getPixelData(); //possibly read back memory
            glDeleteTextures(1, &mTexId);
            mTexId = GLID_INVALID;
            mError = false;
        }
        if (mData) {
            assert(mData.data !is null);
        }
    }

    override void kill() {
        releaseSurface();
        super.kill();
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
            updateTexture(Rect2i(mData.size));
        }

        steal();
    }

    //like updatePixels, but assumes texture is already bound (and does
    //less error checking)
    private void updateTexture(in Rect2i rc) {
        if (rc.size.x <= 0 || rc.size.y <= 0)
            return;

        if (mError)
            return;  //texture failed to load and contains only 1 pixel

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
        if (mError)
            return;

        assert(mTexId != GLID_INVALID);

        //clip rc to the texture area
        rc.fitInsideB(Rect2i(mData.size));
        glBindTexture(GL_TEXTURE_2D, mTexId);
        updateTexture(rc);
    }

    void steal() {
        if (mError)
            return;

        assert(mTexId != GLID_INVALID);

        if (!(cStealSurfaceData && gSDLDriver.mEnableCaching))
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

        checkGLError("prepareDraw", true);
    }

    void endDraw() {
        glDisable(GL_TEXTURE_2D);
        glDisable(GL_ALPHA_TEST);
        glDisable(GL_BLEND);

        checkGLError("endDraw", true);
    }

    /*
    private void prepareDraw2() {
        glBindTexture(GL_TEXTURE_2D, mTexId);
    }

    DrawCache cachePrepare(Texture source, Vector2i destOffset,
        Vector2i sourcePos, Vector2i sourceSize, Vector2i advance)
    {
        auto ret = new DrawCacheGl(source, destOffset, sourcePos, sourceSize,
            advance);
        ret.validate();
        return ret;
    }
    */

    char[] toString() {
        return myformat("GLSurface, {}, id={}, data={}",
            mData ? mData.size : Vector2i(-1), mTexId,
            mData ? mData.data.length : -1);
    }
}

class GLCanvas : Canvas {
    const int MAX_STACK = 30;

    private {
        struct State {
            bool enableClip;
            Rect2i clip;
            Vector2i translate;
            Vector2i clientsize;
            Vector2f scale = {1.0f, 1.0f};
        }

        State[MAX_STACK] mStack;
        uint mStackTop; //point to next free stack item (i.e. 0 on empty stack)
        Rect2i mParentArea, mVisibleArea;
    }

    void startScreenRendering() {
        mStack[0].clientsize = Vector2i(gSDLDriver.mSDLScreen.w,
            gSDLDriver.mSDLScreen.h);
        mStack[0].clip.p2 = mStack[0].clientsize;
        mStack[0].enableClip = false;

        initGLViewport();

        gSDLDriver.mClearTime.start();
        auto clearColor = Color(0,0,0);
        clear(clearColor);
        gSDLDriver.mClearTime.stop();

        checkGLError("start rendering", true);

        startDraw();
    }

    void stopScreenRendering() {
        endDraw();

        checkGLError("end rendering", true);

        gSDLDriver.mFlipTime.start();
        SDL_GL_SwapBuffers();
        gSDLDriver.mFlipTime.stop();

        checkGLError("SDK_GL_swapBuffers", true);
    }

    package void startDraw() {
        assert(mStackTop == 0);
        pushState();
    }
    public void endDraw() {
        popState();
        assert(mStackTop == 0);
    }

    public int features() {
        return gSDLDriver.getFeatures();
    }

    private void initGLViewport() {
        glViewport(0, 0, mStack[0].clientsize.x, mStack[0].clientsize.y);

        glMatrixMode(GL_PROJECTION);
        glLoadIdentity();
        //standard top-zero coordinates
        glOrtho(0, mStack[0].clientsize.x, 0, mStack[0].clientsize.y, 0, 128);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();
        glScalef(1, -1, 1);
        glTranslatef(0, -mStack[0].clientsize.y, 0);
        //glTranslatef(0, 1, 0);

        glDisable(GL_SCISSOR_TEST);

        bool lowquality = gSDLDriver.mOpenGL_LowQuality;
        if (!lowquality) {
            glEnable(GL_LINE_SMOOTH);
        } else {
            glHint(GL_PERSPECTIVE_CORRECTION_HINT, GL_FASTEST);
            glDisable(GL_DITHER);
            //glTexEnvf(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_DECAL);
            glShadeModel(GL_FLAT);
        }

        checkGLError("initGLViewport", true);
    }

    //screen size
    public Vector2i realSize() {
        return mStack[0].clientsize;
    }
    //drawable size
    public Vector2i clientSize() {
        return mStack[mStackTop].clientsize;
    }

    //area of the parent window, in current client coords
    public Rect2i parentArea() {
        return mParentArea;
    }

    //what is shown on the screen (in client coords)
    public Rect2i visibleArea() {
        return mVisibleArea;
    }

    //updates parentArea / visibleArea after translating/clipping/scaling
    private void updateAreas() {
        if (mStackTop > 0) {
            mParentArea.p1 =
                -mStack[mStackTop].translate + mStack[mStackTop - 1].translate;
            mParentArea.p1 =
                toVector2i(toVector2f(mParentArea.p1) /mStack[mStackTop].scale);
            mParentArea.p2 = mParentArea.p1 + mStack[mStackTop - 1].clientsize;
        } else {
            mParentArea.p1 = mParentArea.p2 = Vector2i(0);
        }

        mVisibleArea = mStack[mStackTop].clip - mStack[mStackTop].translate;
        mVisibleArea.p1 =
            toVector2i(toVector2f(mVisibleArea.p1) / mStack[mStackTop].scale);
        mVisibleArea.p2 =
            toVector2i(toVector2f(mVisibleArea.p2) / mStack[mStackTop].scale);
    }

    public void translate(Vector2i offset) {
        glTranslatef(cast(float)offset.x, cast(float)offset.y, 0);
        checkGLError("glTranslatef", true);
        mStack[mStackTop].translate += toVector2i(toVector2f(offset)
            ^ mStack[mStackTop].scale);
        updateAreas();
    }
    public void setWindow(Vector2i p1, Vector2i p2) {
        clip(p1, p2);
        translate(p1);
        mStack[mStackTop].clientsize = p2 - p1;
        updateAreas();
    }
    public void clip(Vector2i p1, Vector2i p2) {
        p1 = toVector2i(toVector2f(p1) ^ mStack[mStackTop].scale);
        p2 = toVector2i(toVector2f(p2) ^ mStack[mStackTop].scale);
        p1 += mStack[mStackTop].translate;
        p2 += mStack[mStackTop].translate;
        p1 = mStack[mStackTop].clip.clip(p1);
        p2 = mStack[mStackTop].clip.clip(p2);
        mStack[mStackTop].clip = Rect2i(p1, p2);
        doClip(p1, p2);
        updateAreas();
    }
    private void doClip(Vector2i p1, Vector2i p2) {
        mStack[mStackTop].enableClip = true;
        glEnable(GL_SCISSOR_TEST);
        //negative w/h values generate GL errors
        auto sz = (p2 - p1).max(Vector2i(0));
        glScissor(p1.x, realSize.y-p2.y, sz.x, sz.y);
        checkGLError("doClip", true);
    }
    public void setScale(Vector2f z) {
        glScalef(z.x, z.y, 1);
        checkGLError("glScalef", true);
        mStack[mStackTop].clientsize =
            toVector2i(toVector2f(mStack[mStackTop].clientsize) / z);
        mStack[mStackTop].scale = mStack[mStackTop].scale ^ z;
        updateAreas();
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        checkGLError("before pushState", true);

        glPushMatrix();
        mStack[mStackTop+1] = mStack[mStackTop];
        mStackTop++;
        updateAreas();

        checkGLError("pushState", true);
    }
    public void popState() {
        assert(mStackTop > 0);

        checkGLError("before popState", true);

        glPopMatrix();
        mStackTop--;
        if (mStack[mStackTop].enableClip) {
            doClip(mStack[mStackTop].clip.p1, mStack[mStackTop].clip.p2);
        } else {
            glDisable(GL_SCISSOR_TEST);
            checkGLError("glDisable(GL_SCISSOR_TEST)", true);
        }
        updateAreas();

        checkGLError("popState", true);
    }

    public void clear(Color color) {
        if (mStackTop == 0) {
            glClearColor(color.r, color.g, color.b, color.a);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        } else {
            drawFilledRect(Vector2i(0,0), clientSize, color);
        }

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

    private void markAlpha(Vector2i p, Vector2i size) {
        if (!gSDLDriver.mMarkAlpha)
            return;
        auto c = Color(0,1,0);
        drawRect(p, p + size, c);
        drawLine(p, p + size, c);
        drawLine(p + size.Y, p + size.X, c);

        checkGLError("markAlpha", true);
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
        Color[2] c;
        c[0] = c[1] = color;
        doDrawRect(p1, p2, c);
    }

    void doDrawRect(Vector2i p1, Vector2i p2, Color[2] c) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        //p2.x -= 1; //border exclusive
        //p2.y -= 1;

        bool alpha = (c[0].hasAlpha() || c[1].hasAlpha());
        if (alpha) {
            glEnable(GL_BLEND);
            glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        }

        //xxx WTF? I don't understand this (the -1), but the result still looks
        //right (equal to SDL's rendering), so I keep this (wtf...)
        //glTranslatef(0.5f, 0.5f-1.0f, 0);
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

        if (alpha)
            markAlpha(p1, p2-p1);
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

        bool alpha = c.hasAlpha();
        if (alpha) {
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

        if (alpha)
            markAlpha(p1, p2-p1);
    }

    public void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize,
        bool mirrorY = false)
    {
        drawTextureInt(source, sourcePos, sourceSize, destPos, sourceSize,
            mirrorY);
    }

    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        drawTextureInt(source, Vector2i(0,0), source.size, destPos, destSize);
    }

    private static void simpleDraw(Vector2i sourceP, Vector2i destP, Vector2i destS,
        GLSurface gls, bool mirrorY = false) {
        Vector2i p1 = destP;
        Vector2i p2 = destP + destS;
        Vector2f t1, t2;

        //select the right part of the texture (in 0.0-1.0 coordinates)
        t1.x = cast(float)sourceP.x / gls.mTexSize.x;
        t1.y = cast(float)sourceP.y / gls.mTexSize.y;
        t2.x = cast(float)(sourceP.x+destS.x) / gls.mTexSize.x;
        t2.y = cast(float)(sourceP.y+destS.y) / gls.mTexSize.y;

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

    //this will draw the texture source tiled in the destination area
    //optimized if no tiling needed or tiling can be done by OpenGL
    //tiling only works for the above case (i.e. when using the whole texture)
    private void drawTextureInt(Texture source, Vector2i sourcePos,
        Vector2i sourceSize, Vector2i destPos, Vector2i destSize,
        bool mirrorY = false)
    {
        //clipping, discard anything that would be invisible anyway
        if (!mVisibleArea.intersects(destPos, destPos + destSize))
            return;

        if (gSDLDriver.glWireframeDebug) {
            //wireframe mode
            drawRect(destPos, destPos+destSize, Color(1,1,1));
            drawLine(destPos, destPos+destSize, Color(1,1,1));
            return;
        }

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();
        assert(glsurf !is null);

        //glPushAttrib(GL_ENABLE_BIT);
        checkGLError("draw texture - begin", true);
        glDisable(GL_DEPTH_TEST);
        glsurf.prepareDraw();


        //tiling can be done by OpenGL if texture space is fully used
        bool glTilex = glsurf.mTexMax.x == 1.0f;
        bool glTiley = glsurf.mTexMax.y == 1.0f;

        //check if either no tiling is needed, or it can be done entirely by GL
        bool noTileSpecial = (glTilex || destSize.x <= sourceSize.x)
            && (glTiley || destSize.y <= sourceSize.y);

        if (noTileSpecial) {
            //pure OpenGL drawing (and tiling)
            simpleDraw(sourcePos, destPos, destSize, glsurf, mirrorY);
        } else {
            //manual tiling code, partially using OpenGL tiling if possible
            //xxx sorry for code duplication, but the differences seemed too big
            int w = glTilex?destSize.x:sourceSize.x;
            int h = glTiley?destSize.y:sourceSize.y;
            int x;
            Vector2i tmp;

            int y = 0;
            while (y < destSize.y) {
                tmp.y = destPos.y + y;
                int resty = ((y+h) < destSize.y) ? h : destSize.y - y;
                //check visibility (y coordinate)
                if (tmp.y + resty > mVisibleArea.p1.y
                    && tmp.y < mVisibleArea.p2.y)
                {
                    x = 0;
                    while (x < destSize.x) {
                        tmp.x = destPos.x + x;
                        int restx = ((x+w) < destSize.x) ? w : destSize.x - x;
                        //visibility check for x coordinate
                        if (tmp.x + restx > mVisibleArea.p1.x
                            && tmp.x < mVisibleArea.p2.x)
                        {
                            simpleDraw(Vector2i(0, 0), tmp,
                                Vector2i(restx, resty), glsurf, mirrorY);
                        }
                        x += restx;
                    }
                }
                y += resty;
            }
        }

        GLboolean isalpha;
        if (gSDLDriver.mMarkAlpha)
            glGetBooleanv(GL_BLEND, &isalpha);

        glsurf.endDraw();

        checkGLError("draw texture - end", true);

        if (isalpha)
            markAlpha(destPos, sourceSize);
    }

    public void drawQuad(Surface source, Vertex2i[4] quad) {
        //xxx code duplication with above, sorry I was too lazy

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)source.getDriverSurface();
        assert(glsurf !is null);

        //glPushAttrib(GL_ENABLE_BIT);
        checkGLError("draw texture 2", true);
        glDisable(GL_DEPTH_TEST);
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

    /*
    public void cachedBegin(Vector2i destPos, Transparency tr) {
        glPushMatrix();
        glEnable(GL_TEXTURE_2D);
        glDisable(GL_DEPTH_TEST);
        switch (tr) {
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
        glTranslatef(cast(float)destPos.x, cast(float)destPos.y, 0f);
    }

    public void cachedDraw(DrawCache cache) {
        auto c = cast(DrawCacheGl)cache;
        assert(!!c);
        c.validate();
        c.call();
    }

    public void cachedEnd() {
        glPopMatrix();
        glDisable(GL_TEXTURE_2D);
        glDisable(GL_ALPHA_TEST);
        glDisable(GL_BLEND);
    }
    */
}
