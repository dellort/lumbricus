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
import utils.randval;

import math = tango.math.Math;
import cstdlib = tango.stdc.stdlib;

debug import common.common;
debug import utils.perf;

//use C memory for particles (is lighter on the GC)
version = CMemory;


class ParticleType {
    RandomFloat gravity = {0f, 0f};
    RandomFloat wind_influence = {0f, 0f};
    float explosion_influence = 0f;
    float air_resistance = 0f;

    //bubble movement (in x direction)
    //the value is the highest velocity used to move into the x direction
    //xxx: this is a big bogus, because the amplitude depends from y speed
    float bubble_x = 0f;
    //size of bubble arc
    float bubble_x_h = 0f;

    //particle can only exist underwater (e.g. bubbles)
    bool underwater;

    Time lifetime = Time.Never;
    //list of available animations, one is randomly selected
    Animation[] animation;
    Color color = Color(0,0,0,0); //temporary hack for drawing
    //if non-null, play one of those
    //unless sound is null or sound_repeat is true, the particle lives until
    //  the sound is done playing
    Sample[] sound;
    bool sound_looping;

    //array of particles that can be emitted (random pick)
    ParticleEmit[] emit;
    //seconds between emitting a new particle
    RandomValue!(Time) emit_interval = {Time.Null, Time.Null};
    //seconds until emitting starts
    RandomValue!(Time) emit_delay = {Time.Null, Time.Null};
    //particles max. emit count
    int emit_count = 0;

    //emit when life time is out
    ParticleEmit[] emit_on_death; //again, random pick
    int emit_on_death_count = 0;

    //get a list of resource T, but also accept a single item if node contains
    //  a value only, or if the node is empty
    private static T[] get_res_list(T)(ResourceSet res, ConfigNode node) {
        T[] list;
        if (node.value.length) {
            list = [res.get!(T)(node.value)];
        } else if (node.count) {
            char[][] items = node.getCurValue!(char[][]);
            foreach (id; items) {
                list ~= res.get!(T)(id);
            }
        }
        return list;
    }

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
        underwater = node.getValue("underwater", underwater);
        color = node.getValue("color", color);
        air_resistance = node.getValue("air_resistance", air_resistance);
        emit_interval = node.getValue("emit_interval", emit_interval);
        emit_delay = node.getValue("emit_delay", emit_delay);
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

        animation = get_res_list!(Animation)(res, node.getSubNode("animation"));
        sound = get_res_list!(Sample)(res, node.getSubNode("sound"));

        void read_sub(char[] name, ref ParticleEmit[] t) {
            auto sub = node.getSubNode(name);
            foreach (ConfigNode s; sub) {
                ParticleEmit e;
                //read both ParticleEmit and ParticleEmit.particle from the same
                //node, because the additional nesting would be annoying
                e.initial_speed = s.getValue("initial_speed", e.initial_speed);
                e.absolute_speed = s.getValue("absolute_speed",
                    e.absolute_speed);
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

        sound_looping = node.getValue("sound_looping", sound_looping);

        read_sub("emit", emit);
        read_sub("emit_on_death", emit_on_death);
    }
}

//static properties for emitting particles
struct ParticleEmit {
    ParticleType particle;
    //multiplied with speed of emitting particle
    float initial_speed = 1.0f;
    float absolute_speed = 0f;
    //relative (not absolute) probability, that this particle is selected and
    //emitted from ParticleType.emit
    float emit_probability = 1.0f;
    //angle in degrees how much the direction should be changed on emit
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
    float gravity, windInfluence;
    Animation anim;
    Source sound;

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
        emit_next = props.emit_delay.sample(rngShared).secsf;
        gravity = props.gravity.sample(rngShared);
        windInfluence = props.wind_influence.sample(rngShared);
        random = rngShared.nextDouble();
        anim = rngShared.pickArray(props.animation);
        Sample snd = rngShared.pickArray(props.sound);
        if (!snd) {
            sound = null;
        } else {
            sound = snd.play();
            sound.looping = props.sound_looping;
        }
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

        velocity.y += gravity * deltaT;
        velocity.x += owner.windSpeed*windInfluence * deltaT;

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

        if (props.underwater && pos.y < owner.waterLine) {
            kill();
            return;
        }

