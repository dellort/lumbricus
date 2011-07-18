module game.worm;

import common.animation;
import framework.drawing;
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
        //hack for rope (animation only)
        float mRotationOverride = float.nan;

        //Time mStandTime;

        //by default off, GameController can use this
        bool mDelayedDeath;
        bool mFixed;

        float mPoisoned = 0;    //>0 means worm is poisoned

        int mGravestone;

        float mPreviousVelocity = 0;
        FlyMode mLastFlyMode;
        Time mLastFlyChange;

        Time mPreGetupStart;    //time when st_pre_getup was entered
        Time mLastFlyReset;     //hack for FlyMode.slide => FlyMode.fall

        Vector2f mMoveVector;
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
        return super.activity() || currentState.activity;
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
     + If delayed death is not enabled (with delayedDeath = true), state 2 is
     + skipped.
     +
     + When the worm is drowning, it's still considered alive. (xxx: need to
     + implement this properly) The worm dies with state 4 when it reaches the
     + "death zone".
     +
     + Note the the health points amount can be > 0 even if the worm is dead.
     + e.g. when the worm drowned and died on the death zone.
     +/

    //if this is true, a killed worm doesn't die immediately, but remains in
    //  a half-dead state (death states 2), until the game logic calls
    //  checkSuiciding(), which initiates the real death
    void delayedDeath(bool delay) {
        mDelayedDeath = delay;
    }
    bool delayedDeath() {
        return mDelayedDeath;
    }

    //death states: 1
    //true: alive and healthy
    //false: waiting for suicide, suiciding, or dead and removed from world
    bool isAlive() {
        return physics.lifepower > 0 && !physics.dead;
    }

    //death states: 2 and 3
    //true: waiting for suicide or suiciding
    //false: anything else
    private bool isWaitingForSuicide() {
        return !isAlive() && !isReallyDead();
    }

    //death states: 4
    //true: dead and removed from world
    //false: anything else
    private bool isReallyDead()
    out (res) { assert(!res || (physics.lifepower < 0) || physics.dead); }
    body {
        return currentState is wsc.st_dead;
    }

    private bool isSuiciding() {
        return currentState is wsc.st_die;
    }

    //possibly initiate suicide (== delayed dying)
    //return true if suicide was initiated or is in progress
    bool checkSuiciding() {
        if (!isWaitingForSuicide())
            return false;
        if (internal_active) {
            if (!isSuiciding()) {
                assert(!isAlive());
                setState(wsc.st_die);
            }
            return true;
        }
        //xxx not sure what's going on here
        return false;
    }

    //set amount how much the worm is poisoned
    //every turn (or rather on each digestPoison call) the amount is substracted
    //  from the worm's health points
    void poisoned(float val) {
        mPoisoned = val;
        if (graphic)
            graphic.poisoned = val;
    }
    float poisoned() {
        return mPoisoned;
    }

    //if the worm is poisoned, die a little bit more
    void digestPoison() {
        if (poisoned > 0) {
            auto cur = physics.lifepower;
            auto next = cur - poisoned;
            //poison actually can't kill a worm (normally stops at 1 hp)
            //also have to take care of wtfish fractional parts between 0.0-1.0
            if (cur > 0.0f && next < 1.0f)
                next = min(cur, 1.0f); //min: never increase hp
            physics.lifepower = next;
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
        checkWalking();
    }

    bool isBeaming() {
        return (currentState is wsc.st_beaming)
            || (currentState is wsc.st_reverse_beaming) ;
    }

    void beamTo(Vector2f npos) {
        //if (!isSitting())
        //    return; //only can beam when standing
        log.trace("beam to: %s", npos);
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

        if (currentState is wsc.st_pre_getup) {
            //was long enough in this state => play actual getup animation
            if (engine.gameTime.current >= mPreGetupStart + wsc.getupDelay) {
                setState(wsc.st_getup);
            }
        }

        //xxx was too lazy to add something new, so I used getupDelay
        if (engine.gameTime.current >= mLastFlyReset + wsc.getupDelay) {
            //ensure that "fall" is showed, not "slide", when worm is falling
            //"slide" is default to deal with worms sizzling in napalm
            if (getFlyMode(FlyMode.fall) == FlyMode.slide) {
                setFlyMode(FlyMode.fall);
            }
        }
    }

    void jump(JumpMode m) {
        if (wormCanJump()) {
            mJumpMode = m;
            setState(wsc.st_jump_start);
        } else if (currentState is wsc.st_jump_start) {
            //double-click
            if (mJumpMode == JumpMode.normal) mJumpMode = JumpMode.smallBack;
            if (mJumpMode == JumpMode.straightUp) mJumpMode = JumpMode.backFlip;
        }
    }

    //no walk while shooting (or charging)
    private bool wormCanWalk() {
        return currentState.canWalk && !fixed;
    }
    private bool wormCanJump() {
        return currentState.canJump && !fixed;
    }

    private void checkWalking() {
        //hack for correct blowtorch handling (Drill class controls walking)
        if (blowtorchActivated)
            return;
        //stop movement if not possible
        if (!wormCanWalk()) {
            physics.setWalking(Vector2f(0));
        } else {
            physics.setWalking(mMoveVector);
        }
    }

    bool fixed() {
        return mFixed;
    }
    void fixed(bool flags) {
        mFixed = flags;
        checkWalking();
    }

    bool delayedAction() {
        //isBeaming: hack to prevent aborting beam on turn-end
        //  (those wormstate-changing weapons are all a big hack anyway)
        return isBeaming();
    }

    void forceAbort() {
        abortBeaming();
    }

    protected void stateTransition(WormStateInfo from, WormStateInfo to) {
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
                        (myformat("x_gravestone%s", id), true);
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

        checkWalking();
        mRotationOverride = float.nan;
    }

    void setState(WormStateInfo nstate, bool for_end = false) {
        if (nstate is wsc.st_stand &&
            (currentState is wsc.st_fly || currentState is wsc.st_jump ||
            currentState is wsc.st_jump_to_fly))
        {
            if (getFlyMode(FlyMode.fall) == FlyMode.fall) {
                //landing straight => don't slide first
                nstate = wsc.st_getup;
            } else {
                //show slide animation for a small time; this way the animation
                //  looks less stupid if the worm changes quickly between
                //  flying and being glued
                nstate = wsc.st_pre_getup;
                mPreGetupStart = engine.gameTime.current;
            }
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

        log.trace("state %s -> %s", currentState.name, nstate.name);

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

        mLastFlyReset = engine.gameTime.current;
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

        log.trace("force state: %s", nstate.name);

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

    private void setFlyMode(FlyMode m) {
        if (!graphic)
            return;

        if (graphic.currentState is wsc.flyState[m])
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

            mLastFlyReset = engine.gameTime.current;
        }
    }

    private FlyMode getFlyMode(FlyMode def) {
        if (!(currentState is wsc.st_fly && graphic))
            return def;

        //xxx finding "current" is somewhat silly
        FlyMode current = def;
        for (FlyMode idx; idx <= FlyMode.max; idx++) {
            if (graphic.currentState is wsc.flyState[idx]) {
                current = idx;
                break;
            }
        }
        return current;
    }

    override protected void physDamage(float amount, DamageCause type,
        Object cause)
    {
        super.physDamage(amount, type, cause);
        if (type != DamageCause.explosion)
            return;
        if (currentState !is wsc.st_fly) {
            //hit by explosion, abort everything (code below will immediately
            //  correct the state)
            forceAbort();
            setState(wsc.st_stand);
        }

        //xxx possible improvement: measure damage over time, and emit particles
        //  at a corresponding rate
        if (amount > wsc.hitParticleDamage)
            emitParticle(wsc.hitParticle);
    }

    //this function is called each frame with the relative velocity change
    //this means amount is something like the summed impulses over a frame
    private void handleVelocityChange(float amount) {
        auto velocity = physics.velocity.length;

        if (currentState is wsc.st_fly && graphic) {
            FlyMode current = getFlyMode(FlyMode.slide);

            FlyMode newfly = FlyMode.slide;

            if (velocity >= wsc.heavyVelocity) {
                newfly = FlyMode.heavy;
            } else if (velocity >= wsc.rollVelocity) {
                newfly = FlyMode.roll;
            } else if (current == FlyMode.fall) {
                newfly = FlyMode.fall;
            }

            if (newfly < current) {
                //if the new mode is less "heavy" than the old one, only change
                //  it if there was a big velocity change
                //e.g.:
                //- worm in FlyMode.heavy flies a parable and slow down at
                //  the top (velocity=0) => keep heavy
                //- worm in FlyMode.heavy collides with a wall and slows down
                //  => set to lower selected fly mode
                //and this value is just a "heuristic" (i.e. completely random)
                if (amount < wsc.heavyVelocity / 2)
                    newfly = current;
            }

            setFlyMode(newfly);
        }
    }

    override void physImpact(PhysicObject other, Vector2f normal) {
        super.physImpact(other, normal);
        mLastFlyReset = engine.gameTime.current;
    }

    private void physUpdate() {
        if (isSuiciding)
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
                if (physics.isGlued) {
                    //setState may correct state to getup etc.
                    setState(wsc.st_stand);
                } else {
                    setState(wsc.st_fly);
                    //start with this mode; will be corrected later if needed
                    setFlyMode(FlyMode.slide);
                }
            }
        }

        if (currentState is wsc.st_jump && physics.velocity.y > 0) {
            setState(wsc.st_jump_to_fly);
        }

        //probably should be considered a hack for physics not providing more
        //  information
        auto nvel = physics.velocity.length;
        handleVelocityChange(nvel - mPreviousVelocity);
        mPreviousVelocity = nvel;

        //check death (only if game logic doesn't take care of this by setting
        //  delayedDeath to true)
        if (internal_active && !isAlive() && !delayedDeath()) {
            checkSuiciding();
        }
    }
}

