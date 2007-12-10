//contains the OpenGL
module framework.sdl.fwgl;

import derelict.opengl.gl;
import derelict.opengl.glu;
import derelict.sdl.sdl;
import framework.framework;
import framework.sdl.framework;
import framework.drawing;
import std.math;
import utils.misc;

debug import std.stdio;

class GLSurface : DriverSurface {
    const GLuint TEXID_INVALID = 0;

    SurfaceData* mData;
    GLuint mTexId;
    Vector2f mTexMax;
    Vector2i mTexSize;

    //create from Framework's data
    this(SurfaceData* data) {
        mData = data;
        reinit();
    }

    void releaseSurface() {
        if (mTexId != TEXID_INVALID) {
            glDeleteTextures(1, &mTexId);
            mTexId = TEXID_INVALID;
        }
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

        void* texData;
        uint texPitch;
        SDL_Surface *texSurface;
        if (mTexSize!=mData.size || mData.transparency!=Transparency.Alpha) {
            //size does not fit, or transparency uses colorkeying -> convert
            SDL_Surface *srcSurface = SDL_CreateRGBSurfaceFrom(mData.data.ptr,
                mData.size.x, mData.size.y, 32, mData.pitch, 0x000000FF,
                0x0000FF00, 0x00FF0000, 0xFF000000);
            assert(srcSurface);

            texSurface = SDL_CreateRGBSurface(SDL_SWSURFACE, mTexSize.x,
                mTexSize.y, 32, 0x000000FF, 0x0000FF00, 0x00FF0000, 0xFF000000);
            assert(texSurface);

            //clear transparency - I don't know why, the surface has just been
            //created and should not have any
            SDL_SetAlpha(srcSurface, 0, 0);
            switch (mData.transparency) {
                case Transparency.Alpha: {
                    //no transparency handling for alpha surfaces, copy 1:1
                    break;
                }
                case Transparency.Colorkey: {
                    //activate colorkeying for source surface
                    uint key = simpleColorToSDLColor(srcSurface,
                        mData.colorkey);
                    SDL_SetColorKey(srcSurface, SDL_SRCCOLORKEY, key);
                    break;
                }
                default: //rien
            }

            //Copy the surface into the GL texture image
            //Blitting converts colorkey images to alpha images, because only
            //non-transparent pixels are overwritten
            SDL_Rect area;
            area.x = 0;
            area.y = 0;
            area.w = mData.size.x;
            area.h = mData.size.y;
            SDL_BlitSurface(srcSurface, &area, texSurface, &area);
            SDL_FreeSurface(srcSurface);

            texData = texSurface.pixels;
            texPitch = texSurface.pitch;
            //xxx OpenGL does not have a pitch value and data should be
            //4-byte-aligned anyway
            assert(texPitch == texSurface.w*4);
        } else {
            //transparency format and alpha match -> use directly
            texData = mData.data.ptr;
            texPitch = mData.pitch;
            assert(texPitch == mData.size.x*4);
        }

        //generate texture and set parameters
        glGenTextures(1, &mTexId);
        glBindTexture(GL_TEXTURE_2D, mTexId);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
        //glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);

        //glPixelStorei(GL_UNPACK_ROW_LENGTH, texPitch);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, mTexSize.x, mTexSize.y, 0,
            GL_RGBA, GL_UNSIGNED_BYTE, texData);
        GLenum err = glGetError();
        if (err != GL_NO_ERROR) {
            debug writefln("Failed to create texture of size %s",mTexSize);
            //throw new Exception(
            //    "glTexImage2D failed, probably texture was too big. "
            //    ~ "Requested size: "~mTexSize.toString);

            //create a red replacement texture so the error is well-visible
            uint red = 0xff0000ff;
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0,
                GL_RGBA, GL_UNSIGNED_BYTE, &red);
        }
        //glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
        if (texSurface)
            SDL_FreeSurface(texSurface);
    }

    void getPixelData() {
        //nop, nothing free'd for now
    }

    void updatePixels(in Rect2i rc) {
        if (mTexId == TEXID_INVALID) {
            reinit();
        } else {
            assert(mData.pitch == mData.size.x*4);
            assert(rc.p1.x <= mData.size.x && rc.p1.y <= mData.size.y);
            assert(rc.p2.x <= mData.size.x && rc.p2.y <= mData.size.y);
            glBindTexture(GL_TEXTURE_2D, mTexId);
            //make GL read the right data from the full-image array
            glPixelStorei(GL_UNPACK_ROW_LENGTH, mData.pitch/4);
            glPixelStorei(GL_UNPACK_SKIP_ROWS, rc.p1.y);
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, rc.p1.x);
            //xxx what about colorkey? currently draws ugly pink rectangles
            glTexSubImage2D(GL_TEXTURE_2D, 0, rc.p1.x, rc.p1.y, rc.size.x,
                rc.size.y, GL_RGBA, GL_UNSIGNED_BYTE, mData.data.ptr);
            //reset unpack values
            glPixelStorei(GL_UNPACK_ROW_LENGTH, 0);
            glPixelStorei(GL_UNPACK_SKIP_ROWS, 0);
            glPixelStorei(GL_UNPACK_SKIP_PIXELS, 0);
        }
    }
}

