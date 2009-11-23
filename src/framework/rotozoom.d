//source:
//http://dsource.org/projects/bindings/browser/trunk/sdl_rotozoom/rotozoom.d
//revision 20
//changes by me (in this svn):
//- converted to Tango
//- remove support for 8 bit palette pixel formats (only rgba32 now)
//- make independent from SDL ('Pixels' instead of 'SDL_Surface*')

// converted to D by clayasaurus

/*  

   SDL_rotozoom.d

   Copyright (C) A. Schiffler, July 2001

   This library is free software; you can redistribute it and/or
   modify it under the terms of the GNU Lesser General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This library is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Lesser General Public License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with this library; if not, write to the Free Software
   Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA

*/
module framework.rotozoom;

import tango.stdc.stdlib : malloc, free;
import tango.stdc.string : memset;
import tango.math.Math : PI, sin, cos, ceil, max;
import tango.math.IEEE : fabs;

import utils.color : Color;

private
{
   const float VALUE_LIMIT = 0.001;

   alias ubyte Uint8;
   alias uint Uint32;
   alias Color.RGBA32 tColorRGBA;

   
   // return the greater of two value
   real MAX(real a, real b) { if (a > b) return a; return b; }
}

const bool SMOOTHING_OFF = 0;
const bool SMOOTHING_ON  = 1;

//reference a bitmap or a sub-bitmap (for sub-bitmaps, pitch != w*4)
struct Pixels {
    int w, h;
    void* pixels;   //actually Color.RGBA32*
    uint pitch;     //in bytes
}

//gets called once by the frontend functions to create the destination surface
//callee must create a bitmap with size (w,h) and fill the Pixels member
alias void delegate(out Pixels out_dest, int w, int h) CreatePixelsDg;

/* 

32bit Zoomer with optional anti-aliasing by bilinear interpolation.

Zoomes 32bit RGBA/ABGR 'src' surface to 'dst' surface.

*/

