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
static int[] cAngles = [90+45,90+90,90+135,90-45,90-90,90-135];

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
    float realangle;

    this(GameController controller) {
        super(controller);
        physics = new PhysicObject();
        graphic = new Animator();
        auto config = globals.loadConfig("worm");

        Animation loadAnim(char[] name) {
            return new Animation(config.getSubNode("worm_" ~ name));
        }

        mAnim.length = WormAnim.max+1;

        mAnim[WormAnim.Stand][Angle.Up] = loadAnim("stand_up");
        mAnim[WormAnim.Stand][Angle.Down] = loadAnim("stand_down");
        mAnim[WormAnim.Stand][Angle.Norm] = loadAnim("stand_norm");
        mAnim[WormAnim.Move][Angle.Up] = loadAnim("move_up");
        mAnim[WormAnim.Move][Angle.Down] = loadAnim("move_down");
        mAnim[WormAnim.Move][Angle.Norm] = loadAnim("move_norm");

        mBla = loadAnim("bla");
        curanim = mBla;
        //graphic.paused = true;
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

        //ground_angle is the angle of the normal, orthogonal to the worm
        //  walking direction
        //so there are two possible sides (+/- 180 degrees)
        auto nangle = physics.ground_angle+3.141/2;
        //hm!?!?
        auto a = Vector2f.fromPolar(1, nangle);
        auto b = Vector2f.fromPolar(1, physics.rotation);
        if (a*b < 0)
            nangle += 3.141; //+180 degrees
        if (nangle != angle) {
            angle = nangle;

            //whatever
            int angle_dist(int a, int b) {
                int x1 = min(a, b);
                int x2 = max(a, b);
                if (x1 < 180 && x2 > 180) {
                    return abs((x1+360-x2) % 360);
                } else {
                    return x2-x1;
                }
            }

            //pick best animation (what's nearer)
            Angle closest;
            int cur = int.max;
            int iangle = (cast(int)(nangle/(2*3.141)*360)+360*2) % 360;
            foreach (int i, int x; cAngles) {
                if (angle_dist(iangle,x) < cur) {
                    cur = angle_dist(iangle,x);
                    closest = cast(Angle)i;
                }
            }

            //registerLog("xxx")("angle=%s iangle=%s ca=%s cl=%s", angle, iangle, cAngles[closest], closest);

            curanim = mAnim[mState][closest % 3];
            graphic.setMirror(!!(closest/3));
            graphic.setAnimation(curanim);

            //auto x = cast(int)((angle+3.141*2.5)/(2*3.141)*(curanim.frameCount-1));
            //graphic.setFrame(x % (curanim.frameCount));
        }
    }

    private void physImpact(PhysicObject other) {
    }

    private void physDie() {
        graphic.active = false;
    }
}

