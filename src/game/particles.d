module game.particle;

import framework.timesource;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.list2;

class ParticleWorld {
    private {
        TimeSource time;
        List2!(Particle) mParticles;
        List2!(ParticleEffect) mEffects;
    }
    float windSpeed = 0f;

    this(TimeSource t) {
        assert(!!t);
        time = t;
        mParticles = new typeof(mParticles);
        mEffects = new typeof(mEffects);
    }

    void simulate() {
        foreach (p; mParticles) {
            float deltaT = time.difference.secsf;
            foreach (eff; mEffects) {
                eff.applyTo(p, deltaT);
            }
            p.simulate(deltaT);
        }
    }

    void draw(Canvas c) {
        foreach (p; mParticles) {
            p.draw(c);
        }
    }
}

//use ConfigNode.getValue!(PSP) to load
struct PSP {
    float gravity = 0f;
    float wind_influence = 0f;
    float explosion_influence = 0f;
    float air_resistance = 0f;
    Time lifetime;
    Resource
}

class Particle {
    Vector2f pos, velocity;
    Time start;
    PSP props;
    Particle parent;

    private {
        ParticleWorld mOwner;
        ListNode particle_node;
    }

    this(ParticleWorld owner) {
        assert(!!owner);
        mOwner = owner;
        particle_node = owner.mParticles.add(this);
        start = owner.time.current;
    }

    void simulate(float deltaT) {
        if (start + props.lifetime > owner.time.current) {
            remove();
            return;
        }
        if (parent) {
            if (parent.dead) {
                remove();
                return;
            }
            pos = parent.pos;
            velocity = parent.velocity;
        } else {
            velocity.y += props.gravity * deltaT;
            velocity.x += owner.windSpeed*props.wind_influence * deltaT;

            pos += velocity * deltaT;
        }
    }

    void draw(Canvas c) {
    }

    bool dead() {
        return !particle_node;
    }

    void remove() {
        if (dead)
            return;
        assert(!!particle_node);
        owner.mParticles.remove(particle_node);
        particle_node = null;
    }
}

class ParticleEffect : Particle {
    private {
        ListNode effects_node;
    }

    this(ParticleWorld owner) {
        super(owner);
        effects_node = owner.mEffects.add(this);
    }

    abstract void applyTo(Particle p, float deltaT);

    override void remove() {
        super.remove();
        assert(!!effects_node);
        owner.mEffects.remove(effects_node);
    }
}

class ParticleExplosion : ParticleEffect {
    float vAdd = 100f;
    float radius = 50f;

    this(ParticleWorld owner) {
        super(owner);
    }

    void applyTo(Particle p, float deltaT) {
        float dist = (p.pos - pos).length;
        if (dist > radius || dist < float.epsilon)
            return;
        p.velocity += p.props.explosionInfluence * (p.pos-pos)/dist
            * (radius - dist) * vAdd;
    }
}

class ParticleGravity : ParticleEffect {
    float accel = 100f;
    float radius = 50f;

    this(ParticleWorld owner) {
        super(owner);
    }

    void applyTo(Particle p, float deltaT) {
        float dist = (p.pos - pos).length;
        if (dist > radius || dist < float.epsilon)
            return;
        p.velocity += accel * (pos - p.pos)/dist * deltaT * (radius - dist);
    }
}
