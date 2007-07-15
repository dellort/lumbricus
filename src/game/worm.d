module game.worm;

import game.gobject;
import game.animation;
import common.common;
import game.physic;
import game.game;
import game.sprite;
import game.weapon;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.configfile;
import std.math;
import str = std.string;

static this() {
    gSpriteClassFactory.register!(WormSpriteClass)("worm_mc");
}

/**
  just an idea:
  thing which can be controlled like a worm
  game/controller.d would only have a sprite, which could have this interface...

interface IControllable {
    void move(Vector2f dir);
    void jump();
    void activateJetpack(bool activate);
    void drawWeapon(bool draw);
    bool weaponDrawn();
    void shooter(Shooter w);
    Shooter shooter();
    xxx not uptodate
}
**/

class WormSprite : GObjectSprite {
    private {
        WormSpriteClass wsc;

        float mWeaponAngle = 0;
        float mWeaponMove = 0;

        //selected weapon
        Shooter mWeapon;

        //by default off, GameController can use this
        bool mDelayedDeath;

        bool mIsDead;

        AnimationResource mGravestone;
    }

    float weaponAngle() {
        return mWeaponAngle;
    }

    //if can move etc.
    bool haveAnyControl() {
        return !isDead();
    }

    void gravestone(int grave) {
        assert(grave >= 0 && grave < wsc.gravestones.length);
        mGravestone = wsc.gravestones[grave];
    }

    void delayedDeath(bool delay) {
        mDelayedDeath = delay;
    }
    bool delayedDeath() {
        return mDelayedDeath;
    }

    //if object wants to die; if true, call finallyDie() (etc.)
    //actually, object can have any state, it even can be dead
    //you should prefer isDead()
    bool shouldDie() {
        return physics.lifepower <= 0;
    }

    //if worm is dead (including if worm is waiting to commit suicide)
    bool isDead() {
        return shouldDie() || isReallyDead();
    }
    //less strict than isDead(): return false for not-yet-suicided worms
    //but true for suiciding worms
    bool isReallyDead() {
        return mIsDead;
    }
    //returns true if suiciding is also done
    bool isReallyReallyDead() {
        return mIsDead && currentState is wsc.st_dead;
    }

    //if suicide animation played
    bool isDelayedDying() {
        return isReallyDead() && currentState is wsc.st_die;
    }

    void finallyDie() {
        if (active) {
            if (isDelayedDying())
                return;
            //assert(delayedDeath());
            assert(shouldDie());
            setState(wsc.st_die);
        }
    }

    void updateControl() {
        if (!haveAnyControl()) {
            drawWeapon(false);
            activateJetpack(false);
        }
    }

    protected this (GameEngine engine, WormSpriteClass spriteclass) {
        super(engine, spriteclass);
        wsc = spriteclass;

        gravestone = 0;
    }

