module game.weapon.girder;

import framework.framework;
import game.action.base;
import game.action.wcontext;
import game.game;
import game.gfxset;
import game.sprite;
import game.weapon.weapon;
import game.wcontrol;
import game.gamepublic;
import game.levelgen.landscape;
import physics.world;
import utils.configfile;
import utils.factory;
import utils.reflection;
import utils.time;
import utils.vector2;
import utils.log;
import utils.misc;
import utils.randval;

import math = tango.math.Math;
import mymath = utils.math;

static this() {
    regAction!(putgirder, "")("putgirder");
}

float girder_rotation(int n, int steps) {
    //start horizontal, 22.5° steps, no upside-down
    return math.PI/steps * realmod!(int)(n+steps/2, steps) - math.PI/2;
}

Surface[] create_girders(Surface girder, int steps) {
    Surface[] res;
    res ~= girder;
    for (int n = 1; n < steps; n++) {
        res ~= girder.rotated(girder_rotation(n, steps), true);
    }
    return res;
}

//temporary object that is active while the girder weapon is selected
class GirderControl : WeaponSelector, Controllable {
    private {
        GameEngine mEngine;
        GObjectSprite mOwner;
        WormControl mControl;
        Surface[] mGirders, mGirdersLong;
        int mGirderSel, mGirderAnimSel;
        bool mDoubleLen;
        //rectangle for the girder; used as bounding box
        Vector2i mBaseSize;

        const cRotateSteps = 8;
        const cMaxDistance = 500;  //in pixels from worm position
    }

    mixin Methods!("mouseRender");

    this(WeaponClass wc, GObjectSprite a_owner) {
        super(wc, a_owner);
        mOwner = a_owner;
        mEngine = mOwner.engine;

        mControl = mEngine.controller.controlFromGameObject(mOwner, true);

        Surface girder = mEngine.level.theme.girder;
        mBaseSize = girder.size;
    }

    this (ReflectCtor c) {
        super(c);
        c.transient(this, &mGirders);
        c.transient(this, &mGirdersLong);
    }

    void initGirderSurfaces() {
        Surface girder = mEngine.level.theme.girder;
        //xxx this should really be cached
        mGirders = create_girders(girder, cRotateSteps);

        Surface longGirder = new Surface(
            Vector2i(girder.size.x*2, girder.size.y), girder.transparency);
        longGirder.copyFrom(girder, Vector2i(0), Vector2i(0), girder.size);
        longGirder.copyFrom(girder, Vector2i(girder.size.x,0),
            Vector2i(0), girder.size);
        mGirdersLong = create_girders(longGirder, cRotateSteps);
        assert(mGirders.length == mGirdersLong.length);
        assert(mGirders.length == cRotateSteps);
    }

    override void onSelect() {
        mControl.pushControllable(this);
        mEngine.addRenderOnMouse(&mouseRender);
    }

    override void onUnselect() {
        mEngine.removeRenderOnMouse(&mouseRender);
        mControl.releaseControllable(this);
    }

    Surface girderSurface() {
        if (mGirders.length < cRotateSteps
            || mGirdersLong.length < cRotateSteps)
        {
            initGirderSurfaces();
        }
        return mDoubleLen ? mGirdersLong[mGirderAnimSel]
            : mGirders[mGirderAnimSel];
    }

    void mouseRender(Canvas c, Vector2i mousepos) {
        Surface bmp = girderSurface();
        bool ok = canInsertAt(mousepos);
        Vector2i pos = mousepos - bmp.size / 2;
        if (c.features & DriverFeatures.transformedQuads) {
            //accelerated driver, blend with red if invalid
            c.drawColored(bmp, pos,
                ok ? Color(1, 1, 1, 0.7) : Color(1, 0.5, 0.5, 0.7));
            //draw the valid placing range
            //xxx can we rely on the canvas having the same coordinate system
            //    as the engine?
            c.drawFilledCircle(toVector2i(mOwner.physics.pos), cMaxDistance,
                Color(0, 1.0, 0, 0.15));
        } else {
            //unaccelerated driver, just show a red circle
            c.draw(bmp, pos);
            c.drawFilledCircle(mousepos, 5, ok ? Color(0,1,0) : Color(1,0,0));
        }
    }

