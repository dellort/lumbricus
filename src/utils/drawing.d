module utils.drawing;

//from http://en.wikipedia.org/wiki/Midpoint_circle_algorithm
//(modified for filling)
void circle(int x, int y, int r,
    void delegate(int x1, int x2, int y) cb)
{
    if (r <= 0)
        return;

    int cx = 0, cy = r;
    int df = 1 - r;
    int ddf_x = 0;
    int ddf_y = -2 * r;

    while (cx < cy) {
        cb(x-cy,x+cy,y+cx);
        cb(x-cy,x+cy,y-cx);
        if (df >= 0)  {
            cb(x-cx,x+cx,y+cy);
            cb(x-cx,x+cx,y-cy);
            cy--;
            ddf_y += 2;
            df += ddf_y;
        }

        ddf_x += 2;
        df += ddf_x + 1;
        cx++;
    }
    cb(x-cy,x+cy,y+cx);
    cb(x-cy,x+cy,y-cx);
}
