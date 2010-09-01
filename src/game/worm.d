module game.worm;

import common.animation;
import framework.framework;
import game.core;
import game.sequence;
import game.sprite;
import game.teamtheme;
import game.temp : GameZOrder;
import game.particles;
import physics.all;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.log;
import utils.misc;
import utils.math;
import tango.math.Math;

//crosshair
import common.scene;
import utils.interpolate;
import utils.timesource;


///which style a worm should jump
//keep in sync with worm.lua
enum JumpMode {
    normal,      ///standard forward jump (return)
    smallBack,   ///little backwards jump (double return)
    backFlip,    ///large backwards jump/flip (double backspace)
    straightUp,  ///jump straight up (backspace)
}

enum FlyMode {
    fall,
    slide,
    roll,
    heavy,
}

class WormSprite : Sprite {
    private {
        WormSpriteClass wsc;
        WormStateInfo mCurrentState; //must not be null

        //beam destination, only valid while state is st_beaming
        Vector2f mBeamDest;
        //cached movement, will be applied in simulate
        Vector2f mMoveVector;
        //hack for rope (animation only)
        float mRotationOverride = float.nan;

        Time mStandTime;

        //by default off, GameController can use this
        bool mDelayedDeath;
        bool mIsFixed;

        int mGravestone;

        FlyMode mLastFlyMode;
        Time mLastFlyChange, mLastDmg;

        JumpMode mJumpMode;

        static LogStruct!("worm") log;
    }

    TeamTheme teamColor;

    protected this(WormSpriteClass spriteclass) {
        super(spriteclass);
        wsc = spriteclass;
        setStateForced(wsc.st_stand);

        gravestone = 0;
    }

    WormStateInfo currentState() {
        assert(!!mCurrentState);
        return mCurrentState;
    }
    private void currentState(WormStateInfo n) {
        mCurrentState = n;
    }

    override protected void updateInternalActive() {
        super.updateInternalActive();
        if (internal_active) {
            setCurrentAnimation();
        }
    }

    override bool activity() {
        return super.activity()
            || currentState == wsc.st_jump_start
            || currentState == wsc.st_beaming
            || currentState == wsc.st_reverse_beaming
            || currentState == wsc.st_getup
            || isDelayedDying;
    }

    void youWinNow() {
        setState(wsc.st_win);
    }

    //if can move etc.
    bool haveAnyControl() {
        return isAlive() && !currentState.isUnderWater;
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

    /+
     + Death is a complicated thing. There are 4 possibilities (death states):
     +  1. worm is really REALLY alive
     +  2. worm is dead, but still sitting around on the landscape (HUD still
     +     displays >0 health points, although HP is usually <= 0)
     +     this is "delayed death", until the gamemode stuff actually triggers
     +     dying with checkDying()
     +  3. worm is dead and in the progress of suiciding (an animation is
     +     displayed, showing the worm blowing up itself)
     +  4. worm is really REALLY dead, and is not visible anymore
     +     (worm sprite gets replaced by a gravestone sprite)
     + For the game, the only difference between 1. and 2. is, that in 2. the
     + worm is not controllable anymore. In 2., the health points usually are
     + <= 0, but for the game logic (and physics etc.), the worm is still alive.
     + The worm can only be engaged in state 1.
     +
     + If delayed death is not enabled (with setDelayedDeath()), state 2 is
     + skipped.
     +
     + When the worm is drowning, it's still considered alive. (xxx: need to
     + implement this properly) The worm dies with state 4 when it reaches the
     + "death zone".
     +
     + Note the the health points amount can be > 0 even if the worm is dead.
     + e.g. when the worm drowned and died on the death zone.
     +/

    //death states: 1
    //true: alive and healthy
    //false: waiting for suicide, suiciding, or dead and removed from world
    bool isAlive() {
        return physics.lifepower > 0 && !physics.dead;
    }

    //death states: 2 and 3
    //true: waiting for suicide or suiciding
    //false: anything else
    bool isWaitingForDeath() {
        return !isAlive() && !isReallyDead();
    }

    //death states: 4
    //true: dead and removed from world
    //false: anything else
    bool isReallyDead()
    out (res) { assert(!res || (physics.lifepower < 0) || physics.dead); }
    body {
        return currentState is wsc.st_dead;
    }

    //if suicide animation played
    bool isDelayedDying() {
        return currentState is wsc.st_die;
    }

    void finallyDie() {
        if (isAlive())
            return;
        if (internal_active) {
            if (isDelayedDying())
                return;
            //assert(delayedDeath());
            assert(!isAlive());
            setState(wsc.st_die);
        }
    }

