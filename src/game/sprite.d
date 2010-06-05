module game.sprite;

import framework.framework;
import game.core;
import game.events;
import game.sequence;
import game.temp : GameZOrder;
import game.particles;
import net.marshal; // : Hasher;
import physics.all;

import utils.vector2;
import utils.rect2;
import utils.misc;
import utils.log;
import utils.math;
import tango.math.Math : abs, PI;
import utils.time;


//called when sprite is finally dead (for worms: when done blowing up)
alias DeclareEvent!("sprite_die", Sprite) OnSpriteDie;
//on Sprite.waterStateChange()
alias DeclareEvent!("sprite_waterstate", Sprite) OnSpriteWaterState;
//with Sprite.activate()
alias DeclareEvent!("sprite_activate", Sprite) OnSpriteActivate;
//whenever the glue status changes (checked/called every frame)
alias DeclareEvent!("sprite_glue_changed", Sprite) OnSpriteGlueChanged;
//see Sprite.exceedVelocity
alias DeclareEvent!("sprite_exceed_velocity", Sprite) OnSpriteExceedVelocity;
//not called by default; see Sprite.notifyAnimationEnd
alias DeclareEvent!("sprite_animation_end", Sprite) OnSpriteAnimationEnd;
//physics.lifepower <= 0
alias DeclareEvent!("sprite_zerohp", Sprite) OnSpriteZeroHp;
//victim, cause, type, damage
//  cause can be null (e.g. for fall damage)
alias DeclareEvent!("sprite_damage", Sprite, GameObject, DamageCause,
    float) OnDamage;
//well whatever this is
//should be avoided in scripting; the Vector2f will allocate a table
alias DeclareEvent!("sprite_impact", Sprite, PhysicObject, Vector2f)
    OnSpriteImpact;

//object which represents a PhysicObject and an animation on the screen
//also provides loading from ConfigFiles
class Sprite : GameObject {
    private {
        //transient for savegames, Particle created from StaticStateInfo.particle
        //all state associated with this variable is non-deterministic and must not
        //  have any influence on the rest of the game state
        //xxx: move to Sequence, as soon as this is being rewritten
        ParticleEmitter mParticleEmitter;
        ParticleType mCurrentParticle;

        bool mWasActivated;
        bool mOldGlueState;
        bool mIsUnderWater, mWaterUpdated;
        bool mZeroHpCalled;
    }
    protected SpriteClass mType;

    PhysicObject physics;
    //attention: can be null if object inactive
    //if it gets active again it's recreated again LOL
    Sequence graphic;

    //if false, sprite is considered active if visible/alive
    //if true, sprite is considered active only if it's moving (== unglued)
    bool noActivityWhenGlued;

    //if velocity is higher than this value, the OnSpriteExceedVelocity event is
    //  triggered, and exceedVelocity is reset to infinity
    float exceedVelocity = float.infinity;

    //if true, the OnSpriteAnimationEnd event is called when the Sequence's
    //  readyflag is true; notifyAnimationEnd is reset to false as well
    bool notifyAnimationEnd;

    this(SpriteClass a_type) {
        super(a_type.engine, a_type.name);
        mType = a_type;
        assert(!!mType);

        noActivityWhenGlued = type.initNoActivityWhenGlued;

        physics = new PhysicObjectCircle();
        physics.backlink = this;
        physics.lifepower = type.initialHp;

        physics.posp = type.initPhysic;

        physics.onDie = &physDie;
        physics.onDamage = &physDamage;

        setParticle(type.initParticle);
    }

    SpriteClass type() {
        return mType;
    }

    //if it's placed in the world (physics, animation)
    bool visible() {
        return internal_active;
    }

    void activate(Vector2f pos, Vector2f velocity = Vector2f(0)) {
        if (physics.dead || mWasActivated)
            return;
        mWasActivated = true;
        physics.setInitialVelocity(velocity);
        setPos(pos);
        internal_active = true;

        OnSpriteActivate.raise(this);
    }

    //force position
    void setPos(Vector2f pos) {
        physics.setPos(pos, false);
        if (graphic)
            fillAnimUpdate();
    }

    override protected void updateInternalActive() {
        if (graphic) {
            graphic.remove();
            graphic = null;
        }
        physics.remove = true;
        if (internal_active) {
            engine.physicWorld.add(physics);
            graphic = new Sequence(engine, engine.teamThemeOf(this));
            graphic.zorder = GameZOrder.Objects;
            if (auto st = type.getInitSequenceState())
                graphic.setState(st);
            engine.scene.add(graphic);
            updateAnimation();
        }
        updateParticles();
    }

    override bool activity() {
        return internal_active && !(physics.isGlued && noActivityWhenGlued);
    }

    protected void physImpact(PhysicObject other, Vector2f normal) {
        //it appears no code uses the "other" parameter
        OnSpriteImpact.raise(this, other, normal);
    }

    //normal always points away from other object
    final void doImpact(PhysicObject other, Vector2f normal) {
        physImpact(other, normal);
    }

    protected void physDamage(float amount, DamageCause type, Object cause) {
        auto goCause = cast(GameObject)cause;
        assert(!cause || !!goCause, "damage by non-GameObject?");
        //goCause can be null (e.g. for fall damage)
        OnDamage.raise(this, goCause, type, amount);
    }

