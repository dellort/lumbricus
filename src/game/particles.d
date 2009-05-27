module game.particle;

import framework.framework;
import framework.timesource;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.list2;

class ParticleWorld {
    private {
        TimeSource time;
        //could be tuneable, but changing the length needs full reinitialization
        Particle[1000] mParticles;
        Particle* first, last, freelist;
        List2!(ParticleEffect) mEffects;
    }
    float windSpeed = 0f;

    this(TimeSource t) {
        assert(!!t);
        time = t;
        mEffects = new typeof(mEffects);

        //init freelist, blah.
        freelist = &mParticles[0];
        for (int n = 0; n < mParticles.length - 1; n++) {
            mParticles[n].next = &mParticles[n+1];
        }
    }

    void draw(Canvas c) {
        float deltaT = time.difference.secsf;
        //xxx: check if time diff below a threshhold, and if so, skip frame
        //     (add progressed time to next frame, draw this frame with deltaT=0)

        Particle* cur = first;
        Particle** pprev = &cur;

        while (cur) {
            Particle* next = cur.next;
            if (cur.dead()) {
                //remove from list, put into freelist
                (*pprev).next = next;
                cur.next = freelist;
                freelist = cur;
                if (cur is first)
                    first = next;
                if (cur is last)
                    last = *pprev;
            } else {
                foreach (eff; mEffects) {
                    eff.applyTo(p, deltaT);
                }
                p.draw(c, deltaT);
            }

            pprev = &cur.next;
            cur = next;
        }

        last = *pprev;
    }

    //move from freelist to active list
    //actually never allocates a new particle
    //may return null
    Particle* newparticle(PSP* props) {
        assert(!!props);
        Particle* cur = freelist;
        if (cur) {
            //allocate from freelist
            freelist = freelist.next;
            assert(!last.next);
            last.next = cur;
            cur.next = null;
            if (first is last)
                first = cur;
            last = cur;
        } else {
            //could hijack old particles
            return null;
        }
        cur.init(this, props);
        return cur;
    }

    void emitParticle(Vector2f pos, Vector2f vel, PSP* props) {
        Particle* p = newparticle(props);
        if (!p)
            return;
        p.pos = pos;
        p.velocity = vel;
    }
}

//use ConfigNode.getValue!(PSP) to load
struct PSP {
    float gravity = 0f;
    float wind_influence = 0f;
    float explosion_influence = 0f;
    float air_resistance = 0f;
    Time lifetime;
    Animation animation;

    //array of particles that can be emitted (random pick)
    PSP*[] emit;
    //particles per second
    float emit_rate;
    //particles max. emit count
    int emit_count;
}

struct Particle {
    Particle* next; //next particle or freelist
    ParticleWorld owner;
    PSP* props; //null means dead lol
    Time start;
    Vector2f pos, velocity;

    //state for particle emitter
    int emitted; //number of emitted particles
    float emit_next; //wait time for next particle


    void init(ParticleWorld a_owner, PSP* a_props) {
        assert(!!owner);
        owner = a_owner;
        props = a_props;
        start = owner.time.current;
        emitted = 0;
        emit_next = 0f;
    }

    void draw(Canvas c, float deltaT) {
        assert(!!props);
        auto diff = owner.time.current - start;
        if (diff >= props.lifetime) {
            props = null;
            return;
        }

        velocity.y += props.gravity * deltaT;
        velocity.x += owner.windSpeed*props.wind_influence * deltaT;

        pos += velocity * deltaT;

        Animation ani = props.animation;
        if (ani) {
            //die if finished
            if (ani.finished(diff)) {
                props = null;
                return;
            }
            AnimationParams p;
            ani.draw(c, toVector2i(pos), p, diff);
        }

        //particle emitter here
        if (emitted < props.emit_count) {
            emit_next -= deltaT;
            if (emit_next <= 0f) {
                //new particle
                emitted++;
                if (owner) {
                    owner.
                }
            }
        }
    }

    bool dead() {
        return !!props;
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

    void applyTo(ref Particle p, float deltaT) {
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

    void applyTo(ref Particle p, float deltaT) {
        float dist = (p.pos - pos).length;
        if (dist > radius || dist < float.epsilon)
            return;
        p.velocity += accel * (pos - p.pos)/dist * deltaT * (radius - dist);
    }
}
