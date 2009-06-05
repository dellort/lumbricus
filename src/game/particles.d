module game.particles;

import framework.framework;
import framework.timesource;
import common.animation;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.list2;
import utils.random;

import math = tango.math.Math;

/+
Random notes about connecting particles to game objects:
(delete this when done)
(actually, don't read it)
- particles are completely transient, and it shouldn't really matter when all
  particles are suddenly destroyed
- ...destroying all particles happens on game reloading
- ...and because there's a static limit on the number of all particles in the
  system + some more stupid design decisions, particles can be destroyed too
  early even during normal runtime
- for some more stupid reasons, lightweight particles can work as particle
  emitters => transient particles as particle emitters
- so a particle emitter in the game engine should just create a (transient)
  particle, and recreate it as soon as the particle dies or the reference to it
  becomes null
- don't know what to do with those ParticleEffects
- alternatives:
    a) let game objects allocate their own particles (simply embed a Particle
       struct and give the ParticleWorld a pointer to it), the particle could
       be serialized without serializing the rest of the particle engine (as
       long as the particle is not inserted into the particle list)
    b) make it like d0c first wanted: each Particle is a class, and then
       particle emitters could even be derived as separate classes; but you
       still have to care about game saving
    c) delete this file and use the physic engine instead (but physic objects
       are not light weight enough and don't handle drawing; after all this is
       about particles like rockets generate them, and they should be as light
       as possible)
+/

class PSP {
    float gravity = 0f;
    float wind_influence = 0f;
    float explosion_influence = 0f;
    float air_resistance = 0f;
    Time lifetime = Time.Never;
    Animation animation;
    Color color = Color(0); //temporary hack for drawing

    //array of particles that can be emitted (random pick)
    //having emit rate/count for each 
    ParticleEmit[] emit;
    //particles per second
    float emit_rate = 0f;
    //particles max. emit count
    int emit_count = 0;

    //emit when life time is out
    ParticleEmit[] emit_on_death; //again, random pick
    int emit_on_death_count = 0;
}

//static properties for emitting particles
struct ParticleEmit {
    PSP props;
    //multiplied with speed of emitting particle
    float initial_speed = 1.0f;
    //relative (not absolute) probability, that this particle is selected and
    //emitted from PSP.emit
    float emit_probability = 1.0f;
    //angle in radians how much the direction should be changed on emit
    float spread_angle = 0f;
}

//(before ParticleWorld because of
// "Error: struct game.particles.Particle no size yet for forward reference")
struct Particle {
    ObjListNode!(Particle*) node;
    ParticleWorld owner;
    PSP props; //null means dead lol
    Time start;
    Vector2f pos, velocity;

    //state for particle emitter
    int emitted; //number of emitted particles
    float emit_next; //wait time for next particle


    void doinit(ParticleWorld a_owner, PSP a_props) {
        assert(!!a_owner);
        assert(!!a_props);
        owner = a_owner;
        props = a_props;
        start = owner.time.current;
        emitted = 0;
        emit_next = 0f;
        //reasonable defaults of other state that gets set anyway?
        pos.x = pos.y = velocity.x = velocity.y = 0f;
    }

    void draw(Canvas c, float deltaT) {
        assert(!!props);
        auto diff = owner.time.current - start;
        if (diff >= props.lifetime) {
            for (int n = 0; n < props.emit_on_death_count; n++) {
                emitRandomParticle(props.emit_on_death);
            }
            props = null;
            return;
        }

        velocity.y += props.gravity * deltaT;
        velocity.x += owner.windSpeed*props.wind_influence * deltaT;

        pos += velocity * deltaT;
        //Trace.formatln("{} {} {}", pos, velocity, deltaT);

        Animation ani = props.animation;
        if (ani) {
            //die if finished
            if (ani.finished(diff)) {
                props = null;
                return;
            }
            AnimationParams p;
            ani.draw(c, toVector2i(pos), p, diff);
        } else {
            c.drawFilledCircle(toVector2i(pos), 2, props.color);
        }

        //particle emitter here
        if (emitted < props.emit_count) {
            emit_next -= deltaT;
            if (emit_next <= 0f) {
                //new particle
                emitted++;
                //xxx randomize time
                emit_next = 1.0f/props.emit_rate;
                emitRandomParticle(props.emit);
            }
        }
    }

    bool dead() {
        return !props;
    }

    //pick a random particle type from emit[] and create a new particle
    private void emitRandomParticle(ParticleEmit[] emit) {
        if (!owner)
            return;
        //select an entry from props.emit
        float sum = 0f;
        foreach (ref e; emit) {
            sum += e.emit_probability;
        }
        float select = sum * rngShared.nextDouble2();
        sum = 0f;
        foreach (ref e; emit) {
            auto nsum = sum + e.emit_probability;
            if (select >= sum && select < nsum) {
                //actually emit
                auto nvel = velocity*e.initial_speed;
                nvel = nvel.rotated(e.spread_angle *
                    (rngShared.nextDouble() - 0.5f));
                owner.emitParticle(pos, nvel, e.props);
                return;
            }
            sum = nsum;
        }
    }
}


class ParticleWorld {
    private {
        TimeSourcePublic time;
        //could be tuneable (changing the length needs full reinitialization)
        Particle[1000] mParticleAlloc;
        ObjectList!(Particle*, "node") mParticles, mFreeParticles;
        ObjectList!(ParticleEffect, "node") mEffects;
        Time mLastFrame = Time.Never;
    }
    float windSpeed = 0f;

