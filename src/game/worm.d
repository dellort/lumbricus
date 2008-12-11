module game.worm;

import framework.framework;
import game.gobject;
import game.animation;
import physics.world;
import game.game;
import game.sequence;
import game.sprite;
import game.weapon.types;
import game.weapon.weapon;
import game.temp;  //whatever, importing gamepublic doesn't give me JumpMode
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.math;
import utils.configfile;
import std.math;
import str = std.string;

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

        //beam destination, only valid while state is st_beaming
        Vector2f mBeamDest;
        //cached movement, will be applied in simulate
        Vector2f mMoveVector;

        //selected weapon
        Shooter mWeapon;

        //by default off, GameController can use this
        bool mDelayedDeath;

        bool mIsDead;

        int mGravestone;

        bool mWeaponAsIcon;

        enum FlyMode {
            fall,
            slide,
            roll,
            heavy,
        }
        FlyMode mLastFlyMode;
        Time mLastFlyChange, mLastDmg;

        SequenceState[FlyMode.max+1] mFlyState;

        JumpMode mJumpMode;
    }

    //-PI/2..+PI/2, actual angle depends from whether worm looks left or right
    float weaponAngle() {
        return mWeaponAngle;
    }

    //real weapon angle (normalized direction)
    Vector2f weaponDir() {
        return dirFromSideAngle(physics.lookey, weaponAngle);
    }

    //if can move etc.
    bool haveAnyControl() {
        return !isDead();
    }

    void gravestone(int grave) {
        //assert(grave >= 0 && grave < wsc.gravestones.length);
        //mGravestone = wsc.gravestones[grave];
        mGravestone = grave;
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

    override protected void updateActive() {
        super.updateActive();
        if (graphic) {
            mFlyState[FlyMode.fall] = graphic.type.findState("fly_fall",true);
            mFlyState[FlyMode.slide] = graphic.type.findState("fly_slide",true);
            mFlyState[FlyMode.roll] = graphic.type.findState("fly_roll",true);
            mFlyState[FlyMode.heavy] = graphic.type.findState("fly_heavy",true);
        }
    }

    protected override void setCurrentAnimation() {
        if (!graphic)
            return;

        if (currentState is wsc.st_weapon) {
            assert(!!mWeapon);
            char[] w = mWeapon.weapon.animations[WeaponWormAnimations.Arm];
            auto state = graphic.type.findState(w, true);
            mWeaponAsIcon = !state;
            if (mWeaponAsIcon) {
                //no specific weapon animation there
                state = graphic.type.findState("weapon_unknown");
            }
            graphic.setState(state);
            return;
        }
        if (currentState is wsc.st_jump) {
            switch (mJumpMode) {
                case JumpMode.normal:
                    auto state = graphic.type.findState("jump_normal", true);
                    graphic.setState(state);
                    break;
                case JumpMode.backFlip:
                    auto state = graphic.type.findState("jump_backflip", true);
                    graphic.setState(state);
                    break;
                default:
                    assert(false, "Implement");
            }
        }
        super.setCurrentAnimation();
    }

    protected override WormSequenceUpdate createSequenceUpdate() {
        return new WormSequenceUpdate();
    }

    protected override void fillAnimUpdate() {
        super.fillAnimUpdate();
        auto wsu = cast(WormSequenceUpdate)seqUpdate;
        assert(!!wsu);
        wsu.pointto_angle = mWeaponAngle;
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        if (jetpackActivated) {
            //force!
            Vector2f jetForce = dir.mulEntries(wsc.jetpackThrust);
            //don't accelerate down
            if (jetForce.y > 0)
                jetForce.y = 0;
            physics.selfForce = jetForce;
        } else {
            mMoveVector = dir;
        }
    }

    bool isBeaming() {
        return (currentState is wsc.st_beaming)
            || (currentState is wsc.st_reverse_beaming) ;
    }

    void beamTo(Vector2f npos) {
        //if (!isSitting())
        //    return; //only can beam when standing
        engine.mLog("beam to: %s", npos);
        //xxx: check and lock destination
        mBeamDest = npos;
        setState(wsc.st_beaming);
    }

    void abortBeaming() {
        if (isBeaming)
            //xxx is that enough? what about animation?
            setStateForced(wsc.st_stand);
    }

    //overwritten from GObject.simulate()
    override void simulate(float deltaT) {
        super.simulate(deltaT);

        //check if the worm is really allowed to move
        if (currentState.canAim) {
            //invert y to go from screen coords to math coords
            mWeaponMove = -mMoveVector.y;
        }
        if (currentState.canWalk) {
            physics.setWalking(mMoveVector);
        }

        if (weaponDrawn) {
            //when user presses key to change weapon angle
            //can rotate through all 180 degrees in 5 seconds
            //(given abs(mWeaponMove) == 1)
            if (abs(mWeaponMove) > 0.0001) {
                mWeaponAngle += mWeaponMove*deltaT*PI/2;
                mWeaponAngle = max(mWeaponAngle, cast(float)-PI/2);
                mWeaponAngle = min(mWeaponAngle, cast(float)PI/2);
                updateAnimation();
            }
        }
        //if shooter dies, undraw weapon
        //xxx doesn't work yet, shooter starts as active=false (wtf)
        //if (mWeapon && !mWeapon.active)
          //  shooter = null;
    }

    void jump(JumpMode m) {
        if (currentState.canWalk) {
            mJumpMode = m;
            setState(wsc.st_jump_start);
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
    //xxx kind of wrong, weapon can be selected in jetpack mode etc. too, needs
    //to be fixed or redefined, the controller is broken anyway
    bool weaponDrawn() {
        return currentState is wsc.st_weapon;
    }

    //if weapon needs to be displayed outside the worm
    //slightly bogus in the same way like weaponDrawn()
    bool displayWeaponIcon() {
        //hm not very nice
        return mWeaponAsIcon && weaponDrawn;
    }

    //xxx: clearify relationship between shooter and so on
    void shooter(Shooter sh) {
        //xxx: haha, not sure if this is right
        //is to disallow interrupting i.e. for guns
        if (mWeapon) {
            if (mWeapon.active)
                mWeapon.interruptFiring();
            if (mWeapon.active)
                return; //interrupting didn't work
        }
        mWeapon = sh;
        if (!sh) {
            drawWeapon(false);
        }
        //xxx: if weapon is changed, play the correct animations
        setCurrentAnimation();
    }
    Shooter shooter() {
        return mWeapon;
    }

    override protected void stateTransition(StaticStateInfo from,
        StaticStateInfo to)
    {
        super.stateTransition(from, to);

        if (!mIsDead && (currentState is wsc.st_drowning)) {
            //die by drowning - are there more actions needed?
            mIsDead = true;
        }

        if (from is wsc.st_beaming) {
            setPos(mBeamDest);
        }

        if (to is wsc.st_fly) {
            //whatever, when you beam the worm into the air
            //xxx replace by propper handing in physics.d
            physics.doUnglue();
        }
        if (to is wsc.st_jump) {
            auto look = Vector2f.fromPolar(1, physics.lookey);
            look.y = 0;
            look = look.normal(); //get sign *g*
            look.y = 1;
            switch (mJumpMode) {
                case JumpMode.normal:
                    physics.addImpulse(look.mulEntries(wsc.jumpStNormal));
                    break;
                case JumpMode.backFlip:
                    physics.addImpulse(look.mulEntries(wsc.jumpStBackflip));
                    break;
                default:
                    assert(false, "Implement");
            }
        }

        //die by blowing up
        if (to is wsc.st_dead) {
            mIsDead = true;
            die();
            //explosion!
            engine.explosionAt(physics.pos, wsc.suicideDamage, this);
            auto grave = castStrict!(GravestoneSprite)(
                engine.createSprite("grave"));
            grave.setGravestone(mGravestone);
            grave.setPos(physics.pos);
        }

        //stop movement if not possible
        if (!currentState.canAim) {
            //invert y to go from screen coords to math coords
            mWeaponMove = 0;
        }
        if (!currentState.canWalk) {
            physics.setWalking(Vector2f(0));
        }
    }

    //xxx sorry for that
    override void setState(StaticStateInfo nstate, bool for_end = false) {
        if (nstate is wsc.st_stand &&
            (currentState is wsc.st_fly || currentState is wsc.st_jump)) {
            super.setState(wsc.st_getup, for_end);
            return;
        }
        super.setState(nstate, for_end);
    }

    override WormStateInfo currentState() {
        return cast(WormStateInfo)super.currentState;
    }

    bool jetpackActivated() {
        return currentState is wsc.st_jet;
    }

    //activate = activate/deactivate the jetpack
    void activateJetpack(bool activate) {
        if (activate == jetpackActivated())
            return;

        //lolhack: return to stand state, and if that's wrong (i.e. jetpack
        //  deactivated in sky), other code will immediately correct the state
        StaticStateInfo wanted = activate ? wsc.st_jet : wsc.st_stand;
        if (!activate) {
            physics.selfForce = Vector2f(0);
        }
        setState(wanted);
    }

    bool isStanding() {
        return currentState is wsc.st_stand;
    }

    private void setFlyAnim(FlyMode m) {
        if (!graphic)
            return;
        if (currentState is wsc.st_fly) {
            //don't change to often
            if (m < mLastFlyMode &&
                engine.gameTime.current - mLastFlyChange < timeMsecs(200))
                return;
            graphic.setState(mFlyState[m]);
            mLastFlyChange = engine.gameTime.current;
            mLastFlyMode = m;
        }
    }

    override protected void physImpact(PhysicBase other, Vector2f normal) {
        super.physImpact(other, normal);
        if (currentState is wsc.st_fly) {
            //impact -> roll
            if (physics.velocity.length >= wsc.rollVelocity)
                setFlyAnim(FlyMode.roll);
            else
                //too slow? so use slide animation
                //xxx not so sure about that
                setFlyAnim(FlyMode.slide);
        }
    }

    override protected void physDamage(float amout, int cause) {
        super.physDamage(amout, cause);
        if (cause != cDamageCauseExplosion)
            return;
        if (currentState is wsc.st_fly) {
            //when damaged in-flight, switch to heavy animation
            //xxx better react to impulse rather than damage
            setFlyAnim(FlyMode.heavy);
        }
        mLastDmg = engine.gameTime.current;
    }

    override protected void physUpdate() {
        if (!isDelayedDying) {
            if (!jetpackActivated) {
                //update walk animation
                if (physics.isGlued) {
                    bool walkst = currentState is wsc.st_walk;
                    if (walkst != physics.isWalking)
                        setState(physics.isWalking ? wsc.st_walk : wsc.st_stand);
                }

                //update if worm is flying around...
                bool onGround = currentState.isGrounded;
                if (physics.isGlued != onGround) {
                    setState(physics.isGlued ? wsc.st_stand : wsc.st_fly);
                    //recent damage -> ungluing possibly caused by explosion
                    //xxx better physics feedback
                    if (engine.gameTime.current - mLastDmg < timeMsecs(100))
                        setFlyAnim(FlyMode.heavy);
                }
                if (currentState is wsc.st_fly && graphic) {
                    //worm is falling to fast -> use roll animation
                    if (physics.velocity.length >= wsc.rollVelocity)
                        if (graphic.getCurrentState is mFlyState[FlyMode.fall]
                         || graphic.getCurrentState is mFlyState[FlyMode.slide])
                            setFlyAnim(FlyMode.roll);
                }
                if (currentState is wsc.st_jump && physics.velocity.y > 0) {
                    setState(wsc.st_fly);
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

//contains custom state attributes for worm sprites
class WormStateInfo : StaticStateInfo {
    bool isGrounded = false;    //is this a standing-on-ground state
    bool canWalk = false;       //should the worm be allowed to walk
    bool canAim = false;        //can the target cross be moved

    override void loadFromConfig(ConfigNode sc, ConfigNode physNode,
        GOSpriteClass owner)
    {
        super.loadFromConfig(sc, physNode, owner);
        isGrounded = sc.getBoolValue("is_grounded", isGrounded);
        canWalk = sc.getBoolValue("can_walk", canWalk);
        canAim = sc.getBoolValue("can_aim", canAim);
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : GOSpriteClass {
    Vector2f jetpackThrust;
    float suicideDamage;
    //SequenceObject[] gravestones;
    Vector2f jumpStNormal, jumpStBackflip;
    float rollVelocity = 400;

    WormStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning, st_beaming, st_reverse_beaming, st_getup,
        st_jump_start, st_jump;

    this(GameEngine e, char[] r) {
        super(e, r);
    }
    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);
        float[] jetTh = config.getValueArray!(float)("jet_thrust", [0f,0f]);
        if (jetTh.length > 1)
            jetpackThrust = Vector2f(jetTh[0], jetTh[1]);
        else
            jetpackThrust = Vector2f(0);
        suicideDamage = config.getFloatValue("suicide_damage", 10);
        float[] js = config.getValueArray!(float)("jump_st_normal",[100,-100]);
        jumpStNormal = Vector2f(js[0],js[1]);
        js = config.getValueArray!(float)("jump_st_backflip",[-20,-150]);
        jumpStBackflip = Vector2f(js[0],js[1]);

        //done, read out the stupid states :/
        st_stand = findState("stand");
        st_fly = findState("fly");
        st_walk = findState("walk");
        st_jet = findState("jetpack");
        st_weapon = findState("weapon");
        st_dead = findState("dead");
        st_die = findState("die");
        st_drowning = findState("drowning");
        st_beaming = findState("beaming");
        st_reverse_beaming = findState("reverse_beaming");
        st_getup = findState("getup");
        st_jump_start = findState("jump_start");
        st_jump = findState("jump");
    }
    override WormSprite createSprite() {
        return new WormSprite(engine, this);
    }

    override StaticStateInfo createStateInfo() {
        return new WormStateInfo();
    }

    override WormStateInfo findState(char[] name, bool canfail = false) {
        return cast(WormStateInfo)super.findState(name, canfail);
    }

    static this() {
        SpriteClassFactory.register!(WormSpriteClass)("worm_mc");
    }
}

class GravestoneSprite : GObjectSprite {
    private {
        GravestoneSpriteClass gsc;
        int mType;
    }

    void setGravestone(int n) {
        assert(n >= 0);
        if (n >= gsc.normal.length) {
            //what to do?
            assert(false, "gravestone not found");
        }
        mType = n;
        setCurrentAnimation();
    }

    protected override void setCurrentAnimation() {
        if (!graphic)
            return;

        SequenceState st;
        if (currentState is gsc.st_normal) {
            st = gsc.normal[mType];
        } else if (currentState is gsc.st_drown) {
            st = gsc.drown[mType];
        } else {
            assert(false);
        }

        graphic.setState(st);
    }

    this(GameEngine e, GravestoneSpriteClass s) {
        super(e, s);
        gsc = s;
        active = true;
    }
}

class GravestoneSpriteClass : GOSpriteClass {
    StaticStateInfo st_normal, st_drown;

    //indexed by type
    SequenceState[] normal;
    SequenceState[] drown;

    this(GameEngine e, char[] r) {
        super(e, r);
    }

    override void loadFromConfig(ConfigNode config) {
        super.loadFromConfig(config);

        st_normal = findState("normal");
        st_drown = findState("drown");

        //try to find as much gravestones as there are
        for (int n = 0; ; n++) {
            auto s_n = sequenceObject.findState(str.format("n%s", n), true);
            auto s_d = sequenceObject.findState(str.format("drown%s", n), true);
            if (!(s_n && s_d))
                break;
            normal ~= s_n;
            drown ~= s_d;
        }
    }

    override GravestoneSprite createSprite() {
        return new GravestoneSprite(engine, this);
    }

    static this() {
        SpriteClassFactory.register!(typeof(this))("grave_mc");
    }
}
