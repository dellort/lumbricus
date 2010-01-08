module framework.drivers.draw_directx;

import derelict.directx.d3d9;
import derelict.directx.d3dx9;
import framework.framework;
import framework.drawing;
import tango.sys.win32.Macros;
import tango.sys.win32.Types;
import utils.misc;
import utils.transform;


const uint D3DFVF_TLVERTEX = D3DFVF_XYZ | D3DFVF_DIFFUSE | D3DFVF_TEX1;
struct TLVERTEX {
    Vector2f p;
    float z = 0.0f;      //always 0 for 2D
    D3DCOLOR color;
    Vector2f t;

    static TLVERTEX opCall(Vector2i p, Color col, Vector2f t) {
        TLVERTEX ret;
        ret.p = toVector2f(p);
        ret.color = D3DCOLOR_FLOAT(col);
        ret.t = t;
        return ret;
    }

    static TLVERTEX opCall(Vector2i p, Vector2f t) {
        return opCall(p, Color(1), t);
    }
}

D3DCOLOR D3DCOLOR_FLOAT(Color c) {
    return D3DCOLOR_COLORVALUE(c.tupleof);
}

void checkDX(HRESULT res, char[] msg) {
    if (FAILED(res)) {
        throw new FrameworkException("D3D: "~msg~" failed.");
    }
}

private struct Options {
    bool vsync = false;
}

class DXDrawDriver : DrawDriver {
    private {
        Vector2i mScreenSize;
        DXCanvas mCanvas;
        D3DPRESENT_PARAMETERS mPresentParams;
        bool mVsync;
    }

    IDirect3D9 d3dObj;
    IDirect3DDevice9 d3dDevice;

    this() {
        auto opts = driverOptions(this).getval!(Options);
        mVsync = opts.vsync;

        DerelictD3D9.load();
        DerelictD3DX9.load();

        d3dObj = Direct3DCreate9(D3D_SDK_VERSION);
        if (d3dObj is null)
            throw new FrameworkException("Could not create Direct3D Object");
    }

    override DriverSurface createSurface(SurfaceData data) {
        return new DXSurface(this, data);
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
        auto vstate = gFramework.driver.getVideoWindowState();

        mPresentParams.Windowed = !vstate.fullscreen;
        mPresentParams.SwapEffect = D3DSWAPEFFECT_DISCARD;
        mPresentParams.EnableAutoDepthStencil = true;
        mPresentParams.AutoDepthStencilFormat = D3DFMT_D16;
        mPresentParams.hDeviceWindow = vstate.window_handle;
        mPresentParams.BackBufferWidth = mScreenSize.x;
        mPresentParams.BackBufferHeight = mScreenSize.y;
        mPresentParams.BackBufferFormat = D3DFMT_X8R8G8B8;
        mPresentParams.MultiSampleType = D3DMULTISAMPLE_NONE;
        mPresentParams.PresentationInterval =
            mVsync ? D3DPRESENT_INTERVAL_ONE : D3DPRESENT_INTERVAL_IMMEDIATE;

        if (FAILED(d3dObj.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL,
           vstate.window_handle, D3DCREATE_SOFTWARE_VERTEXPROCESSING
           | D3DCREATE_FPU_PRESERVE, &mPresentParams, &d3dDevice)))
        {
            throw new FrameworkException("Could not create Direct3D Device");
        }