    protected void physDie() {
        //assume that's what we want
        if (!internal_active)
            return;
        kill();
    }

    final void exterminate() {
        //_always_ die completely (or are there exceptions?)
        engine.log.trace("exterminate in deathzone: {}", type.name);
        kill();
    }

    override void onKill() {
        super.onKill();
        internal_active = false;
        if (!physics.dead) {
            physics.dead = true;
            engine.log.trace("really die: {}", type.name);
            OnSpriteDie.raise(this);
        }
    }

    //update animation to physics status etc.
    final void updateAnimation() {
        if (!graphic)
            return;

        fillAnimUpdate();

        //this is needed to fix a 1-frame error with worms - when you walk, the
        //  weapon gets deselected, and without this code, the weapon icon
        //  (normally used for weapons without animation) can be seen for a
        //  frame or so
        graphic.simulate();
    }

    protected void fillAnimUpdate() {
        assert(!!graphic);
        graphic.position = physics.pos;
        graphic.velocity = physics.velocity;
        graphic.rotation_angle = physics.lookey_smooth;
        graphic.lifepower = physics.lifepower;
        if (type.initialHp == float.infinity ||
            physics.lifepower == float.infinity ||
            type.initialHp == 0f)
        {
            graphic.lifePercent = 1.0f;
        } else {
            graphic.lifePercent = max(physics.lifepower / type.initialHp, 0f);
        }
    }

    protected void updateParticles() {
        mParticleEmitter.active = internal_active();
        mParticleEmitter.current = mCurrentParticle;
        mParticleEmitter.pos = physics.pos;
        mParticleEmitter.velocity = physics.velocity;
        mParticleEmitter.update(engine.particleWorld);
    }

    final void setParticle(ParticleType pt) {
        if (mCurrentParticle is pt)
            return;
        mCurrentParticle = pt;
        updateParticles();
    }

    //called by GameEngine on each frame if it's really under water
    //xxx: TriggerEnter/TriggerExit was more beautiful, so maybe bring it back
    final void setIsUnderWater() {
        mWaterUpdated = true;

        if (mIsUnderWater)
            return;
        mIsUnderWater = true;
        waterStateChange();
    }

    final bool isUnderWater() {
        return mIsUnderWater;
    }

    protected void waterStateChange() {
        OnSpriteWaterState.raise(this);
    }

    override void simulate() {
        super.simulate();

        bool glue = physics.isGlued;
        if (glue != mOldGlueState) {
            mOldGlueState = glue;
            OnSpriteGlueChanged.raise(this);
        }

        if (physics.velocity.length >= exceedVelocity) {
            exceedVelocity = float.infinity;
            OnSpriteExceedVelocity.raise(this);
        }

        if (graphic) {
            fillAnimUpdate();

            //xxx: added with sequence-messup
            graphic.simulate();

            if (graphic.readyflag && notifyAnimationEnd) {
                notifyAnimationEnd = false;
                OnSpriteAnimationEnd.raise(this);
            }
        }

        if (!mWaterUpdated && mIsUnderWater) {
            mIsUnderWater = false;
            waterStateChange();
        }
        mWaterUpdated = false;

        if (physics.lifepower <= 0) {
            if (!mZeroHpCalled)
                OnSpriteZeroHp.raise(this);
            mZeroHpCalled = true;
        }

        updateParticles();
    }

    override void hash(Hasher hasher) {
        super.hash(hasher);
        hasher.hash(physics.pos);
        hasher.hash(physics.velocity);
    }

    override void debug_draw(Canvas c) {
        super.debug_draw(c);

        //just draw a small circle to signal that a sprite is here
        //the physic object is drawn by the physic engine's debug_draw

        auto p = toVector2i(physics.pos);
        c.drawCircle(p, 3, Color(1,1,1));
    }

    char[] toString() {
        return myformat("[Sprite 0x{:x} {} at {}]", cast(void*)this, type.name,
            physics.pos);
    }
}

class SpriteClass {
    GameCore engine;
    char[] name;

    SequenceType sequenceType;
    //can be null (then sequenceType.normalState is used)
    //if non-null, sequenceType is ignored (remember that SequenceType just
    //  provides a namespace for sequenceStates anyway)
    //see getInitSequenceState()
    SequenceState sequenceState;

    //those are just "utility" properties to simplify initialization
    //in most cases, it's all what one needs
    float initialHp = float.infinity;
    POSP initPhysic;
    ParticleType initParticle;
    bool initNoActivityWhenGlued = false;

    this (GameCore a_core, char[] a_name) {
        engine = a_core;
        name = a_name;

        initPhysic = new POSP();
        //be friendly
        initPhysic.collisionID = engine.physicWorld.collide.find("none");
    }

    Sprite createSprite() {
        return new Sprite(this);
    }

    //may return null
    SequenceState getInitSequenceState() {
        auto state = sequenceState;
        if (!state && sequenceType)
            state = sequenceType.normalState;
        return state;
    }
    SequenceType getInitSequenceType() {
        if (sequenceState && sequenceState.owner)
            return sequenceState.owner;
        return sequenceType;
    }

    char[] toString() { return "SpriteClass["~name~"]"; }
}

