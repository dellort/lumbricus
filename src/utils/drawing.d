module utils.drawing;

//copied from sdl_gfx (and modified)
//original: sdlgfx-2.0.9, SDL_gfxPrimitives.c: filledCircleColor()
void circle(int x, int y, int r,
    void delegate(int x1, int x2, int y) cb)
{
    if (r <= 0)
        return;

    int cx = 0, cy = r;
    int ocx = cx-1, ocy = cy+1;
    int df = r - 1;
    int d_e = 3;
    int d_se = -2 * r + 5;

    bool draw = true;

    do {
        if (draw) {
            if (cy > 0) {
                cb(x - cx, x + cx, y + cy);
                cb(x - cx, x + cx, y - cy);
            } else {
                cb(x - cx, x + cx, y);
            }
            draw = false;
        }
        if (cx != cy) {
            if (cx) {
                cb(x - cy, x + cy, y - cx);
                cb(x - cy, x + cy, y + cx);
            } else {
                cb(x - cy, x + cy, y);
            }
        }
        if (df < 0) {
            df += d_e;
            d_e += 2;
            d_se += 2;
        } else {
            df += d_se;
            d_e += 2;
            d_se += 4;
            cy--;
            draw = true;
        }
        cx++;
    } while (cx <= cy);
}