        mCanvas = new DXCanvas(this);
    }

    override Surface screenshot() {
        //xxx stupid Direct3D can only capture the whole screen (with desktop)
        //    in windowed mode
        //another approach is to copy the _backbuffer_ before it is flipped and
        //discarded with the Present() call, but I'm too lazy for that
        D3DDISPLAYMODE displayMode;
        d3dDevice.GetDisplayMode(0, &displayMode);

        Surface res = new Surface(
            Vector2i(displayMode.Width, displayMode.Height), Transparency.None);
        Color.RGBA32* pDest;
        uint pitch;
        res.lockPixelsRGBA32(pDest, pitch);
        assert(pitch == res.size.x);

        IDirect3DSurface9 tmpSurf;
        d3dDevice.CreateOffscreenPlainSurface(displayMode.Width,
            displayMode.Height, D3DFMT_A8R8G8B8, D3DPOOL_SYSTEMMEM, &tmpSurf,
            null);
        assert(!!tmpSurf);
        checkDX(d3dDevice.GetFrontBufferData(0, tmpSurf),
            "d3dDevice.CreateOffscreenPlainSurface");

        D3DLOCKED_RECT lrc;
        checkDX(tmpSurf.LockRect(&lrc, null, D3DLOCK_READONLY),
            "tmpSurf.LockRect");
        assert(lrc.Pitch == res.size.x*4);
        Color.RGBA32* pSrc = cast(Color.RGBA32*)lrc.pBits;
        for (int i = 0; i < res.size.x*res.size.y; i++) {
            pDest.r = pSrc.b;
            pDest.g = pSrc.g;
            pDest.b = pSrc.r;
            pDest.a = pSrc.a;
            pDest++;
            pSrc++;
        }
        tmpSurf.UnlockRect();

        res.unlockPixels(res.rect());
        tmpSurf.Release();
        tmpSurf = null;
        return res;
    }

    override int getFeatures() {
        return DriverFeatures.canvasScaling | DriverFeatures.transformedQuads;
    }

    override void destroy() {
        if (d3dDevice) {
            d3dDevice.Release();
            d3dDevice = null;
        }
        d3dObj.Release();
        d3dObj = null;
        DerelictD3DX9.unload();
        DerelictD3D9.unload();
    }

    static this() {
        auto opts = registerFrameworkDriver!(typeof(this))("directx");
        opts.addMembers!(Options)();
    }
}

class DXSurface : DriverSurface {
    DXDrawDriver mDrawDriver;
    SurfaceData mData;
    IDirect3DTexture9 mTex;

    this(DXDrawDriver draw_driver, SurfaceData data) {
        mDrawDriver = draw_driver;
        mData = data;
        assert(data.data !is null);
        //reinit();
        if (data.size.quad_length == 0)
            return;
        mDrawDriver.d3dDevice.CreateTexture(mData.size.x, mData.size.y, 1,
            D3DUSAGE_DYNAMIC, D3DFMT_A8R8G8B8, D3DPOOL_DEFAULT, &mTex, null);
        assert(!!mTex);
        updatePixels(Rect2i(mData.size));
    }

    override void getPixelData() {
    }

    override void updatePixels(in Rect2i rc) {
        rc.fitInsideB(Rect2i(mData.size));
        if (rc.size.x < 0 || rc.size.y < 0)
            return;
        RECT rc2;
        rc2.left = rc.p1.x;
        rc2.top = rc.p1.y;
        rc2.right = rc.p2.x;
        rc2.bottom = rc.p2.y;
        D3DLOCKED_RECT lrc;
        checkDX(mTex.LockRect(0, &lrc, &rc2, 0), "texture.LockRect");
        for (int y = 0; y < rc.p2.y - rc.p1.y; y++) {
            Color.RGBA32* psrc = &mData.data[(y+rc.p1.y)*mData.pitch + rc.p1.x];
            Color.RGBA32* pdest = cast(Color.RGBA32*)(lrc.pBits + lrc.Pitch * y);
            size_t s = rc.size.x;
            for (int i = 0; i < s; i++) {
                //internal RGBA32 -> Direct3d A8R8G8B8
                pdest.r = psrc.b;
                pdest.g = psrc.g;
                pdest.b = psrc.r;
                pdest.a = psrc.a;
                pdest++;
                psrc++;
            }
            //pdest[0..s] = psrc[0..s];
        }
        mTex.UnlockRect(0);
    }

    override void destroy() {
        if (mTex)
            mTex.Release();
        mTex = null;
    }

    override void getInfos(out char[] desc, out uint extra_data) {
    }
}

class DXCanvas : Canvas3DHelper {
    private {
        const cMaxVertices = 100;
        DXDrawDriver mDrawDriver;
        IDirect3DVertexBuffer9 mDXVertexBuffer;
        TLVERTEX[cMaxVertices] mVertexBuffer;
        D3DMATRIX mStdTransform;
    }
    IDirect3DDevice9 d3dDevice;

