//contains the OpenGL part of the SDL driver, not as well separated as it
//should be
module framework.sdl.fwgl;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import framework.framework;
import framework.sdl.framework;
import framework.drawing;
import std.math;
import std.string;
import utf = std.utf;
import utils.misc;

debug import std.stdio;

char[] glErrorToString(GLenum errCode) {
    char[] res = toString(cast(char*)gluErrorString(errCode));
    //hur, the man page said, "The string is in ISO Latin 1 format." (!=ASCII?)
    //so check it, not that invalid utf-8 strings leak into the GUI or so
    utf.validate(res);
    return res;
}

class GLSurface : SDLDriverSurface {
    const GLuint GLID_INVALID = 0;

    GLuint mTexId = GLID_INVALID;
    Vector2f mTexMax;
    Vector2i mTexSize;
    bool mError;

    //create from Framework's data
    this(SurfaceData* data) {
        super(data);
        reinit();
    }

    void releaseSurface() {
        if (mTexId != GLID_INVALID) {
            glDeleteTextures(1, &mTexId);
            mTexId = GLID_INVALID;
        }
    }

    override void kill() {
        releaseSurface();
        super.kill();
    }

    void reinit() {
        releaseSurface();

        //OpenGL textures need width and heigth to be a power of two
        mTexSize = Vector2i(powerOfTwo(mData.size.x),
            powerOfTwo(mData.size.y));
        if (mTexSize == mData.size) {
            //image width and heigth are already a power of two
            mTexMax.x = 1.0f;
            mTexMax.y = 1.0f;
        } else {
            //image is smaller, parts of the texture will be unused
            mTexMax.x = cast(float)mData.size.x / mTexSize.x;
            mTexMax.y = cast(float)mData.size.y / mTexSize.y;
        }

        //generate texture and set parameters
        glGenTextures(1, &mTexId);
        glBindTexture(GL_TEXTURE_2D, mTexId);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);