int zoomSurfaceRGBA (Pixels src, Pixels dst, int smooth)
{
 /*  int x, y, sx, sy, *sax, *say, *csax, *csay, csx, csy, ex, ey, t1, t2, sstep;
   tColorRGBA *c00, *c01, *c10, *c11;
   tColorRGBA *sp, *csp, *dp;*/

   int x, y, sx, sy;
   int csx, csy, ex, ey, t1, t2, sstep;
   int * sax, say, csax, csay;
   tColorRGBA * c00, c01, c10, c11;
   tColorRGBA * sp, csp, dp;

   int sgap, dgap;
   
   /* Variable setup */
   if (smooth)
      {
         /* For interpolation: assume source dimension is one pixel */
         /* smaller to avoid overflow on right and bottom edge.     */
         sx = cast(int) (65536.0 * cast(float) (src.w - 1) / cast(float) dst.w);
         sy = cast(int) (65536.0 * cast(float) (src.h - 1) / cast(float) dst.h);
      }
   else
      {
         sx = cast(int) (65536.0 * cast(float) src.w / cast(float) dst.w);
         sy = cast(int) (65536.0 * cast(float) src.h / cast(float) dst.h);
      }
   
   /* Allocate memory for row increments */
   if ((sax = cast(int *) malloc ((dst.w + 1) * Uint32.sizeof)) is null)
      {
         return (-1);
      }
   if ((say = cast(int *) malloc ((dst.h + 1) * Uint32.sizeof)) is null)
      {
         free (sax);
         return (-1);
      }
   
   /* Precalculate row increments */
   csx = 0;
   csax = sax;
   for (x = 0; x <= dst.w; x++)
      {
         *csax = csx;
         csax++;
         csx &= 0xffff;
         csx += sx;
      }
   csy = 0;
   csay = say;
   for (y = 0; y <= dst.h; y++)
      {
         *csay = csy;
         csay++;
         csy &= 0xffff;
         csy += sy;
      }
   
   /* Pointer setup */
   sp = csp = cast(tColorRGBA *) src.pixels;
   dp = cast(tColorRGBA *) dst.pixels;
   sgap = src.pitch - src.w * 4;
   dgap = dst.pitch - dst.w * 4;
   
   /* Switch between interpolating and non-interpolating code */
   if (smooth)
      {
   
         /* Interpolating Zoom */
   
         /* Scan destination */
         csay = say;
         for (y = 0; y < dst.h; y++)
      {
      /* Setup color source pointers */
      c00 = csp;
      c01 = csp;
      c01++;
      c10 = cast(tColorRGBA *) (cast(Uint8 *) csp + src.pitch);
      c11 = c10;
      c11++;
      csax = sax;
      for (x = 0; x < dst.w; x++)
         {
            /* ABGR ordering */
            /* Interpolate colors */
            ex = (*csax & 0xffff);
            ey = (*csay & 0xffff);
            t1 = ((((c01.r - c00.r) * ex) >> 16) + c00.r) & 0xff;
            t2 = ((((c11.r - c10.r) * ex) >> 16) + c10.r) & 0xff;
            dp.r = (((t2 - t1) * ey) >> 16) + t1;
            t1 = ((((c01.g - c00.g) * ex) >> 16) + c00.g) & 0xff;
            t2 = ((((c11.g - c10.g) * ex) >> 16) + c10.g) & 0xff;
            dp.g = (((t2 - t1) * ey) >> 16) + t1;
            t1 = ((((c01.b - c00.b) * ex) >> 16) + c00.b) & 0xff;
            t2 = ((((c11.b - c10.b) * ex) >> 16) + c10.b) & 0xff;
            dp.b = (((t2 - t1) * ey) >> 16) + t1;
            t1 = ((((c01.a - c00.a) * ex) >> 16) + c00.a) & 0xff;
            t2 = ((((c11.a - c10.a) * ex) >> 16) + c10.a) & 0xff;
            dp.a = (((t2 - t1) * ey) >> 16) + t1;
            /* Advance source pointers */
            csax++;
            sstep = (*csax >> 16);
            c00 += sstep;
            c01 += sstep;
            c10 += sstep;
            c11 += sstep;
            /* Advance destination pointer */
            dp++;
         }
      /* Advance source pointer */
      csay++;
      csp = cast(tColorRGBA *) (cast(Uint8 *) csp + (*csay >> 16) * src.pitch);
      /* Advance destination pointers */
      dp = cast(tColorRGBA *) (cast(Uint8 *) dp + dgap);
      }
   
      }
   else
      {
   
         /* Non-Interpolating Zoom */
   
         csay = say;
         for (y = 0; y < dst.h; y++)
      {
      sp = csp;
      csax = sax;
      for (x = 0; x < dst.w; x++)
         {
            /* Draw */
            *dp = *sp;
            /* Advance source pointers */
            csax++;
            sp += (*csax >> 16);
            /* Advance destination pointer */
            dp++;
         }
      /* Advance source pointer */
      csay++;
      csp = cast(tColorRGBA *) (cast(Uint8 *) csp + (*csay >> 16) * src.pitch);
      /* Advance destination pointers */
      dp = cast(tColorRGBA *) (cast(Uint8 *) dp + dgap);
      }
   
      }
   
   /* Remove temp arrays */
   free (sax);
   free (say);
   
   return (0);
}


/* 

32bit Rotozoomer with optional anti-aliasing by bilinear interpolation.

Rotates and zoomes 32bit RGBA/ABGR 'src' surface to 'dst' surface.

*/

