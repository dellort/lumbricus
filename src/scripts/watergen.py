#!/usr/bin/python

import cairo
import math

w = 120.0
h = 8.0
segcount = 100.0

# number of frames
anicount = 20.0

line_width = 25.0

# make place for the border (you'll see if it's not enough)
rh = h+line_width+5

cOneFile = False

if cOneFile:
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, int(w*anicount), int(rh))
    ctx = cairo.Context(surface)


def draw_stuff(ctx, fa):
    ctx.save()

    #ctx.set_line_width(line_width)
    #fill = cairo.LinearGradient(0, 0, 0, 50.0)
    #fill.add_color_stop_rgb(0.0, 1.0, 1.0, 1.0)
    #fill.add_color_stop_rgb(1.0, 0.2, 0.2, 0.5)
    #ctx.set_source(fill)

    ctx.new_path()
    # goes a bit out of the draw area to make the thick line continuous
    for i in range(-5, int(segcount)+5):
        f = i / segcount
        ctx.line_to(f * w, math.sin((f)*math.pi*2)*math.sin(fa*math.pi*2)*h/2)
    path = ctx.copy_path()

    # simulate wwp like gradient (apparently Cairo can't do this natively)

    c1 = (0.2, 0.2, 0.5)
    c2 = (0.61, 0.64, 0.83)

    ctx.translate(0, rh/2 - line_width/2)
    for i in range(0, int(line_width)):
        f = i/line_width
        t = 1.0-f
        ctx.set_source_rgb(c1[0]*f+c2[0]*t, c1[1]*f+c2[1]*t, c1[2]*f+c2[2]*t)
        ctx.new_path()
        ctx.append_path(path)
        ctx.stroke()
        ctx.translate(0, 1)

    ctx.restore()


for n in range(0, int(anicount)):
    fa = n / anicount

    if not cOneFile:
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, int(w), int(rh))
        ctx = cairo.Context(surface)
    else:
        # this is like Canvas.setWindow
        ctx.save()
        ctx.translate(n*w, 0)
        ctx.rectangle(0, 0, w, rh)
        ctx.clip()

    draw_stuff(ctx, fa)

    if not cOneFile:
        surface.write_to_png("out%03d.png" % (n+1))
    else:
        ctx.restore()

if cOneFile:
    surface.write_to_png("out.png")