    void rotateGirder(int dir) {
        //index over all girders (single+double)
        mGirderSel = realmod!(int)(mGirderSel + dir, cRotateSteps * 2);
        //animation index
        mGirderAnimSel = mGirderSel % cRotateSteps;
        //so the switch from normal to double is in vertical position
        mDoubleLen = mGirderSel >= cRotateSteps/2
            && mGirderSel < 3*cRotateSteps/2;
    }

    bool canInsertAt(Vector2i pos) {
        Vector2i girderSize = mBaseSize;
        if (mDoubleLen)
            girderSize.x *= 2;
        //check against waterline
        if (pos.y+girderSize.y/2 >= mEngine.waterOffset)
            return false;
        //check distance to worm
        if ((pos - toVector2i(mOwner.physics.pos)).length > cMaxDistance)
            return false;
        //pixel precise collision test with landscape
        //create a polygon that makes up the rotated girder
        //collisePolygon() will use the rasterization code to check each lexel
        Vector2f[4] verts;
        verts[0] = Vector2f(0, 0);
        verts[1] = Vector2f(1, 0);
        verts[2] = Vector2f(1, 1);
        verts[3] = Vector2f(0, 1);
        float rot = girder_rotation(mGirderSel, cRotateSteps);
        foreach (ref v; verts) {
            v = v ^ toVector2f(girderSize);
            v = v - toVector2f(girderSize/2);
            v = v.rotated(rot);
            v += toVector2f(pos);
        }
        foreach (land; mEngine.gameLandscapes) {
            Vector2f[4] lverts;
            lverts[] = verts;
            foreach (ref v; lverts) {
                v -= toVector2f(land.offset);
            }
            if (land.landscape_bitmap.collidePolygon(lverts))
                return false;
        }

        //check for objects
        //do some approximate bullshit, because we can't get a good collision
        //  test anyway (although, a test for convex polygon collision with
        //  circles should be relatively simple - or just a rotated bounding box
        //  with circles)
        for (int a = 0; a < verts.length; a++) {
            for (int b = a + 1; b < verts.length; b++) {
                Vector2f crap1, crap3;
                PhysicObject crap2;
                auto dir = verts[b] - verts[a];
                if (mEngine.physicworld.shootRay(verts[a], dir,
                    dir.length, crap1, crap2, crap3))
                {
                    return false;
                }
            }
        }

        return true;
    }

    void insertAt(Vector2i pos) {
        Surface bmp = girderSurface();
        pos -= bmp.size / 2;
        mEngine.insertIntoLandscape(pos, bmp, Lexel.SolidSoft);
    }

    //--- Controllable
    bool fire(bool keyDown) {
        return false;
    }
    bool jump(JumpMode j) {
        return false;
    }
    bool move(Vector2f m) {
        if (m.y > 0) {
            rotateGirder(1);
        } else if (m.y < 0) {
            rotateGirder(-1);
        } else {
            return false;
        }
        return true;
    }
    GObjectSprite getSprite() {
        return null;
    }
    //--- /Controllable

    static this() {
        WeaponSelectorFactory.register!(typeof(this))("girder_selector");
    }
}

void putgirder(WeaponContext wx) {
    WeaponSelector sel = wx.shooter.selector;
    auto gsel = castStrict!(GirderControl)(sel);
    auto at = toVector2i(wx.fireInfo.info.pointto.currentPos);
    //xxx: this should be checked before the girder "weapon" is triggered
    if (gsel.canInsertAt(at)) {
        gsel.insertAt(at);
    } else {
        Trace.formatln("oh hi, you can't insert this here");
    }
}