class GLCanvas : Canvas {
    const int MAX_STACK = 20;

    private {
        struct State {
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

        initGLViewport();

        gSDLDriver.mClearTime.start();
        auto clearColor = Color(0,0,0);
        clear(clearColor);
        gSDLDriver.mClearTime.stop();

        startDraw();
    }

    void stopScreenRendering() {
        endDraw();

        //TODO: Software backbuffer (or not... not needed with X11/windib)
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
        glOrtho(0, mStack[0].clientsize.x, mStack[0].clientsize.y, 0, 0, 128);

        glMatrixMode(GL_MODELVIEW);
        glLoadIdentity();

        glDisable(GL_SCISSOR_TEST);
        glEnable(GL_LINE_SMOOTH);
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
        glEnable(GL_SCISSOR_TEST);
        glScissor(p1.x, realSize.y-p2.y, p2.x-p1.x, p2.y-p1.y);
    }

    public void pushState() {
        assert(mStackTop < MAX_STACK);

        glPushAttrib(GL_SCISSOR_BIT);
        glPushMatrix();
        mStack[mStackTop+1] = mStack[mStackTop];
        mStackTop++;
    }
    public void popState() {
        assert(mStackTop > 0);

        glPopMatrix();
        glPopAttrib();
        mStackTop--;
        if (glIsEnabled(GL_SCISSOR_TEST))
            doClip(mStack[mStackTop].clip.p1, mStack[mStackTop].clip.p2);
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
        glColor4fv(cast(float*)&color);
        stroke_circle(center.x, center.y, radius);
    }

    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
        glColor4fv(cast(float*)&color);
        fill_circle(center.x, center.y, radius);
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
        glPushAttrib(GL_ENABLE_BIT);
        glDisable(GL_TEXTURE_2D);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(cast(float*)&color);

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
        glPushMatrix();
        glPushAttrib(GL_ENABLE_BIT);
        glDisable(GL_TEXTURE_2D);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glColor4fv(cast(float*)&color);

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

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color,
        bool properalpha = true)
    {
        glPushMatrix();
        glPushAttrib(GL_ENABLE_BIT);
        glDisable(GL_TEXTURE_2D);
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        //har
        glColor4fv(cast(float*)&color);

        //glTranslatef(0.5f, 0.5f, 0);
        glBegin(GL_QUADS);
            glVertex2i(p1.x, p1.y);
            glVertex2i(p1.x, p2.y);
            glVertex2i(p2.x, p2.y);
            glVertex2i(p2.x, p1.y);
        glEnd();

        glPopAttrib();
        glPopMatrix();
    }

    public void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        drawTextureInt(source, sourcePos, sourceSize, destPos, sourceSize);
    }

    public void drawTiled(Texture source, Vector2i destPos, Vector2i destSize) {
        drawTextureInt(source, Vector2i(0,0), source.size, destPos, destSize);
    }

    //this will draw the texture source tiled in the destination area
    //tiling is completely untested, and it is unknown if tiling works
    //if sourcePos/sourceSize don't match texture size
    private void drawTextureInt(Texture source, Vector2i sourcePos,
        Vector2i sourceSize, Vector2i destPos, Vector2i destSize)
    {
        if (gSDLDriver.glWireframeDebug) {
            //wireframe mode
            drawRect(destPos, destPos+sourceSize, Color(1,1,1));
            drawLine(destPos, destPos+sourceSize, Color(1,1,1));
            return;
        }

        assert(source !is null);
        GLSurface glsurf = cast(GLSurface)(source.getDriverSurface(
            SurfaceMode.NORMAL));
        assert(glsurf !is null);

        glPushAttrib(GL_ENABLE_BIT);

        glEnable(GL_TEXTURE_2D);
        glDisable(GL_DEPTH_TEST);

        //activate blending for proper alpha display
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

        glBindTexture(GL_TEXTURE_2D, glsurf.mTexId);

        Vector2i p1 = destPos;
        Vector2i p2 = destPos + destSize;
        //select the right part of the texture (in 0.0-1.0 texture coordinates)
        Vector2f t1, t2;
        t1.x = cast(float)sourcePos.x / glsurf.mTexSize.x;
        t1.y = cast(float)sourcePos.y / glsurf.mTexSize.y;
        t2.x = cast(float)(sourcePos.x+sourceSize.x) / glsurf.mTexSize.x;
        t2.y = cast(float)(sourcePos.y+sourceSize.y) / glsurf.mTexSize.y;

        glColor4f(1.0f, 1.0f, 1.0f, 1.0f);

        //draw textured rect
        glBegin(GL_QUADS);
        glTexCoord2f(t1.x, t1.y); glVertex2i(p1.x, p1.y);
        glTexCoord2f(t1.x, t2.y); glVertex2i(p1.x, p2.y);
        glTexCoord2f(t2.x, t2.y); glVertex2i(p2.x, p2.y);
        glTexCoord2f(t2.x, t1.y); glVertex2i(p2.x, p1.y);
        glEnd();

        glPopAttrib();
    }
}