void transformSurfaceRGBA (Pixels src, Pixels dst, int cx, int cy,
            int isin, int icos, int smooth)
{
   int x, y, t1, t2, dx, dy, xd, yd, sdx, sdy, ax, ay, ex, ey, sw, sh;
   tColorRGBA c00, c01, c10, c11;
   //tColorRGBA *pc, *sp;
   tColorRGBA *pc, sp;
   int gap;
   
   /* Variable setup */
   xd = ((src.w - dst.w) << 15);
   yd = ((src.h - dst.h) << 15);
   ax = (cx << 16) - (icos * cx);
   ay = (cy << 16) - (isin * cx);
   sw = src.w - 1;
   sh = src.h - 1;
   pc = cast(tColorRGBA *)dst.pixels;
   gap = dst.pitch - dst.w * 4;
   
   /* Switch between interpolating and non-interpolating code */
   if (smooth)
      {
         for (y = 0; y < dst.h; y++)
      {
      dy = cy - y;
      sdx = (ax + (isin * dy)) + xd;
      sdy = (ay - (icos * dy)) + yd;
      for (x = 0; x < dst.w; x++)
         {
            dx = (sdx >> 16);
            dy = (sdy >> 16);
            if ((dx >= -1) && (dy >= -1) && (dx < src.w) && (dy < src.h))
         {
         if ((dx >= 0) && (dy >= 0) && (dx < sw) && (dy < sh))
            {
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               sp += dx;
               c00 = *sp;
               sp += 1;
               c01 = *sp;
               sp = cast(tColorRGBA *) (cast(Uint8 *) sp + src.pitch);
               sp -= 1;
               c10 = *sp;
               sp += 1;
               c11 = *sp;
            }
         else if ((dx == sw) && (dy == sh))
            {
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               sp += dx;
               c00 = *sp;
               c01 = *pc;
               c10 = *pc;
               c11 = *pc;
            }
         else if ((dx == -1) && (dy == -1))
            {
               sp = cast(tColorRGBA *) (src.pixels);
               c00 = *pc;
               c01 = *pc;
               c10 = *pc;
               c11 = *sp;
            }
         else if ((dx == -1) && (dy == sh))
            {
               sp = cast(tColorRGBA *) (src.pixels);
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               c00 = *pc;
               c01 = *sp;
               c10 = *pc;
               c11 = *pc;
            }
         else if ((dx == sw) && (dy == -1))
            {
               sp = cast(tColorRGBA *) (src.pixels);
               sp += dx;
               c00 = *pc;
               c01 = *pc;
               c10 = *sp;
               c11 = *pc;
            }
         else if (dx == -1)
            {
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               c00 = *pc;
               c01 = *sp;
               c10 = *pc;
               sp = cast(tColorRGBA *) (cast(Uint8 *) sp + src.pitch);
               c11 = *sp;
            }
         else if (dy == -1)
            {
               sp = cast(tColorRGBA *) (src.pixels);
               sp += dx;
               c00 = *pc;
               c01 = *pc;
               c10 = *sp;
               sp += 1;
               c11 = *sp;
            }
         else if (dx == sw)
            {
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               sp += dx;
               c00 = *sp;
               c01 = *pc;
               sp = cast(tColorRGBA *) (cast(Uint8 *) sp + src.pitch);
               c10 = *sp;
               c11 = *pc;
            }
         else if (dy == sh)
            {
               sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels +
                  src.pitch * dy);
               sp += dx;
               c00 = *sp;
               sp += 1;
               c01 = *sp;
               c10 = *pc;
               c11 = *pc;
            }
         /* Interpolate colors */
         ex = (sdx & 0xffff);
         ey = (sdy & 0xffff);
         t1 = ((((c01.r - c00.r) * ex) >> 16) + c00.r) & 0xff;
         t2 = ((((c11.r - c10.r) * ex) >> 16) + c10.r) & 0xff;
         pc.r = (((t2 - t1) * ey) >> 16) + t1;
         t1 = ((((c01.g - c00.g) * ex) >> 16) + c00.g) & 0xff;
         t2 = ((((c11.g - c10.g) * ex) >> 16) + c10.g) & 0xff;
         pc.g = (((t2 - t1) * ey) >> 16) + t1;
         t1 = ((((c01.b - c00.b) * ex) >> 16) + c00.b) & 0xff;
         t2 = ((((c11.b - c10.b) * ex) >> 16) + c10.b) & 0xff;
         pc.b = (((t2 - t1) * ey) >> 16) + t1;
         t1 = ((((c01.a - c00.a) * ex) >> 16) + c00.a) & 0xff;
         t2 = ((((c11.a - c10.a) * ex) >> 16) + c10.a) & 0xff;
         pc.a = (((t2 - t1) * ey) >> 16) + t1;
   
         }
            sdx += icos;
            sdy += isin;
            pc++;
         }
      pc = cast(tColorRGBA *) (cast(Uint8 *) pc + gap);
      }
      }
   else
      {
         for (y = 0; y < dst.h; y++)
      {
      dy = cy - y;
      sdx = (ax + (isin * dy)) + xd;
      sdy = (ay - (icos * dy)) + yd;
      for (x = 0; x < dst.w; x++)
         {
            dx = cast(short) (sdx >> 16);
            dy = cast(short) (sdy >> 16);
            if ((dx >= 0) && (dy >= 0) && (dx < src.w) && (dy < src.h))
         {
         sp =
            cast(tColorRGBA *) (cast(Uint8 *) src.pixels + src.pitch * dy);
         sp += dx;
         *pc = *sp;
         }
            sdx += icos;
            sdy += isin;
            pc++;
         }
      pc = cast(tColorRGBA *) (cast(Uint8 *) pc + gap);
      }
      }
}

/* 

rotozoomSurface()

Rotates and zoomes a 32bit or 8bit 'src' surface to newly created 'dst' surface.
'angle' is the rotation in degrees. 'zoom' a scaling factor. If 'smooth' is 1
then the destination 32bit surface is anti-aliased. If the surface is not 8bit
or 32bit RGBA/ABGR it will be converted into a 32bit RGBA format on the fly.

*/


