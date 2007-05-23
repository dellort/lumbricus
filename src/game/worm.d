module game.worm;

import game.gobject;
import game.animation;
import game.common;
import game.physic;
import game.game;
import utils.misc;
import utils.vector2;
import utils.mylist;
import utils.time;
import utils.log;
import std.math;

enum WormAnim {
    Stand = 0,
    Move,
}

enum Angle {
    Up = 0,
    Norm,
    Down,
}

//indexed by Angle (in degrees)
static float[] cAngles = [90+45,90+90,90+135,90-45,90-90,90-135];

class Worm : GameObject {
    Animator graphic;
    alias Animation[Angle.max+1] bla;
    bla[] mAnim;
    Animation mBla;
    Animation curanim;
    PhysicObject physics;
    WormAnim mState;
    float angle; //in radians!
    float set_angle; //angle as set in graphic, needs update if !=angle!

    this(GameController controller) {
        super(controller);
        physics = new PhysicObject();
        graphic = new Animator();
        auto config = globals.loadConfig("worm");

        Animation loadAnim(char[] name) {
            return new Animation(config.getSubNode("worm_" ~ name));
        }

        /*foreach (inout Animation[] a; mAnim) {
            a.length = WormAnim.max+1;
        }*/
        mAnim.length = WormAnim.max+1;

        /*mAnim[WormAnim.Stand][Angle.Up] = loadAnim("stand_up");
        mAnim[WormAnim.Stand][Angle.Down] = loadAnim("stand_down");
        mAnim[WormAnim.Stand][Angle.Norm] = loadAnim("stand_norm");
        mAnim[WormAnim.Move][Angle.Up] = loadAnim("move_up");
        mAnim[WormAnim.Move][Angle.Down] = loadAnim("move_down");
        mAnim[WormAnim.Move][Angle.Norm] = loadAnim("move_norm");*/

        mBla = loadAnim("bla");
        curanim = mBla;
        graphic.paused = true;
        graphic.setAnimation(curanim);

        mState = WormAnim.Stand;

        graphic.setScene(controller.scene, GameZOrder.Objects);
        physics.radius = 5;
        physics.onUpdate = &physUpdate;
        physics.onImpact = &physImpact;
        physics.glueForce = 100;
        controller.physicworld.add(physics);
    }

    void setPos(Vector2i pos) {
        physics.pos = toVector2f(pos);
        physUpdate();
    }

    private void physUpdate() {
        if (curanim) {
            graphic.pos = toVector2i(physics.pos) - curanim.size/2;
        }

        auto nangle = physics.rotation;//ground_angle-3.141/2;
        if (nangle != angle) {
            angle = nangle;
            /*
            //pick best animation (what's nearer)
            Angle closest;
            float cur = float.max;
            foreach (int i, float x; cAngles) {
                x = x/360.0f * 2*3.141;
                if (fabs(angle-x) < cur) {
                    cur = fabs(angle-x);
                    closest = cast(Angle)i;
                }
            }

            registerLog("xxx")("%s -> %s", angle, closest);

            curanim = mAnim[mState][closest % 3];*/
            //graphic.setAnimation(curanim);
            auto x = cast(int)((angle+3.141*2.5)/(2*3.141)*(curanim.frameCount-1));
            graphic.setFrame(x % (curanim.frameCount));
        }
    }

    private void physImpact(PhysicObject other) {
    }

    private void physDie() {
        graphic.active = false;
    }
}

