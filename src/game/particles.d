module game.particles;

import framework.framework;
import framework.timesource;
import common.animation;
import common.resset;
import utils.misc;
import utils.vector2;
import utils.time;
import utils.configfile;
import utils.list2;
import utils.random;

import math = tango.math.Math;


class ParticleType {
    float gravity = 0f;
    float wind_influence = 0f;
    float explosion_influence = 0f;
    float air_resistance = 0f;

    //bubble movement (in x direction)
    //the value is the highest velocity used to move into the x direction
    //xxx: this is a big bogus, because the amplitude depends from y speed
    float bubble_x = 0f;
    //size of bubble arc
    float bubble_x_h = 0f;

    Time lifetime = Time.Never;
    Animation animation;
    Color color = Color(0,0,0,0); //temporary hack for drawing

    //array of particles that can be emitted (random pick)
    ParticleEmit[] emit;
    //seconds between emitting a new particle
    float emit_delay = 0f;
    //add this*rnd(0,1) to emit_delay
    float emit_delay_add_random = 0f;
    //particles max. emit count
    int emit_count = 0;

    //emit when life time is out
    ParticleEmit[] emit_on_death; //again, random pick
    int emit_on_death_count = 0;

    void read(ResourceSet res, ConfigNode node) {
        //sorry about this
        //we need a better way to read stuff from configfiles

        gravity = node.getValue("gravity", gravity);
        wind_influence = node.getValue("wind_influence", wind_influence);
        explosion_influence = node.getValue("explosion_influence",
            explosion_influence);
        air_resistance = node.getValue("air_resistance", air_resistance);
        bubble_x = node.getValue("bubble_x", bubble_x);
        bubble_x_h = node.getValue("bubble_x_h", bubble_x_h);
        color = node.getValue("color", color);
        air_resistance = node.getValue("air_resistance", air_resistance);
        emit_delay = node.getValue("emit_delay", emit_delay);
        emit_delay_add_random = node.getValue("emit_delay_add_random",
            emit_delay_add_random);
        emit_on_death_count = node.getValue("emit_on_death_count",
            emit_on_death_count);
        //includes dumb special case
        if (node["emit_count"] == "max") {
            emit_count = emit_count.max;
        } else {
            emit_count = node.getValue("emit_count", emit_count);
        }
        //conversion to float destroys Time.Never default value
        float t = node.getValue("lifetime", float.nan);
        if (t == t)
            lifetime = timeSecs(t);

        auto ani = node["animation"];
        if (ani.length) {
            animation = res.get!(Animation)(ani);
        }

        void read_sub(char[] name, ref ParticleEmit[] t) {
            auto sub = node.getSubNode(name);
            foreach (ConfigNode s; sub) {
                ParticleEmit e;
                //read both ParticleEmit and ParticleEmit.particle from the same
                //node, because the additional nesting would be annoying
                e.initial_speed = s.getValue("initial_speed", e.initial_speed);
                e.emit_probability = s.getValue("emit_probability",
                    e.emit_probability);
                e.spread_angle = s.getValue("spread_angle", e.spread_angle);
                e.offset = s.getValue("offset", e.offset);
                auto x = new ParticleType();
                x.read(res, s);
                e.particle = x;
                t ~= e;
            }
        }

        read_sub("emit", emit);
        read_sub("emit_on_death", emit_on_death);
    }
}

//static properties for emitting particles
struct ParticleEmit {
    ParticleType particle;
    //multiplied with speed of emitting particle
    float initial_speed = 1.0f;
    //relative (not absolute) probability, that this particle is selected and
    //emitted from ParticleType.emit
    float emit_probability = 1.0f;
    //angle in radians how much the direction should be changed on emit
    float spread_angle = 0f;
    //move emit position by this value along velocity direction
    float offset = 0f;
}

//(before ParticleWorld because of
// "Error: struct game.particles.Particle no size yet for forward reference")
struct Particle {
    ObjListNode!(Particle*) node;
    ParticleWorld owner;
    ParticleType props; //null means dead lol
    Time start;
    Vector2f pos, velocity;

    //multipurpose random value (can be used for anything you want)
    //constant over lifetime of the particle, initialized with nextDouble()
    float random;