void rotozoomSurface (Pixels src, double angle, double zoom, int smooth,
    CreatePixelsDg create_dg)
   {
   double zoominv;
   double radangle, sanglezoom, canglezoom, sanglezoominv, canglezoominv;
   int dstwidthhalf, dstwidth, dstheighthalf, dstheight;
   double x, y, cx, cy, sx, sy;
   int is32bit;
   int i;
   
   /* Sanity check zoom factor */
   if (zoom < VALUE_LIMIT)
      {
         zoom = VALUE_LIMIT;
      }
   zoominv = 65536.0 / zoom;
   
   /* Check if we have a rotozoom or just a zoom */
   if (fabs (angle) > VALUE_LIMIT)
      {
   
         /* Angle!=0: full rotozoom */
         /* ----------------------- */
   
         /* Calculate target factors from sin/cos and zoom */
         radangle = angle * (PI / 180.0);
         sanglezoom = sanglezoominv = sin (radangle);
         canglezoom = canglezoominv = cos (radangle);
         sanglezoom *= zoom;
         canglezoom *= zoom;
         sanglezoominv *= zoominv;
         canglezoominv *= zoominv;
   
         /* Determine destination width and height by rotating a centered source box */
         x = src.w / 2;
         y = src.h / 2;
         cx = canglezoom * x;
         cy = canglezoom * y;
         sx = sanglezoom * x;
         sy = sanglezoom * y;
         dstwidthhalf = cast(int)
      MAX (
         ceil (MAX
            (MAX
            (MAX (fabs (cx + sy), fabs (cx - sy)), fabs (-cx + sy)),
            fabs (-cx - sy))), 1);
   
         dstheighthalf = cast(int)
   
      MAX (
         ceil (MAX
            (MAX
            (MAX (fabs (sx + cy), fabs (sx - cy)), fabs (-sx + cy)),
            fabs (-sx - cy))), 1);
         dstwidth = 2 * dstwidthhalf;
         dstheight = 2 * dstheighthalf;

      /* Target surface is 32bit with source RGBA/ABGR ordering */
      Pixels dst;
      create_dg(dst, dstwidth, dstheight);

      /* Call the 32bit transformation routine to do the rotation (using alpha) */
      transformSurfaceRGBA (src, dst, dstwidthhalf, dstheighthalf,
               cast(int) (sanglezoominv),
               cast(int) (canglezoominv), smooth);
      }
   else
      {
   
         /* Angle=0: Just a zoom */
         /* -------------------- */
   
         /* Calculate target size and set rect */
         dstwidth = cast(int) (cast(double) src.w * zoom);
         dstheight = cast(int) (cast(double) src.h * zoom);
         if (dstwidth < 1)
      {
      dstwidth = 1;
      }
         if (dstheight < 1)
      {
      dstheight = 1;
      }
   
         /* Alloc space to completely contain the zoomed surface */

      /* Target surface is 32bit with source RGBA/ABGR ordering */
      Pixels dst;
      create_dg(dst, dstwidth, dstheight);

      /* Call the 32bit transformation routine to do the zooming (using alpha) */
      zoomSurfaceRGBA (src, dst, smooth);
      }
}

/* 

zoomSurface()

Zoomes a 32bit or 8bit 'src' surface to newly created 'dst' surface.
'zoomx' and 'zoomy' are scaling factors for width and height. If 'smooth' is 1
then the destination 32bit surface is anti-aliased. If the surface is not 8bit
or 32bit RGBA/ABGR it will be converted into a 32bit RGBA format on the fly.

*/

void zoomSurface (Pixels src, double zoomx, double zoomy, int smooth,
    CreatePixelsDg create_dg)
   {
   int dstwidth, dstheight;
   int is32bit;
   int i, src_converted;
   
   /* Sanity check zoom factors */
   if (zoomx < VALUE_LIMIT)
      {
         zoomx = VALUE_LIMIT;
      }
   if (zoomy < VALUE_LIMIT)
      {
         zoomy = VALUE_LIMIT;
      }
   
   /* Calculate target size and set rect */
   dstwidth = cast(int) (cast(double) src.w * zoomx);
   dstheight = cast(int) (cast(double) src.h * zoomy);
   if (dstwidth < 1)
      {
         dstwidth = 1;
      }
   if (dstheight < 1)
      {
         dstheight = 1;
      }
   
   /* Alloc space to completely contain the zoomed surface */

         /* Target surface is 32bit with source RGBA/ABGR ordering */
         Pixels dst;
         create_dg(dst, dstwidth, dstheight);

         /* Call the 32bit transformation routine to do the zooming (using alpha) */
         zoomSurfaceRGBA (src, dst, smooth);
}