    override protected void onKill() {
        if (currentState !is wsc.st_dead)
            setState(wsc.st_dead);
        super.onKill();
    }

    protected void setCurrentAnimation() {
        if (!graphic)
            return;

        if (currentState is wsc.st_jump) {
            switch (mJumpMode) {
                case JumpMode.normal, JumpMode.smallBack, JumpMode.straightUp:
                    auto state = wsc.findSequenceState("jump_normal", true);
                    graphic.setState(state);
                    break;
                case JumpMode.backFlip:
                    auto state = wsc.findSequenceState("jump_backflip", true);
                    graphic.setState(state);
                    break;
                default:
                    assert(false, "Implement");
            }
            return; //?
        }

        graphic.setState(currentState.animation);
    }

    override protected void waterStateChange() {
        super.waterStateChange();
        //do something that involves a worm and a lot of water
        if (isUnderWater && !currentState.isUnderWater
            && currentState !is wsc.st_dead)
        {
            setStateForced(currentState !is wsc.st_frozen
                ? wsc.st_drowning : wsc.st_drowning_frozen);
        }
    }

    protected override void fillAnimUpdate() {
        super.fillAnimUpdate();

        //for jetpack
        graphic.selfForce = physics.selfForce;
        if (mRotationOverride == mRotationOverride)
            graphic.rotation_angle = mRotationOverride;
    }

    void rotationOverride(float rot) {
        mRotationOverride = rot;
    }

    //movement for walking/jetpack
    void move(Vector2f dir) {
        mMoveVector = dir;
    }

    bool isBeaming() {
        return (currentState is wsc.st_beaming)
            || (currentState is wsc.st_reverse_beaming) ;
    }

    void beamTo(Vector2f npos) {
        //if (!isSitting())
        //    return; //only can beam when standing
        log.trace("beam to: {}", npos);
        //xxx: check and lock destination
        mBeamDest = npos;
        setState(wsc.st_beaming);
    }

    void abortBeaming() {
        if (isBeaming)
            //xxx is that enough? what about animation?
            setStateForced(wsc.st_stand);
    }

    void freeze(bool frozen) {
        if (frozen) {
            setState(wsc.st_frozen);
        } else {
            if (currentState is wsc.st_frozen)
                setStateForced(wsc.st_unfreeze);
        }
    }

    //overwritten from GObject.simulate()
    override void simulate() {
        physUpdate();

        super.simulate();

        if (currentState.onAnimationEnd && graphic) {
            //as requested by d0c, timing is dependend from the animation
            if (graphic.readyflag) {
                log.trace("state transition because of animation end");
                //time to change; the setState code will reset the animation
                setState(currentState.onAnimationEnd, true);
            }
        }

        setParticle(currentState.particle);

        if (wormCanWalkJump()) {
            physics.setWalking(mMoveVector);
        }

        //when in stand state, draw weapon after 350ms
        //xxx visual only, maybe Sequence should do it (disabled for now)
        /*if (isStanding() && mRequestedWeapon) {
            if (mStandTime == Time.Never)
                mStandTime = engine.gameTime.current;
            //worms are not standing, they are FIGHTING!
            if (engine.gameTime.current - mStandTime > timeMsecs(350)) {
                setState(wsc.st_weapon);
            }
        } else {
            mStandTime = Time.Never;
        }*/
    }

    void jump(JumpMode m) {
        if (wormCanWalkJump()) {
            mJumpMode = m;
            setState(wsc.st_jump_start);
        } else if (currentState is wsc.st_jump_start) {
            //double-click
            if (mJumpMode == JumpMode.normal) mJumpMode = JumpMode.smallBack;
            if (mJumpMode == JumpMode.straightUp) mJumpMode = JumpMode.backFlip;
        }
    }

    private bool wormCanWalkJump() {
        //no walk while shooting (or charging)
        return currentState.canWalk && !isFixed();
    }

    bool isFixed() {
        return mIsFixed;
    }
    void isFixed(bool f) {
        mIsFixed = f;
    }

    bool delayedAction() {
        //isBeaming: hack to prevent aborting beam on turn-end
        //  (those wormstate-changing weapons are all a big hack anyway)
        return isBeaming();
    }

    void forceAbort() {
        abortBeaming();
    }

    protected void stateTransition(WormStateInfo from,
        WormStateInfo to)
    {

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
            physics.addImpulse(look.mulEntries(wsc.jumpStrength[mJumpMode]));
        }