    //state for particle emitter
    int emitted; //number of emitted particles
    float emit_next; //wait time for next particle


    void doinit(ParticleWorld a_owner, ParticleType a_props) {
        assert(!!a_owner);
        assert(!!a_props);
        owner = a_owner;
        props = a_props;
        start = owner.time.current;
        emitted = 0;
        emit_next = 0f;
        random = rngShared.nextDouble();
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

        Vector2f add = velocity * deltaT;

        if (props.bubble_x > 0) {
            //acceleration (?) simply depends from y coordinate
            //sin() also does the modulo operation needed here
            //adding random just changes the phase (for each particle)
            add.x += math.sin((pos.y/props.bubble_x_h+random)*math.PI*2)
                * props.bubble_x * add.y;
        }

        pos += add;
        //Trace.formatln("{} {} {}", pos, velocity, deltaT);

        Animation ani = props.animation;
        if (ani) {
            //die if finished
            if (ani.finished(diff)) {
                kill();
                return;
            }
            AnimationParams p;
            ani.draw(c, toVector2i(pos), p, diff);
        }

        if (props.color.a > 0) {
            c.drawFilledCircle(toVector2i(pos), 2, props.color);
        }

        //particle emitter here
        if (emitted < props.emit_count) {
            emit_next -= deltaT;
            if (emit_next <= 0f) {
                //new particle
                emitted++;
                //xxx randomize time
                emit_next = props.emit_delay
                    + rngShared.nextDouble() * props.emit_delay_add_random;
                emitRandomParticle(props.emit);
            }
        }
    }

    bool dead() {
        return !props;
    }

    void kill() {
        //NOTE: will be removed from particle list in the next iteration
        props = null;
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
                auto at = pos;
                auto nvel = velocity*e.initial_speed;
                nvel = nvel.rotated(e.spread_angle *
                    (rngShared.nextDouble() - 0.5f));
                if (e.offset != 0f) {
                    //xxx I realize I'd need the emitter rotation, not velocity
                    // OTOH, the code that creates the emitter should set the
                    // emitter position correctly in the first place, and
                    // ParticleEmit.offset is only a hack to get around this!
                    auto dir = velocity.normal;
                    if (!dir.isNaN()) {
                        at += dir * e.offset;
                    }
                }
                owner.emitParticle(at, nvel, e.particle);
                return;
            }
            sum = nsum;
        }
    }
}


class ParticleWorld {
    private {
        TimeSource mTS; //only !null if no external timesource
        TimeSourcePublic time;
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

    this(TimeSourcePublic t = null) {
        if (!t) {
            mTS = new TimeSource("particles");
            t = mTS;
        }
        time = t;
        mEffects = new typeof(mEffects);
        mFreeParticles = new typeof(mFreeParticles);
        mParticles = new typeof(mParticles);

        reinit();
    }

    void reinit(int particle_count = 50000) {
        //right now changing the length needs full reinitialization
        //seems one could also simply add particles
        //destroy
        foreach (p; mParticles) {
            p.kill();
        }
        mParticles.clear();
        mFreeParticles.clear();
        //alloc new
        Particle[] alloc;
        alloc.length = particle_count;
        for (int n = 0; n < alloc.length; n++) {
            mFreeParticles.add(&alloc[n]);
        }
    }

    void draw(Canvas c) {
        if (mTS) {
            mTS.update();
        }

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
    Particle* newparticle(ParticleType props) {
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

    Particle* createParticle(ParticleType props) {
        return newparticle(props);
    }

    void emitParticle(Vector2f pos, Vector2f vel, ParticleType props) {
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
        auto x = new ParticleType;
        x.color = Color(1,0,0);
        x.lifetime = timeSecs(1);
        auto y = new ParticleType;
        y.wind_influence = 0.6;
        y.explosion_influence = 0.01f;
        y.gravity = 0f;
        y.color = Color(0,0,1);
        y.lifetime = timeSecs(3);
        y.emit_on_death ~= ParticleEmit(x, 2, 1, math.PI*2);
        y.emit_on_death_count = 6;
        auto z = new ParticleType;
        z.wind_influence = 0.8;
        z.explosion_influence = 0.005f;
        z.gravity = 10f;
        z.emit_delay = 0.5;
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