    //created after Direct3D device creation
    this(DXDrawDriver draw_driver) {
        mDrawDriver = draw_driver;
        d3dDevice = mDrawDriver.d3dDevice;

        d3dDevice.SetSamplerState(0, D3DSAMP_MAGFILTER, D3DTEXF_LINEAR);
        d3dDevice.SetSamplerState(0, D3DSAMP_MINFILTER, D3DTEXF_LINEAR);

        //Set vertex shader
        d3dDevice.SetVertexShader(null);
        d3dDevice.SetFVF(D3DFVF_TLVERTEX);

        //Create vertex buffer
        d3dDevice.CreateVertexBuffer(TLVERTEX.sizeof * 4,
            D3DUSAGE_DYNAMIC | D3DUSAGE_WRITEONLY,
            D3DFVF_TLVERTEX, D3DPOOL_DEFAULT, &mDXVertexBuffer, null);
        d3dDevice.SetStreamSource(0, mDXVertexBuffer, 0, TLVERTEX.sizeof);

        D3DMATRIX projMatrix;
        D3DXMatrixOrthoOffCenterLH(&projMatrix, 0.5f, mDrawDriver.mScreenSize.x + 0.5f,
            mDrawDriver.mScreenSize.y + 0.5f, 0.5f, 0, 128);
        d3dDevice.SetTransform(D3DTS_PROJECTION, &projMatrix);
        D3DMATRIX viewMatrix;
        D3DXMatrixIdentity(&viewMatrix);
        d3dDevice.SetTransform(D3DTS_VIEW, &viewMatrix);
    }

    override int features() {
        return mDrawDriver.getFeatures();
    }

    package void startScreenRendering() {
        d3dDevice.SetRenderState(D3DRS_LIGHTING, FALSE);
        d3dDevice.SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
        d3dDevice.SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        d3dDevice.SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        d3dDevice.SetRenderState(D3DRS_CULLMODE, D3DCULL_NONE);
        d3dDevice.SetRenderState(D3DRS_ANTIALIASEDLINEENABLE, TRUE);
        d3dDevice.SetRenderState(D3DRS_ZENABLE, FALSE);
        d3dDevice.SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_MODULATE);

