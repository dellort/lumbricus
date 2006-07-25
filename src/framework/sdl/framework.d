module framework.sdl.framework;

import framework.framework;
import std.stream;
import std.stdio;
import std.string;
import utils.vector2;
import framework.sdl.rwops;
import derelict.sdl.sdl;
import derelict.sdl.image;
import derelict.sdl.ttf;
import framework.sdl.keys;

private static Framework gFrameworkSDL;

public class SDLSurface : Surface {
    SDL_Surface* sdlsurface;

    public int width() {
        return sdlsurface.w;
    }
    public int height() {
        return sdlsurface.h;
    }

    this(SDL_Surface* surface) {
        this.sdlsurface = surface;
    }
}

public class SDLImage : Image {
    SDLSurface sdlsurface;

    public Surface surface() {
        return sdlsurface;
    }

    static SDLImage load(Stream st) {
        SDL_RWops* ops = rwopsFromStream(st);
        SDL_Surface* surf;
        surf = IMG_Load_RW(ops, 0);
        if (surf != null) {
            return new SDLImage(new SDLSurface(surf));
        } else {
            return null;
        }
    }

    this(SDLSurface surface) {
        this.sdlsurface = surface;
    }
}

public class SDLCanvas : Canvas {
    SDLSurface sdlsurface;

    this() {
        sdlsurface = new SDLSurface(null);
    }

    public Surface surface() {
        return sdlsurface;
    }

    public void draw(Surface source, Vector2i destPos,
        Vector2i sourcePos, Vector2i sourceSize)
    {
        SDLSurface sdls = cast(SDLSurface)source;
        SDL_Rect rc, destrc;
        rc.x = cast(short)sourcePos.x;
        rc.y = cast(short)sourcePos.y;
        rc.w = cast(ushort)sourceSize.x;
        rc.h = cast(ushort)sourceSize.y;
        destrc.x = cast(short)destPos.x;
        destrc.y = cast(short)destPos.y; //destrc.w/h ignored by SDL_BlitSurface
        SDL_BlitSurface(sdls.sdlsurface, &rc, sdlsurface.sdlsurface, &destrc);
    }

    //TODO: add code
    public void drawCircle(Vector2i center, int radius, Color color) {
    }

    public void drawFilledCircle(Vector2i center, int radius,
        Color color)
    {
    }

    public void drawLine(Vector2i p1, Vector2i p2, Color color) {
    }

    public void drawRect(Vector2i p1, Vector2i p2, Color color) {
    }

    public void drawFilledRect(Vector2i p1, Vector2i p2, Color color) {
    }

    public void drawText(char[] text) {

    }
}

public class SDLFont : Font {
    private Surface frags[dchar];
    private FontProperties props;
    private TTF_Font* font;
    // Stream is used by TTF_Font, this keeps the reference to it
    private MemoryStream font_stream;

    this(Stream str, FontProperties props) {
        font_stream = new MemoryStream();
        str.seek(0,SeekPos.Set);
        font_stream.copyFrom(str);
        font_stream.seek(0,SeekPos.Set);
        this.props = props;
        SDL_RWops* rwops;
        rwops = rwopsFromStream(font_stream);
        font = TTF_OpenFontRW(rwops, 1, props.size);
        if (font == null) {
            throw new Exception("Could not load font.");
        }
    }

    ~this() {
        TTF_CloseFont(font);
    }

    public void drawText(Canvas canvas, Vector2i pos, char[] text) {
        Surface surface;
        foreach (dchar c; text) {
            if (!(c in frags)) {
                frags[c] = renderChar(c);
            }
            surface = frags[c];
            canvas.draw(surface, pos);
            pos.x += surface.width;
        }
    }

    private Surface renderChar(dchar c) {
        dchar s[2];
        s[0] = c;
        s[1] = '\0';
        //TODO: foreground and background color
        SDL_Color col;
        col.r = 255;
        SDL_Surface* surface = TTF_RenderUNICODE_Blended(font,
            cast(ushort*)s.ptr, col);
        if (surface == null) {
            throw new Exception(format("could not render char %s", c));
        }
        return new SDLSurface(surface);
    }
}

public class FrameworkSDL : Framework {
    SDL_Surface* mScreen;
    SDLCanvas mScreenCanvas;
    Keycode mSdlToKeycode[int];

