module game.sprite;

import framework.framework;
import game.events;
import game.game;
import game.gobject;
import game.sequence;
import game.temp : GameZOrder;
import game.gfxset;
import game.particles;
import net.marshal : Hasher;
import physics.world;

//temporary?
import game.controller_events;

import utils.vector2;
import utils.rect2;
import utils.misc;
import utils.log;
import utils.math;
import tango.math.Math : abs, PI;
import utils.time;

private LogStruct!("game.sprite") log;

//version = RotateDebug;

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

    this(GameEngine a_engine, SpriteClass a_type) {
        super(a_engine, a_type.name);
        mType = a_type;
        assert(!!mType);

        noActivityWhenGlued = type.initNoActivityWhenGlued;

        physics = new PhysicObject();
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

    void activate(Vector2f pos) {
        if (physics.dead || mWasActivated)
            return;
        mWasActivated = true;
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
            engine.physicworld.add(physics);
            auto member = engine.controller ?
                engine.controller.memberFromGameObject(this, true) : null;
            auto owner = member ? member.team : null;
            graphic = new Sequence(engine, owner ? owner.teamColor : null);
            graphic.zorder = GameZOrder.Objects;
            if (auto st = type.getInitSequenceState())
                graphic.setState(st);
            engine.scene.add(graphic);
            physics.checkRotation();
            updateAnimation();
        }
        updateParticles();
    }

    override bool activity() {
        return internal_active && !(physics.isGlued && noActivityWhenGlued);
    }

    protected void physImpact(PhysicBase other, Vector2f normal) {
        //it appears no code uses the "other" parameter
        OnSpriteImpact.raise(this, normal);
    }

    //normal always points away from other object
    final void doImpact(PhysicBase other, Vector2f normal) {
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
        log("exterminate in deathzone: {}", type.name);
        kill();
    }

    override void onKill() {
        super.onKill();
        internal_active = false;
        if (!physics.dead) {
            physics.dead = true;
            log("really die: {}", type.name);
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
        mParticleEmitter.update(engine.callbacks.particleEngine);
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

    override void simulate(float deltaT) {
        super.simulate(deltaT);

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
        version (RotateDebug) {
            auto p = toVector2i(physics.pos);

            auto r = Vector2f.fromPolar(30, physics.rotation);
            c.drawLine(p, p + toVector2i(r), Color(1,0,0));

            auto n = Vector2f.fromPolar(30, physics.ground_angle);
            c.drawLine(p, p + toVector2i(n), Color(0,1,0));

            auto l = Vector2f.fromPolar(30, physics.lookey_smooth);
            c.drawLine(p, p + toVector2i(l), Color(0,0,1));
        }
    }
}

class SpriteClass {
    GfxSet gfx;
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

    this (GfxSet gfx, char[] regname) {
        this.gfx = gfx;
        name = regname;

        initPhysic = new POSP();
    }

    Sprite createSprite(GameEngine engine) {
        return new Sprite(engine, this);
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