    //protection against float rounding errors when using a too small deltaT
    //this is the smallest deltaT possible... or so
    //not sure if this is a good idea or if it even works
    //probably still better than using a fixed framerate or ignoring the problem
    const float cMinStep = 1e-9f;

    this(TimeSourcePublic t) {
        assert(!!t);
        time = t;
        mEffects = new typeof(mEffects);
        mFreeParticles = new typeof(mFreeParticles);
        mParticles = new typeof(mParticles);

        for (int n = 0; n < mParticleAlloc.length - 1; n++) {
            mFreeParticles.add(&mParticleAlloc[n]);
        }
    }

    void draw(Canvas c) {
        if (mLastFrame == Time.Never) {
            mLastFrame = time.current;
        }

        float deltaT = 0f;

        //check if time diff below a threshhold, and if so, skip frame
        //(add progressed time to next frame, draw this frame with deltaT=0)
        auto now = time.current;
        auto diff = now - mLastFrame;
        auto d = diff.secsf;
        if (d >= cMinStep) {
            deltaT = d;
            mLastFrame = now;
        }

        Particle* cur = mParticles.head;

        while (cur) {
            Particle* next = mParticles.next(cur);

            if (cur.dead()) {
                mParticles.remove(cur);
                mFreeParticles.add(cur);
            } else {
                foreach (eff; mEffects) {
                    eff.applyTo(cur, deltaT);
                }
                cur.draw(c, deltaT);
            }

            cur = next;
        }
    }

    //move from freelist to active list
    //actually never does an actual memory allocation
    //may return null (if all particles are in use)
    Particle* newparticle(PSP props) {
        assert(!!props);
        Particle* cur = mFreeParticles.head;
        if (cur) {
            mFreeParticles.remove(cur);
        } else {
            //hijack old particles
            //start at begin, so that older particles get scratched first
            cur = mParticles.head();
            if (!cur)
                return null;
            mParticles.remove(cur);
        }
        mParticles.add(cur);
        cur.doinit(this, props);
        return cur;
    }

    void emitParticle(Vector2f pos, Vector2f vel, PSP props) {
        Particle* p = newparticle(props);
        if (!p)
            return;
        p.pos = pos;
        p.velocity = vel;
    }

    void explosion(Vector2f pos, float vAdd = 100f, float radius = 50f) {
        foreach (Particle* p; mParticles) {
            float dist = (p.pos - pos).length;
            if (dist > radius || dist < float.epsilon)
                continue;
            p.velocity += p.props.explosion_influence * (p.pos-pos)/dist
                * (radius - dist) * vAdd;
        }
    }
}

class ParticleEffect {
    ObjListNode!(typeof(this)) node;
    private {
        ParticleWorld mOwner;
    }

    Vector2f pos;

    this(ParticleWorld owner) {
        mOwner = owner;
        mOwner.mEffects.add(this);
    }

    abstract void applyTo(Particle* p, float deltaT);

    void remove() {
        mOwner.mEffects.remove(this);
        mOwner = null;
    }
}

class ParticleGravity : ParticleEffect {
    float accel = 100f;
    float radius = 50f;

    this(ParticleWorld owner) {
        super(owner);
    }

    override void applyTo(Particle* p, float deltaT) {
        float dist = (p.pos - pos).length;
        if (dist > radius || dist < float.epsilon)
            return;
        p.velocity += accel * (pos - p.pos)/dist * deltaT * (radius - dist);
    }
}

debug:

import common.task;
import gui.widget;
import gui.wm;

class TestTask : Task {
    ParticleWorld mWorld;
    Particle mEmitter;
    TimeSource mTS;

    class Drawer : Widget {
        this() {
        }

        override void onKeyEvent(KeyInfo info) {
            if (info.isMouseButton && info.isDown)
                mWorld.explosion(toVector2f(mousePos()));
        }

        override void onDraw(Canvas c) {
            mTS.update();
            //mEmitter.draw(c, mWorld.time.difference.secfs); //args
            mWorld.draw(c);
        }
    }

    this(TaskManager tm, char[] args = "") {
        super(tm);

        mTS = new TimeSource("particles");
        mWorld = new ParticleWorld(mTS);
        mWorld.windSpeed = 2f;

        //init particle business
        auto x = new PSP;
        x.color = Color(1,0,0);
        x.lifetime = timeSecs(1);
        auto y = new PSP;
        y.wind_influence = 0.6;
        y.explosion_influence = 0.01f;
        y.gravity = 0f;
        y.color = Color(0,0,1);
        y.lifetime = timeSecs(3);
        y.emit_on_death ~= ParticleEmit(x, 2, 1, math.PI*2);
        y.emit_on_death_count = 6;
        auto z = new PSP;
        z.wind_influence = 0.8;
        z.explosion_influence = 0.005f;
        z.gravity = 10f;
        z.emit_rate = 2;
        z.emit_count = int.max;
        z.emit ~= ParticleEmit(y, 0.7f, 1.0f, math.PI/180*60);
        for (int n = 0; n < 10; n++) {
            mWorld.emitParticle(Vector2f(50,50), Vector2f(0.2,0.2), z);
        }
        //

        auto drawer = new Drawer();

        gWindowManager.createWindow(this, drawer, "Particle test",
            Vector2i(500, 500));
    }

    static this() {
        TaskFactory.register!(typeof(this))("particletest");
    }
}