    this() {
        if (gFrameworkSDL !is null) {
            throw new Exception("FrameworkSDL is a singleton, sorry.");
        }

        gFrameworkSDL = this;

        DerelictSDL.load();
        DerelictSDLImage.load();
        DerelictSDLttf.load();

        if (SDL_Init(SDL_INIT_VIDEO) < 0) {
            throw new Exception(format("Could not init SDL: %s",
                std.string.toString(SDL_GetError())));
        }

        SDL_EnableUNICODE(1);
        SDL_EnableKeyRepeat(SDL_DEFAULT_REPEAT_DELAY,
            SDL_DEFAULT_REPEAT_INTERVAL);

        if (TTF_Init()==-1) {
            throw new Exception(format("TTF_Init: %s\n",
                std.string.toString(TTF_GetError())));
        }

        mScreenCanvas = new SDLCanvas();

        //Initialize translation hashmap from array
        foreach (SDLToKeycode item; g_sdl_to_code) {
            mSdlToKeycode[item.sdlcode] = item.code;
        }
        
        setCaption("<no caption>");
    }
    
    public void setCaption(char[] caption) {
        caption = caption ~ '\0';
        //second arg is the "icon name", the docs don't tell its meaning
        SDL_WM_SetCaption(caption.ptr, null);
    }

    public void setVideoMode(int widthX, int widthY, int bpp,
        bool fullscreen)
    {
        SDL_Surface* newscreen;

        newscreen = SDL_SetVideoMode(widthX, widthY, bpp,
            SDL_HWSURFACE | SDL_DOUBLEBUF);

        if(newscreen is null) {
            throw new Exception(format("Unable to set %dx%dx%d video mode: %s",
                widthX, widthY, bpp, std.string.toString(SDL_GetError())));
        }

        mScreen = newscreen;
        //TODO: Software backbuffer
        mScreenCanvas.sdlsurface.sdlsurface = mScreen;
    }

    public bool getModifierState(Modifier mod) {
	//special handling for the shift- and numlock-modifiers
	//since the user might toggle numlock or capslock while we don't have
	//the keyboard-focus, ask the SDL (which inturn asks the OS)
	SDLMod modstate = SDL_GetModState();
	//writefln("state=%s", modstate);
	if (mod == Modifier.Shift) {
	    //xxx behaviour when caps and shift are both on is maybe OS
	    //dependend; on X11, both states are usually XORed
	    return ((modstate & KMOD_CAPS) != 0) ^ super.getModifierState(mod);
	} else if (mod == Modifier.Numlock) {
	    return (modstate & KMOD_NUM) != 0;
	} else {
	    //generic handling for non-toggle modifiers
	    return super.getModifierState(mod);
	}
    }

    private Keycode sdlToKeycode(int sdl_sym) {
        if (sdl_sym in mSdlToKeycode) {
            return mSdlToKeycode[sdl_sym];
        } else {
            return Keycode.INVALID; //sorry
        }
    }

    public Image loadImage(Stream st) {
        return SDLImage.load(st);
    }

    public Font loadFont(Stream str, FontProperties fontProps) {
        return new SDLFont(str,fontProps);
    }

    public Canvas screen() {
        return mScreenCanvas;
    }

    public void run() {
        while(!shouldTerminate) {
            // process events
            input();

            // draw to the screen
            render();

            //TODO: Software backbuffer
            SDL_Flip(mScreen);

            // yield the rest of the timeslice
            SDL_Delay(0);
        }
    }

    private KeyInfo keyInfosFromSDL(in SDL_KeyboardEvent sdl) {
        KeyInfo infos;
        infos.code = sdlToKeycode(sdl.keysym.sym);
        infos.unicode = sdl.keysym.unicode;
        return infos;
    }

    private KeyInfo mouseInfosFromSDL(in SDL_MouseButtonEvent mouse) {
        KeyInfo infos;
        infos.code = sdlToKeycode(g_sdl_mouse_button1 + (mouse.button - 1));
        return infos;
    }

    private void input() {
        SDL_Event event;
        while(SDL_PollEvent(&event)) {
            switch(event.type) {
                // exit if SDLK or the window close button are pressed
                case SDL_KEYDOWN:
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    doKeyDown(infos);
                    break;
                case SDL_KEYUP:
                    //xxx TODO: SDL provides no unicode translation for KEYUP
                    KeyInfo infos = keyInfosFromSDL(event.key);
                    doKeyUp(infos);
                    break;
                case SDL_MOUSEMOTION:
                    //update mouse pos after button state
                    doUpdateMousePos(Vector2i(event.motion.x, event.motion.y));
                    break;
                case SDL_MOUSEBUTTONUP:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    doKeyUp(infos);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
                    break;
                case SDL_MOUSEBUTTONDOWN:
                    KeyInfo infos = mouseInfosFromSDL(event.button);
                    doKeyDown(infos);
                    doUpdateMousePos(Vector2i(event.button.x, event.button.y));
                    break;
                case SDL_QUIT:
                    doTerminate();
                    break;
                default:
            }
        }
    }

    private void render() {
        if (onFrame) {
                onFrame();
        }
    }
}