        //particle lifetime rules:
        //- if props.lifetime has elapsed, particle always dies
        //  (but note that lifetime by default is infinite)
        //- particle dies, unless:
        //  - animation or sound is active
        //  - both animation and sound are disabled
        //    (in this case, it's assumed particle does other work: like being
        //     drawn with a solid color, or emitting particles)
        bool sound_active = false;
        bool anim_active = false;

        if (sound && sound.state() != PlaybackState.stopped) {
            sound_active = true;
            //update position
            Rect2i area = owner.mViewArea;
            Vector2i size = area.size;
            //only when valid (and setViewArea() was called)
            if (size.x & size.y) {
                auto rel = pos - toVector2f(area.p1);
                sound.info.position = (rel / toVector2f(size)) * 2.0f
                    - Vector2f(1);
            }
        }

        if (anim && (anim.repeat || !anim.finished(diff))) {
            anim_active = true;
            AnimationParams p;
            anim.draw(c, toVector2i(pos), p, diff);
        }

        bool moreWork() {
            //anim/sound, drawing or emitter
            return (sound && sound_active) || (anim && anim_active)
                || (props.color.a > 0) || (emitted < props.emit_count);
        }

        //die if finished
        //never die here if neither animations or sound are enabled
        if (!moreWork()) {
            kill();
            return;
        }

        if (props.color.a > 0) {
            Color col = props.color;
            col.a = props.color.a
                * max((1.0f - diff.secsf / props.lifetime.secsf), 0);
            c.drawFilledCircle(toVector2i(pos), 2, col);
        }

        //particle emitter here
        if (emitted < props.emit_count) {
            emit_next -= deltaT;
            if (emit_next <= 0f) {
                //new particle
                emitted++;
                //xxx randomize time
                emit_next = props.emit_interval.sample(rngShared).secsf;
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
        if (sound) {
            sound.close();
            sound = null;
        }
    }

    //update pause state
    void paused(bool p) {
        //only needed for sound, because everyting else depends just from deltaT
        if (sound) {
            sound.paused = p;
        }
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
                nvel += Vector2f(0, -1) * e.absolute_speed;
                nvel = nvel.rotated(e.spread_angle*(180.0f/math.PI) *
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
                owner.emitParticle(at, nvel, e.particle, false);
                return;
            }
            sum = nsum;
        }
    }
}

//this is for the user of a ParticleWorld
//it does the job of... emitting particles
//takes care of some very stupid issues:
//  - particle emitters actually work by creating a special particle, which
//    emits other particles; you'll have to keep that special particle alive
//    somehow (because particles may randomly die because of various reasons)
//  - Particle* pointers might randomly become invalid lololo
//    (memory allocation issues)
//also this is a struct because I'm deeply afraid of memory allocation
struct ParticleEmitter {
    private {
        ParticleWorld mOwner;
        ulong mGeneration;
        Particle* mPtr;
    }

    //desired particle emitter
    ParticleType current;
    //can be used to disable particle emitter, even if current !is null
    bool active = true;
    //is used on update()
    Vector2f pos, velocity;


    //check if mPtr is valid, and set it to null if it isn't
    private void check(ParticleWorld owner) {
        if (mOwner && owner is mOwner) {
            if (mOwner.mGeneration == mGeneration)
                return;
        }
        mOwner = owner;
        //reset for various reasons
        mPtr = null; //pointer might be invalid lololo
        mGeneration = mOwner ? mOwner.mGeneration : 0;
    }

    //must be called "once in a while" (like every game engine frame)
    void update(ParticleWorld owner) {
        check(owner);

        if (!mOwner)
            return;

        bool haveparticles() {
            return !!mPtr && !mPtr.dead();
        }

        bool wantparticles = active && !!current;
        bool newParticle = haveparticles() && mPtr.props !is current;

        if (haveparticles() != wantparticles || newParticle) {
            if (mPtr) {
                mPtr.kill();
                mPtr = null;
            }
            if (wantparticles) {
                mPtr = mOwner.newparticle(current, true);
            }
        }
        if (haveparticles()) {
            mPtr.pos = pos;
            mPtr.velocity = velocity;
        }
    }
}

class ParticleWorld {
    private {
        TimeSource mTS; //only !null if no external timesource
        TimeSourcePublic time;
        bool mPauseState;
        Rect2i mViewArea;
        ObjectList!(Particle*, "node") mParticles, mFreeParticles;
        ObjectList!(ParticleEffect, "node") mEffects;
        Time mLastFrame = Time.Never;
        Particle[] mParticleStorage;
        ulong mGeneration; //changes everytime mParticleStorage changes
        //set of ParticleTypes, which might be referenced by Particle
        //because Particles are in C memory, the GC doesn't scan them
        //  => must prevent those objects from being collected, somehow
        bool[ParticleType] mPin;
    }
    float windSpeed = 0f;
    int waterLine = int.max;

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