//contains custom state attributes for worm sprites
class WormStateInfo {
    string name;

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
    bool canJump = false;       //  ... allowed to jump via jump()
    bool canAim = false;        //can the crosshair be moved/is it displayed
    bool canFire = false;       //can the main weapon be fired

    bool isUnderWater = false;

    bool activity = false;      //if true, WormSprite.activity() returns true

    this (string a_name) {
        name = a_name;
    }
}

//the factories work over the sprite classes, so we need one
class WormSpriteClass : SpriteClass {
    WormStateInfo[string] states;

    float suicideDamage;
    //SequenceObject[] gravestones;
    Vector2f[JumpMode.max+1] jumpStrength;
    Vector2f[] jumpStrengthScript; //no static arrays with Lua wrapper
    float rollVelocity = 0;
    float heavyVelocity = 0;

    float hitParticleDamage = 0;
    ParticleType hitParticle;

    Time getupDelay;

    WormStateInfo st_stand, st_fly, st_walk, st_jet, st_weapon, st_dead,
        st_die, st_drowning, st_beaming, st_reverse_beaming, st_getup,
        st_jump_start, st_jump, st_jump_to_fly, st_rope, st_drill, st_blowtorch,
        st_parachute, st_win, st_frozen, st_unfreeze, st_drowning_frozen,
        st_pre_getup;

    //alias WormSprite.FlyMode FlyMode;

    SequenceState[FlyMode.max+1] flyState;

    this(GameCore e, string r) {
        super(e, r);

        initNoActivityWhenGlued = true;

        WormStateInfo state(string name) {
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
        st_pre_getup = state("pre_getup");
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

    WormStateInfo findState(string name) {
        WormStateInfo* state = name in states;
        if (!state) {
            throwError("state %s not found", name);
        }
        return *state;
    }

    SequenceState findSequenceState(string name,
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