        //die by blowing up
        if (to is wsc.st_dead) {
            bool was_alive = objectAlive();
            kill();
            //only show if it didn't die in deathzone
            //(the only reason this check is needed is because simulate() is
            //  somehow called when updating the graphic when kill() is called)
            if (was_alive) {
                //explosion!
                engine.explosionAt(physics.pos, wsc.suicideDamage, this);
                SpriteClass findGrave(int id) {
                    return engine.resources.get!(SpriteClass)
                        (myformat("x_gravestone{}", id), true);
                }
                auto graveclass = findGrave(mGravestone);
                if (!graveclass) //try to default to first gravestone
                    graveclass = findGrave(0);
                //no gravestone if not available?
                if (graveclass) {
                    auto grave = graveclass.createSprite();
                    grave.createdBy = this;
                    grave.activate(physics.pos);
                }
            }
        }

        //stop movement if not possible
        if (!currentState.canWalk) {
            physics.setWalking(Vector2f(0));
        }
        mRotationOverride = float.nan;
    }

    void setState(WormStateInfo nstate, bool for_end = false) {
        if (nstate is wsc.st_stand &&
            (currentState is wsc.st_fly || currentState is wsc.st_jump ||
            currentState is wsc.st_jump_to_fly))
        {
            nstate = wsc.st_getup;
        }
        //if (nstate !is wsc.st_stand)
          //  Trace.formatln(nstate.name);

        if (currentState is nstate)
            return;

        if (currentState.noleave && !for_end)
            return;

        if (for_end) {
            assert(nstate is currentState.onAnimationEnd);
        }

        log.trace("state {} -> {}", currentState.name, nstate.name);

        auto oldstate = currentState;
        currentState = nstate;
        physics.posp = nstate.physic;
        //stop all induced forces (e.g. jetpack)
        physics.selfForce = Vector2f(0);

        stateTransition(oldstate, currentState);
        //if this fails, maybe stateTransition called setState()?
        assert(currentState is nstate);

        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        //and particles
        updateParticles();

        //update water state (to catch an underwater state transition)
        waterStateChange();
    }

        //do as less as necessary to force a new state
    void setStateForced(WormStateInfo nstate) {
        assert(nstate !is null);

        currentState = nstate;
        physics.posp = nstate.physic;
        //stop all induced forces (e.g. jetpack)
        physics.selfForce = Vector2f(0);
        if (graphic) {
            setCurrentAnimation();
            updateAnimation();
        }

        log.trace("force state: {}", nstate.name);

        waterStateChange();
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
        WormStateInfo wanted = activate ? wsc.st_jet : wsc.st_stand;
        setState(wanted);
    }

    bool ropeActivated() {
        return currentState is wsc.st_rope;
    }

    void activateRope(bool activate) {
        if (activate == ropeActivated())
            return;

        WormStateInfo wanted = activate ? wsc.st_rope : wsc.st_stand;
        setState(wanted);
    }

    //xxx need another solution etc.
    bool drillActivated() {
        return currentState is wsc.st_drill;
    }
    void activateDrill(bool activate) {
        if (activate == drillActivated())
            return;

        setState(activate ? wsc.st_drill : wsc.st_stand);
    }
    bool blowtorchActivated() {
        return currentState is wsc.st_blowtorch;
    }
    void activateBlowtorch(bool activate) {
        if (activate == blowtorchActivated())
            return;

        setState(activate ? wsc.st_blowtorch : wsc.st_stand);
    }
    bool parachuteActivated() {
        return currentState is wsc.st_parachute;
    }
    void activateParachute(bool activate) {
        if (activate == parachuteActivated())
            return;

        setState(activate ? wsc.st_parachute : wsc.st_stand);
    }

    bool isStanding() {
        return currentState is wsc.st_stand;
    }
    bool isFlying() {
        return currentState is wsc.st_fly;
    }

    private void setFlyAnim(FlyMode m) {
        if (!graphic)
            return;
        if (currentState is wsc.st_fly) {
            //going for roll or heavy flight -> look in flying direction
            if (m == FlyMode.roll || m == FlyMode.heavy)
                physics.resetLook();
            //don't change to often
            if (m < mLastFlyMode &&
                engine.gameTime.current - mLastFlyChange < timeMsecs(200))
                return;
            graphic.setState(wsc.flyState[m]);
            mLastFlyChange = engine.gameTime.current;
            mLastFlyMode = m;
        }
    }

    override protected void physImpact(PhysicObject other, Vector2f normal) {
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

    override protected void physDamage(float amout, DamageCause type,
        Object cause)
    {
        super.physDamage(amout, type, cause);
        if (type != DamageCause.explosion)
            return;
        if (currentState is wsc.st_fly) {
            //when damaged in-flight, switch to heavy animation
            //xxx better react to impulse rather than damage
            //setFlyAnim(FlyMode.heavy);
        } else {
            //hit by explosion, abort everything (code below will immediately
            //  correct the state)
            forceAbort();
            setState(wsc.st_stand);
        }
        mLastDmg = engine.gameTime.current;
    }

    private void physUpdate() {
        if (isDelayedDying)
            return;

        if (!jetpackActivated && !blowtorchActivated && !parachuteActivated) {
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
                    if (graphic.currentState is wsc.flyState[FlyMode.fall]
                        || graphic.currentState is
                            wsc.flyState[FlyMode.slide])
                    {
                        setFlyAnim(FlyMode.roll);
                    }
            }
            if (currentState is wsc.st_jump && physics.velocity.y > 0) {
                setState(wsc.st_jump_to_fly);
            }

        }
        //check death
        if (internal_active && !isAlive() && !delayedDeath()) {
            finallyDie();
        }
    }
}