    //must be finalizer-safe (don't access references to GC memory)
    private void free() {
        mGeneration++;
        //this code should be executed to make sure all sounds are terminated,
        //  but can't call .kill() within a finalizer
        //will fix later, when we introduce more manual memory managment
        //--//for releasing sound sources
        //--foreach (ref p; mParticleStorage) {
        //--    p.kill();
        //--}
        //release memory
        version (CMemory) {
            //if (mParticleStorage.ptr)
            //    Trace.formatln("-------------- free! -----------");
            cstdlib.free(mParticleStorage.ptr);
        }
        mParticleStorage = null;
    }

    ~this() {
        free();
    }

    private void alloc(size_t n) {
        free();
        version (CMemory) {
            void* p = cstdlib.calloc(n, Particle.sizeof);
            if (!p)
                throw new Exception("out of memory");
            mParticleStorage = (cast(Particle*)p)[0..n];
        } else {
            mParticleStorage.length = n;
        }
    }

    void reinit(int particle_count = 50000) {
        free();
        alloc(particle_count);
        foreach (ref p; mParticleStorage) {
            mFreeParticles.add(&p);
        }
    }

    void draw(Canvas c) {
        debug {
            PerfTimer timer = globals.newTimer("particles");
            timer.start();
        }

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

        debug {
            timer.stop();
            globals.setCounter("particles", mParticles.count);
        }
    }

    //move from freelist to active list
    //actually never does an actual memory allocation
    //may return null (if all particles are in use)
    private Particle* newparticle(ParticleType props, bool pin) {
        assert(!!props);

        if (pin)
            mPin[props] = true;

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

    void emitParticle(Vector2f pos, Vector2f vel, ParticleType props,
        bool pin = true)
    {
        Particle* p = newparticle(props, pin);
        if (!p)
            return;
        p.pos = pos;
        p.velocity = vel;
    }

    void explosion(Vector2f pos, float vAdd = 100f, float radius = 50f) {
        foreach (Particle* p; mParticles) {
            float dist = (p.pos - pos).length;
            if (p.dead || dist > radius || dist < float.epsilon)
                continue;
            p.velocity += p.props.explosion_influence * (p.pos-pos)/dist
                * (radius - dist) * vAdd;
        }
    }

    //xxx: if an external TimeSource is used, (see ctor), this should set the
    //     pause state automatically according to whether the _realtime_ is
    //      paused or not (that is, the full TimeSource hierarchy must be
    //      checked); but TimeSource doesn't have this yet
    void paused(bool p) {
        if (mPauseState == p)
            return;
        mPauseState = p;
        if (mTS) {
            mTS.paused = p;
        }
        foreach (ref particle; mParticles) {
            particle.paused = mPauseState;
        }
    }

    //set the visible screen area - call this before draw()
    //the draw area is used for positioned sound
    //could also be used for clipping of graphics and so on
    void setViewArea(Rect2i rc) {
        mViewArea = rc;
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
            if (info.isMouseButton && info.isDown) {
                if (info.code == Keycode.MOUSE_LEFT)
                    mWorld.explosion(toVector2f(mousePos()));
                if (info.code == Keycode.MOUSE_RIGHT) {
                    auto grav = new ParticleGravity(mWorld);
                    grav.accel = 10f;
                    grav.pos = toVector2f(mousePos());
                }
            }
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
        y.emit_on_death ~= ParticleEmit(x, 2, 0, 1, math.PI*2);
        y.emit_on_death_count = 6;
        auto z = new ParticleType;
        z.wind_influence = 0.8;
        z.explosion_influence = 0.005f;
        z.gravity = 10f;
        z.emit_delay = timeMsecs(500);
        z.emit_count = int.max;
        z.emit ~= ParticleEmit(y, 0.7f, 0, 1.0f, math.PI/180*60);
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