        d3dDevice.BeginScene();
        initFrame(mDrawDriver.mScreenSize);
    }

    package void stopScreenRendering() {
        uninitFrame();
        d3dDevice.EndScene();
        d3dDevice.Present(null, null, null, null);
    }

    override void updateTransform(Vector2i trans, Vector2f scale) {
        D3DMATRIX s, t;
        D3DXMatrixTranslation(&t, trans.x, trans.y, 0);
        D3DXMatrixScaling(&s, scale.x, scale.y, 1.0f);
        D3DXMatrixMultiply(&mStdTransform, &s, &t);
        d3dDevice.SetTransform(D3DTS_WORLD, &mStdTransform);
    }

    override void updateClip(Vector2i p1, Vector2i p2) {
        //scissor stuff, p1 and p2 are already in screen coords
        d3dDevice.SetRenderState(D3DRS_SCISSORTESTENABLE, TRUE);
        RECT sr;
        sr.left = p1.x;
        sr.top = p1.y;
        sr.right = p2.x;
        sr.bottom = p2.y;
        d3dDevice.SetScissorRect(&sr);
    }

    override void clear(Color color) {
        //the Clear() call respects the current scissor rect
        d3dDevice.Clear(0, null, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
            D3DCOLOR_FLOAT(color), 1.0f, 0);
    }

    override void drawSprite(SubSurface source, Vector2i destPos,
        BitmapEffect* effect = null)
    {
        if (!spriteVisible(source, destPos, effect))
            return;

        if (!effect)
            effect = &BitmapEffect.init;

        Transform2f tr = effect.getTransform(source.size, destPos);

        doDraw(source.surface, Vector2i(0), source.origin, source.size,
            &tr, effect.color);
    }

    override void draw(Texture source, Vector2i destPos, Vector2i sourcePos,
        Vector2i sourceSize)
    {
        if (!visibleArea.intersects(destPos, destPos + sourceSize))
            return;

        doDraw(source, destPos, sourcePos, sourceSize);
    }

    private void doDraw(Surface source, Vector2i destPos, Vector2i sourcePos,
        Vector2i sourceSize, Transform2f* tr = null, Color col = Color(1.0f))
    {
        auto tex = cast(DXSurface)source.getDriverSurface();
        Vector2i p1 = destPos;
        Vector2i p2 = destPos + sourceSize;
        Vector2f t1, t2;

        //select the right part of the texture (in 0.0-1.0 coordinates)
        t1.x = cast(float)sourcePos.x / tex.mData.size.x;
        t1.y = cast(float)sourcePos.y / tex.mData.size.y;
        t2.x = cast(float)(sourcePos.x+sourceSize.x) / tex.mData.size.x;
        t2.y = cast(float)(sourcePos.y+sourceSize.y) / tex.mData.size.y;

        //TLVERTEX* buf;
        //mDXVertexBuffer.Lock(0, 0, cast(void**)&buf, D3DLOCK_DISCARD);
        //clockwise rotation, 2nd tri is auto-inverted
        mVertexBuffer[0] = TLVERTEX(Vector2i(p1.x, p2.y), col,
            Vector2f(t1.x, t2.y));
        mVertexBuffer[1] = TLVERTEX(Vector2i(p1.x, p1.y), col,
            Vector2f(t1.x, t1.y));
        mVertexBuffer[2] = TLVERTEX(Vector2i(p2.x, p2.y), col,
            Vector2f(t2.x, t2.y));
        mVertexBuffer[3] = TLVERTEX(Vector2i(p2.x, p1.y), col,
            Vector2f(t2.x, t1.y));

        if (tr) {
            //you also could construct a 4D matrix out of tr, and do
            //  glPushMatrix; glMultMatrixf; glPopMatrix
            //but it would be slower
            foreach (ref v; mVertexBuffer) {
                v.p = tr.transform(v.p);
            }
        }

        //mDXVertexBuffer.Unlock();

        d3dDevice.SetTexture(0, tex.mTex);
        //d3dDevice.DrawPrimitive(D3DPT_TRIANGLESTRIP, 0, 2);
        d3dDevice.DrawPrimitiveUP(D3DPT_TRIANGLESTRIP, 2, mVertexBuffer.ptr,
            TLVERTEX.sizeof);
    }

    private static const D3DPRIMITIVETYPE[] cPrimMap = [
        Primitive.LINES : D3DPT_LINELIST,
        Primitive.LINE_STRIP : D3DPT_LINESTRIP,
        Primitive.LINE_LOOP : D3DPT_LINESTRIP,
        Primitive.TRIS : D3DPT_TRIANGLELIST,
        Primitive.TRI_STRIP : D3DPT_TRIANGLESTRIP,
        Primitive.TRI_FAN : D3DPT_TRIANGLEFAN,
        Primitive.QUADS : D3DPT_TRIANGLESTRIP,
    ];

    override void draw_verts(Primitive primitive, Surface tex, Vertex2f[] verts)
    {
        assert(verts.length <= cMaxVertices);

        DXSurface dxsurf = tex ? cast(DXSurface)tex.getDriverSurface() : null;
        Vector2f ts;
        if (dxsurf) {
            ts = Vector2f(1.0f/dxsurf.mData.size.x, 1.0f/dxsurf.mData.size.y);
            d3dDevice.SetTexture(0, dxsurf.mTex);
        } else {
            ts = Vector2f(1.0f);
            d3dDevice.SetTexture(0, null);
        }

        foreach (int idx, ref cv; verts) {
            mVertexBuffer[idx].p = cv.p;
            mVertexBuffer[idx].color = D3DCOLOR_FLOAT(cv.c);
            mVertexBuffer[idx].t = toVector2f(cv.t) ^ ts;
        }

        int primCount;
        switch (primitive) {
            case Primitive.LINES: primCount = verts.length / 2; break;
            case Primitive.LINE_STRIP: primCount = verts.length - 1; break;
            case Primitive.LINE_LOOP:
                //1 extra vertex
                assert(verts.length < cMaxVertices);
                primCount = verts.length;
                mVertexBuffer[verts.length] = mVertexBuffer[0];
                break;
            case Primitive.TRIS: primCount = verts.length / 3; break;
            case Primitive.TRI_STRIP: primCount = verts.length - 2; break;
            case Primitive.TRI_FAN: primCount = verts.length - 2; break;
            case Primitive.QUADS:
                //quads are rendered as TRI_STRIP, more than 1 quad would
                //require multiple DrawPrimitive calls
                assert(verts.length == 4, "Implement me");
                primCount = 2;
                //2 tris, first rotated clockwise
                swap(mVertexBuffer[0], mVertexBuffer[1]);
                break;
        }
        d3dDevice.DrawPrimitiveUP(cPrimMap[primitive], primCount,
            mVertexBuffer.ptr, TLVERTEX.sizeof);
    }
}
