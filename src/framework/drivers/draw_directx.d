module framework.drivers.draw_directx;

import derelict.directx.d3d9;
import derelict.directx.d3dx9;
import framework.framework;
import framework.drawing;
import tango.sys.win32.Macros;
import tango.sys.win32.Types;
import utils.misc;


const uint D3DFVF_TLVERTEX = D3DFVF_XYZRHW | D3DFVF_DIFFUSE | D3DFVF_TEX1;
struct TLVERTEX {
    Vector2f p;
    float z = 0.0f;      //always 0 for 2D
    float rhw = 1.0f;    //1 to use screen coordinates
    D3DCOLOR color;
    Vector2f t;
}

D3DCOLOR D3DCOLOR_FLOAT(Color c) {
    return D3DCOLOR_COLORVALUE(c.tupleof);
}

class DXDrawDriver : DrawDriver {
    private {
        Vector2i mScreenSize;
        DXCanvas mCanvas;
        D3DPRESENT_PARAMETERS mPresentParams;
    }

    IDirect3D9 d3dObj;
    IDirect3DDevice9 d3dDevice;

    this(ConfigNode config) {
        DerelictD3D9.load();

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
        mPresentParams.BackBufferFormat = D3DFMT_R5G6B5;
        mPresentParams.MultiSampleType = D3DMULTISAMPLE_NONE;

        if (FAILED(d3dObj.CreateDevice(D3DADAPTER_DEFAULT, D3DDEVTYPE_HAL,
           vstate.window_handle, D3DCREATE_SOFTWARE_VERTEXPROCESSING,
           &mPresentParams, &d3dDevice)))
        {
            throw new FrameworkException("Could not create Direct3D Device");
        }

        mCanvas = new DXCanvas(this);
    }

    override Surface screenshot() {
        return null;
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
        DerelictD3D9.unload();
    }

    static this() {
        DrawDriverFactory.register!(typeof(this))("directx");
    }
}

class DXSurface : DriverSurface {
    DXDrawDriver mDrawDriver;
    SurfaceData mData;

    this(DXDrawDriver draw_driver, SurfaceData data) {
        mDrawDriver = draw_driver;
        mData = data;
        assert(data.data !is null);
        //reinit();
    }

    override void getPixelData() {
    }

    override void updatePixels(in Rect2i rc) {
    }

    override void kill() {
    }

    override void getInfos(out char[] desc, out uint extra_data) {
    }
}

class DXCanvas : Canvas {
    private {
        DXDrawDriver mDrawDriver;
        IDirect3DVertexBuffer9 mVertexBuffer;
    }
    IDirect3DDevice9 d3dDevice;

    //created after Direct3D device creation
    this(DXDrawDriver draw_driver) {
        mDrawDriver = draw_driver;
        d3dDevice = mDrawDriver.d3dDevice;

        //Set vertex shader
        d3dDevice.SetVertexShader(null);
        d3dDevice.SetFVF(D3DFVF_TLVERTEX);

        //Create vertex buffer
        d3dDevice.CreateVertexBuffer(TLVERTEX.sizeof * 4, 0,
            D3DFVF_TLVERTEX, D3DPOOL_MANAGED, &mVertexBuffer, null);
        d3dDevice.SetStreamSource(0, mVertexBuffer, 0, TLVERTEX.sizeof);
    }

    override int features() {
        return mDrawDriver.getFeatures();
    }

    void startScreenRendering() {
        d3dDevice.SetRenderState(D3DRS_LIGHTING, FALSE);
        d3dDevice.SetRenderState(D3DRS_ALPHABLENDENABLE, TRUE);
        d3dDevice.SetRenderState(D3DRS_SRCBLEND, D3DBLEND_SRCALPHA);
        d3dDevice.SetRenderState(D3DRS_DESTBLEND, D3DBLEND_INVSRCALPHA);
        d3dDevice.SetTextureStageState(0, D3DTSS_ALPHAOP, D3DTOP_MODULATE);

        clear(Color(0,0,0));
        d3dDevice.BeginScene();
        startDraw();
    }

    void stopScreenRendering() {
        endDraw();
        d3dDevice.EndScene();
        d3dDevice.Present(null, null, null, null);
    }

    package void startDraw() {
    }

    override void endDraw() {
    }

    override Vector2i realSize() {
        return Vector2i(0);
    }
    override Vector2i clientSize() {
        return Vector2i(0);
    }

    override Rect2i parentArea() {
        return Rect2i(0, 0, 0, 0);
    }

    override Rect2i visibleArea() {
        return Rect2i(0, 0, 0, 0);
    }

    override void draw(Texture source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize, bool mirrorY = false) {
    }

    override void drawCircle(Vector2i center, int radius, Color color) {
    }
    override void drawFilledCircle(Vector2i center, int radius,
        Color color) {
    }

    override void drawLine(Vector2i p1, Vector2i p2, Color color,
        int width = 1) {
    }

    override void drawRect(Vector2i p1, Vector2i p2, Color color) {
    }
    override void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
    }
    override void drawVGradient(Rect2i rc, Color c1, Color c2) {
    }

    override void drawPercentRect(Vector2i p1, Vector2i p2, float perc,
        Color c) {
    }

    override void clear(Color color) {
        d3dDevice.Clear(0, null, D3DCLEAR_TARGET | D3DCLEAR_ZBUFFER,
            D3DCOLOR_FLOAT(color), 1.0f, 0);
    }

    override void setWindow(Vector2i p1, Vector2i p2) {
    }
    override void translate(Vector2i offset) {
    }
    override void clip(Vector2i p1, Vector2i p2) {
    }
    override void setScale(Vector2f sc) {
    }

    override void pushState() {
    }
    override void popState() {
    }

    override void drawQuad(Surface tex, Vertex2i[4] quad) {
    }
}