    protected AnimationResource getAnimationForState(StaticStateInfo info) {
        if (currentState is wsc.st_weapon && mWeapon) {
            return mWeapon.weapon.animations[WeaponWormAnimations.Arm];
        } else if (currentState is wsc.st_dead) {
            return mGravestone;
        } else {
            return super.getAnimationForState(info);
        }
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //velocity or force? sigh.
            Vector2f jetForce = dir.mulEntries(wsc.jetpackAccel);
            //don't accelerate down
            if (jetForce.y > 0)
                jetForce.y = 0;
            physics.selfForce = jetForce;
        } else if (weaponDrawn) {
            //invert y to go from screen coords to math coords
            mWeaponMove = -dir.y;
        } else {
            physics.setWalking(dir);
        }
    }

    //overwritten from GObject.simulate()
    override void simulate(float deltaT) {
        super.simulate(deltaT);
        if (weaponDrawn) {
            //when user presses key to change weapon angle
            //can rotate through all 180 degrees in 5 seconds
            //(given abs(mWeaponMove) == 1)
            mWeaponAngle += mWeaponMove*deltaT*PI/2;
            mWeaponAngle = max(mWeaponAngle, cast(float)-PI/2);
            mWeaponAngle = min(mWeaponAngle, cast(float)PI/2);
            //[-PI/2, PI/2] to [-90, 90]
            param2 = cast(int)(mWeaponAngle/PI*180.0f);
            updateAnimation();
        }
    }

    void jump() {
        if (physics.isGlued && !jetpackActivated) {
            auto look = Vector2f.fromPolar(1, physics.lookey);
            look.y = 0;
            look = look.normal(); //get sign *g*
            look.y = 1;
            physics.push(look.mulEntries(wsc.jumpStrength));
        }
    }

    void drawWeapon(bool draw) {
        if (draw == weaponDrawn)
            return;
        if (draw) {
            if (currentState !is wsc.st_stand)
                return;
            if (!haveAnyControl())
                return;
            if (!mWeapon)
                return;
        }

        setState(draw ? wsc.st_weapon : wsc.st_stand);
    }
    bool weaponDrawn() {
        return currentState is wsc.st_weapon;
    }

    //xxx: clearify relationship between shooter and so on
    void shooter(Shooter sh) {
        mWeapon = sh;
        if (!sh) {
            drawWeapon(false);
        }
        //xxx: if weapon is changed, play the correct animations
        updateAnimation();
    }
    Shooter shooter() {
        return mWeapon;
    }

    //yyy
    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        super.stateTransition(from, to);

        bool todead = (currentState is wsc.st_dead);
        if (!mIsDead && (todead || currentState is wsc.st_drowning)) {
            engine.mLog("set dead flag for %s", this);
            mIsDead = true;
            if (todead) {
                //explosion!
                engine.explosionAt(physics.pos, wsc.suicideDamage);
            }
        }
    }

    void fireWeapon() {
        assert(false);
    }

    bool jetpackActivated() {
        return currentState is wsc.st_jet;
    }

    //activate = activate/deactivate the jetpack
    void activateJetpack(bool activate) {
        StaticStateInfo wanted = activate ? wsc.st_jet : wsc.st_stand;
        if (!activate) {
            physics.selfForce = Vector2f(0);
        }
        setState(wanted);
    }

    bool isStanding() {
        return currentState is wsc.st_stand;
    }

    override protected void physUpdate() {
        if (!isDelayedDying) {
            if (!jetpackActivated) {
                //update walk animation
                if (physics.isGlued) {
                    bool walk = physics.isWalking;
                    setState(walk ? wsc.st_walk : wsc.st_stand);
                }

                //update if worm is flying around...
                //xxx replace by state-attributes or so *g*
                bool onGround = currentState is wsc.st_stand
                    || currentState is wsc.st_walk
                    || currentState is wsc.st_weapon;
                if (physics.isGlued != onGround) {
                    setState(physics.isGlued ? wsc.st_stand : wsc.st_fly);
                }
            }
            //check death
            if (active && shouldDie() && !delayedDeath()) {
                finallyDie();
            }
        }
        super.physUpdate();
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : GOSpriteClass {
    Vector2f jetpackAccel;
    float suicideDamage;
    AnimationResource[] gravestones;
    Vector2f jumpStrength;

    StaticStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning;

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        float[] jetAc = config.getValueArray!(float)("jet_velocity", [0f,0f]);
        if (jetAc.length > 1)
            jetpackAccel = Vector2f(jetAc[0], jetAc[1]);
        else
            jetpackAccel = Vector2f(0);
        suicideDamage = config.getFloatValue("suicide_damage", 10);
        float[] js = config.getValueArray!(float)("jump_strength",[100,-100]);
        jumpStrength = Vector2f(js[0],js[1]);

        gravestones.length = 0;

        ConfigNode grNode = config.getSubNode("gravestones");
        foreach (char[] v; grNode) {
            char[] grv = grNode.getPathValue(v);
            assert(grv.length > 0);
            gravestones ~= globals.resources.resource!(AnimationResource)
                (grv);
        }

        //done, read out the stupid states :/
        st_stand = findState("sit");
        st_fly = findState("fly");
        st_walk = findState("walk");
        st_jet = findState("jetpack");
        st_weapon = findState("weapon");
        st_dead = findState("dead");
        st_die = findState("die");
        st_drowning = findState("drowning");
    }
    override WormSprite createSprite() {
        return new WormSprite(engine, this);
    }
}