        //since GL 1.1, pixels pointer can be null, which will just
        //reserve uninitialized memory
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, mTexSize.x, mTexSize.y, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, null);

        //check for errors (textures larger than maximum size
        //supported by GL/hardware will fail to load)
        GLenum err = glGetError();
        if (err != GL_NO_ERROR) {
            //set error flag to prevent changing the texture data
            mError = true;
            debug writefln("Failed to create texture of size %s: %s",mTexSize,
                glErrorToString(err));
            //throw new Exception(
            //    "glTexImage2D failed, probably texture was too big. "
            //    ~ "Requested size: "~mTexSize.toString);

            //create a red replacement texture so the error is well-visible
            uint red = 0xff0000ff;
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0,
                GL_RGBA, GL_UNSIGNED_BYTE, &red);
        } else {
            updateTexture(Rect2i(Vector2i(0),mData.size), true);
        }
    }

    void getPixelData() {
        //nop, nothing free'd for now
    }

    //like updatePixels, but assumes texture is already bound (and does
    //less error checking)
    private void updateTexture(in Rect2i rc, bool full = false) {
        void* texData;
        SDL_Surface *texSurface;
        if (rc.size.x <= 0 || rc.size.y <= 0)
            return;
        if (mData.transparency == Transparency.Colorkey) {
            //transparency uses colorkeying -> convert to alpha
            SDL_Surface *srcSurface = SDL_CreateRGBSurfaceFrom(mData.data.ptr,
                mData.size.x, mData.size.y, 32, mData.pitch, 0x000000FF,
                0x0000FF00, 0x00FF0000, 0xFF000000);
            assert(srcSurface);

            texSurface = SDL_CreateRGBSurface(SDL_SWSURFACE, rc.size.x,
                rc.size.y, 32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
            assert(texSurface);
            //xxx OpenGL does not have a pitch value and data should be
            //4-byte-aligned anyway
            assert(texSurface.pitch == texSurface.w*4);

            //clear transparency - I don't know why, the surface has just been
            //created and should not have any
            SDL_SetAlpha(srcSurface, 0, 0);
            //activate colorkeying for source surface
            uint key = simpleColorToSDLColor(srcSurface,
                mData.colorkey);
            SDL_SetColorKey(srcSurface, SDL_SRCCOLORKEY, key);

            //Copy the surface into the GL texture image
            //Blitting converts colorkey images to alpha images, because only
            //non-transparent pixels are overwritten
            SDL_Rect areasrc, areadest;
            areasrc.x = rc.p1.x;
            areasrc.y = rc.p1.y;
            areasrc.w = areadest.w = rc.size.x;
            areasrc.h = areadest.h = rc.size.y;
            SDL_BlitSurface(srcSurface, &areasrc, texSurface, &areadest);
            SDL_FreeSurface(srcSurface);

            texData = texSurface.pixels;
            full = true;
        } else {
            //transparency format matches -> use directly
            texData = mData.data.ptr;
            assert(mData.pitch == mData.size.x*4);
        }

        //make GL read the right data from the full-image array
        if (!full) {
            glPixelStorei(GL_UNPACK_ROW_LENGTH, mData.size.x);
            glPixelStorei(GL_UNPACK_SKIP_ROWS, rc.p1.y);
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, rc.p1.x);
        }

        glTexSubImage2D(GL_TEXTURE_2D, 0, rc.p1.x, rc.p1.y, rc.size.x,
            rc.size.y, GL_RGBA, GL_UNSIGNED_BYTE, texData);

        //reset unpack values
        glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
        glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);

        if (texSurface)
            SDL_FreeSurface(texSurface);
    }

    void updatePixels(in Rect2i rc) {
        if (mError)
            return;  //texture failed to load and contains only 1 pixel
        if (mTexId == GLID_INVALID) {
            reinit();
        } else {
            assert(mData.pitch == mData.size.x*4);
            //caller has to assure that rc intersects with the
            //texture area at all
            //not anymore, I don't see any reason for this
            //assert(rc.p1.x < mData.size.x && rc.p1.y < mData.size.y);
            //assert(rc.p2.x > 0 && rc.p2.y > 0);
            //now clip rc to the texture area
            rc.fitInsideB(Rect2i(0,0,mData.size.x,mData.size.y));
            glBindTexture(GL_TEXTURE_2D, mTexId);
            updateTexture(rc);
        }
    }

    void getInfos(out char[] desc, out uint extra_data) {
        desc = format("GLSurface, texid=%s", mTexId);
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
        }

        Vector2i mTrans;
        State[MAX_STACK] mStack;
        uint mStackTop; //point to next free stack item (i.e. 0 on empty stack)

        Vector2i mClientSize;
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

        startDraw();
    }

    void stopScreenRendering() {
        endDraw();

        gSDLDriver.mFlipTime.start();
        SDL_GL_SwapBuffers();
        gSDLDriver.mFlipTime.stop();
    }

    package void startDraw() {
        assert(mStackTop == 0);
        pushState();
    }
    public void endDraw() {
        popState();
        assert(mStackTop == 0);
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
    }

    public Vector2i realSize() {
        return mStack[0].clientsize;
    }
    public Vector2i clientSize() {
        return mStack[mStackTop].clientsize;
    }

    public Vector2i clientOffset() {
        return -mStack[mStackTop].translate;
    }

    public Rect2i getVisible() {
        return mStack[mStackTop].clip - mStack[mStackTop].translate;
    }

    public void translate(Vector2i offset) {
        glTranslatef(cast(float)offset.x, cast(float)offset.y, 0);
        mStack[mStackTop].translate += offset;
    }
    public void setWindow(Vector2i p1, Vector2i p2) {
        clip(p1, p2);
        translate(p1);
        mStack[mStackTop].clientsize = p2 - p1;
    }
    public void clip(Vector2i p1, Vector2i p2) {
        p1 += mStack[mStackTop].translate;
        p2 += mStack[mStackTop].translate;
        p1 = mStack[mStackTop].clip.clip(p1);
        p2 = mStack[mStackTop].clip.clip(p2);
        mStack[mStackTop].clip = Rect2i(p1, p2);
        doClip(p1, p2);
    }
    private void doClip(Vector2i p1, Vector2i p2) {
        mStack[mStackTop].enableClip = true;
        glEnable(GL_SCISSOR_TEST);
        glScissor(p1.x, realSize.y-p2.y, p2.x-p1.x, p2.y-p1.y);
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        glPushMatrix();
        mStack[mStackTop+1] = mStack[mStackTop];
        mStackTop++;
    }
    public void popState() {
        assert(mStackTop > 0);

        glPopMatrix();
        mStackTop--;
        if (mStack[mStackTop].enableClip)
            doClip(mStack[mStackTop].clip.p1, mStack[mStackTop].clip.p2);
        else
            glDisable(GL_SCISSOR_TEST);
    }

    public void clear(Color color) {
        if (mStackTop == 0) {
            glClearColor(color.r, color.g, color.b, color.a);
            glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
        } else {
            drawFilledRect(Vector2i(0,0), clientSize, color);
        }
    }

    public void drawCircle(Vector2i center, int radius, Color color) {
        glPushAttrib(GL_CURRENT_BIT);
        glColor4fv(color.ptr);
        stroke_circle(center.x, center.y, radius);
        glPopAttrib();
    }

    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        glPushAttrib(GL_CURRENT_BIT);
        glColor4fv(color.ptr);
        fill_circle(center.x, center.y, radius);
        glPopAttrib();
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
    }
    //<-- Luigi end

    public void drawLine(Vector2i p1, Vector2i p2, Color color) {
        glPushMatrix();
        glPushAttrib(GL_ENABLE_BIT | GL_CURRENT_BIT);
        glDisable(GL_TEXTURE_2D);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(color.ptr);

        //fixes blurry lines with GL_LINE_SMOOTH
        glTranslatef(0.5f, 0.5f, 0);
        glBegin(GL_LINES);
            glVertex2i(p1.x, p1.y);
            glVertex2i(p2.x, p2.y);
        glEnd();

        glPopAttrib();
        glPopMatrix();
    }

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
        if (p1.x >= p2.x || p1.y >= p2.y)
            return;
        p2.x -= 1; //border exclusive
        p2.y -= 1;

        glPushMatrix();
        glPushAttrib(GL_ENABLE_BIT | GL_CURRENT_BIT);
        glDisable(GL_TEXTURE_2D);
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

        glPopAttrib();
        glPopMatrix();
    }

    private void markAlpha(Vector2i p, Vector2i size) {
        if (!gSDLDriver.mMarkAlpha)
            return;
        auto c = Color(0,1,0);
        drawRect(p, p + size, c);
        drawLine(p, p + size, c);
        drawLine(p + size.Y, p + size.X, c);
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

        //glPushMatrix();
        glPushAttrib(GL_ENABLE_BIT | GL_CURRENT_BIT);
        glDisable(GL_TEXTURE_2D);
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

        glPopAttrib();
        //glPopMatrix();

        if (alpha)
            markAlpha(p1, p2-p1);
    }

    public void drawVGradient(Rect2i rc, Color c1, Color c2) {
        Color[2] c;
        c[0] = c1;
        c[1] = c2;
        doDrawRect(rc.p1, rc.p2, c);
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

    //this will draw the texture source tiled in the destination area
    //optimized if no tiling needed or tiling can be done by OpenGL
    //tiling only works for the above case (i.e. when using the whole texture)
    private void drawTextureInt(Texture source, Vector2i sourcePos,
        Vector2i sourceSize, Vector2i destPos, Vector2i destSize,
        bool mirrorY = false)
    {
        //clipping, discard anything that would be invisible anyway
        Vector2i pr1 = destPos+mStack[mStackTop].translate;
        Vector2i pr2 = pr1+destSize;
        if (pr1.x > mStack[0].clientsize.x || pr1.y > mStack[0].clientsize.y
            || pr2.x < 0 || pr2.y < 0)
            return;

        if (gSDLDriver.glWireframeDebug) {
            //wireframe mode
            drawRect(destPos, destPos+destSize, Color(1,1,1));
            drawLine(destPos, destPos+destSize, Color(1,1,1));
            return;
        }

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)(source.getDriverSurface(
            SurfaceMode.NORMAL));
        assert(glsurf !is null);

        glPushAttrib(GL_ENABLE_BIT);
        assert(glGetError() == GL_NO_ERROR);
        glDisable(GL_DEPTH_TEST);
        glsurf.prepareDraw();


        //tiling can be done by OpenGL if texture space is fully used
        bool glTilex = glsurf.mTexMax.x == 1.0f;
        bool glTiley = glsurf.mTexMax.y == 1.0f;

        //check if either no tiling is needed, or it can be done entirely by GL
        bool noTileSpecial = (glTilex || destSize.x <= sourceSize.x)
            && (glTiley || destSize.y <= sourceSize.y);

        void simpleDraw(Vector2i sourceP, Vector2i destP, Vector2i destS) {
            Vector2i p1 = destP;
            Vector2i p2 = destP + destS;
            Vector2f t1, t2;

            //select the right part of the texture (in 0.0-1.0 coordinates)
            t1.x = cast(float)sourceP.x / glsurf.mTexSize.x;
            t1.y = cast(float)sourceP.y / glsurf.mTexSize.y;
            t2.x = cast(float)(sourceP.x+destS.x) / glsurf.mTexSize.x;
            t2.y = cast(float)(sourceP.y+destS.y) / glsurf.mTexSize.y;

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

        if (noTileSpecial) {
            //pure OpenGL drawing (and tiling)
            simpleDraw(sourcePos, destPos, destSize);
        } else {
            //manual tiling code, partially using OpenGL tiling if possible
            //xxx sorry for code duplication, but the differences seemed too big
            int w = glTilex?destSize.x:sourceSize.x;
            int h = glTiley?destSize.y:sourceSize.y;
            int x;
            Vector2i tmp;
            Vector2i trans = mStack[mStackTop].translate;
            Vector2i cs_tr = mStack[0].clientsize - trans;

            int y = 0;
            while (y < destSize.y) {
                tmp.y = destPos.y + y;
                int resty = ((y+h) < destSize.y) ? h : destSize.y - y;
                //check visibility (y coordinate)
                if (tmp.y+resty+trans.y > 0 && tmp.y < cs_tr.y) {
                    x = 0;
                    while (x < destSize.x) {
                        tmp.x = destPos.x + x;
                        int restx = ((x+w) < destSize.x) ? w : destSize.x - x;
                        //visibility check for x coordinate
                        if (tmp.x+restx+trans.x > 0 && tmp.x < cs_tr.x)
                            simpleDraw(Vector2i(0, 0), tmp,
                                Vector2i(restx, resty));
                        x += restx;
                    }
                }
                y += resty;
            }
        }

        GLboolean isalpha;
        if (gSDLDriver.mMarkAlpha)
            glGetBooleanv(GL_BLEND, &isalpha);

        glPopAttrib();

        if (isalpha)
            markAlpha(destPos, sourceSize);
    }
}