//contains custom state attributes for worm sprites
class WormStateInfo {
    char[] name;

    POSP physic;

    //automatic transition to this state if animation finished
    WormStateInfo onAnimationEnd;
    //don't leave this state (explictly excludes onAnimationEnd)
    bool noleave = false;

    SequenceState animation;

    //if non-null, always ensure a single particle like this is created
    //this normally should be an invisible particle emitter
    ParticleType particle;

    bool isGrounded = false;    //is this a standing-on-ground state
    bool canWalk = false;       //should the worm be allowed to walk
    bool canAim = false;        //can the target cross be moved
    bool canFire = false;       //can the main weapon be fired

    bool isUnderWater = false;

    this (char[] a_name) {
        name = a_name;
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : SpriteClass {
    WormStateInfo[char[]] states;

    float suicideDamage;
    //SequenceObject[] gravestones;
    Vector2f[JumpMode.max+1] jumpStrength;
    Vector2f[] jumpStrengthScript; //no static arrays with Lua wrapper
    float rollVelocity = 400;

    WormStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning, st_beaming, st_reverse_beaming, st_getup,
        st_jump_start, st_jump, st_jump_to_fly, st_rope, st_drill, st_blowtorch,
        st_parachute, st_win, st_frozen, st_unfreeze, st_drowning_frozen;

    //alias WormSprite.FlyMode FlyMode;

    SequenceState[FlyMode.max+1] flyState;

    this(GameCore e, char[] r) {
        super(e, r);

        initNoActivityWhenGlued = true;

        WormStateInfo state(char[] name) {
            assert(!(name in states));
            auto nstate = new WormStateInfo(name);
            states[name] = nstate;
            return nstate;
        }

        st_stand = state("stand");
        st_fly = state("fly");
        st_walk = state("walk");
        st_jet = state("jetpack");
        st_weapon = state("weapon");
        st_dead = state("dead");
        st_die = state("die");
        st_drowning = state("drowning");
        st_beaming = state("beaming");
        st_reverse_beaming = state("reverse_beaming");
        st_getup = state("getup");
        st_jump_start = state("jump_start");
        st_jump = state("jump");
        st_jump_to_fly = state("jump_to_fly");
        st_rope = state("rope");
        st_drill = state("drill");
        st_blowtorch = state("blowtorch");
        st_parachute = state("parachute");
        st_win = state("win");
        st_frozen = state("frozen");
        st_unfreeze = state("unfreeze");
        st_drowning_frozen = state("drowning_frozen");
    }

    void finishLoading() {
        flyState[FlyMode.fall] = findSequenceState("fly_fall",true);
        flyState[FlyMode.slide] = findSequenceState("fly_slide",true);
        flyState[FlyMode.roll] = findSequenceState("fly_roll",true);
        flyState[FlyMode.heavy] = findSequenceState("fly_heavy",true);

        //be aware that D has no array bounds checking in release mode
        //if not careful, a script could make D read past the end of an array
        //also the reason why the actual jumpStrength array is still static
        if (jumpStrengthScript.length == JumpMode.max+1) {
            jumpStrength[] = jumpStrengthScript;
        } else {
            throw new CustomException("jumpStrength invalid");
        }
    }

    override WormSprite createSprite() {
        return new WormSprite(this);
    }

    WormStateInfo findState(char[] name) {
        WormStateInfo* state = name in states;
        if (!state) {
            throwError("state {} not found", name);
        }
        return *state;
    }

    SequenceState findSequenceState(char[] name,
        bool allow_not_found = false)
    {
        //something in projectile.d seems to need this special case?
        if (!sequenceType) {
            if (allow_not_found)
                return null;
            assert(false, "bla.: "~name);
        }
        return sequenceType.findState(name, allow_not_found);
    }
}
