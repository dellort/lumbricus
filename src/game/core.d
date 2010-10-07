module game.core;

import common.animation;
import common.common;
import common.lua;
import common.resset;
import common.scene;
import framework.framework;
import framework.i18n; //for LocalizedMessage
import framework.lua;
import game.effects;
import game.events;
import game.input;
import game.particles;
import game.setup; //: GameConfig
import game.teamtheme;
import game.temp : GameZOrder;
import game.levelgen.level;
import game.lua.base;
import gui.rendertext;
import physics.all;
import utils.configfile;
import utils.list2;
import utils.log;
import utils.misc;
import utils.perf;
import utils.random;
import utils.time;
import utils.timesource;

import net.marshal; // : Hasher;

alias DeclareGlobalEvent!("game_start") OnGameStart;
//init plugins
alias DeclareGlobalEvent!("game_init") OnGameInit;
alias DeclareGlobalEvent!("game_end") OnGameEnd;
alias DeclareGlobalEvent!("game_sudden_death") OnSuddenDeath;
//next turn gets prepared; intended for handlers of worm poisoning and
//  turn-persistent napalm, which both need to do something "per turn"
//xxx maybe something that would allow to make events happen in sequence
//  (including waiting for them to finish) instead of once would be nice
//- idea: a function that allows to "pause" the whoever is calling
//  OnPrepareTurn, and then resuming it after the event is done, allowing other
//  handlers to do the same
alias DeclareGlobalEvent!("game_prepare_turn") OnPrepareTurn;

//fixed framerate for the game logic (all of GameEngine)
//also check physic frame length cPhysTimeStepMs in world.d
const Time cFrameLength = timeMsecs(20);

abstract class GameObject : EventTarget {
    private bool mIsAlive, mInternalActive;
    private GameCore mEngine;

    //creator object
    GameObject createdBy;

    //for GameCore
    ObjListNode!(typeof(this)) sim_node, all_node;

    //event_target_type: not needed anymore, but leaving it in for now
    //  basically should give the type of the game object as a string
    //xxx: should do something against the fact that if construction fails (in
    //  a sub-class constructor), the object will still be in the global list
    this(GameCore a_engine, char[] event_target_type) {
        assert(a_engine !is null);
        super(event_target_type, a_engine.events);
        mEngine = a_engine;
        mIsAlive = true;
        engine._object_created(this);
        //starts out with internal_active == false
    }

    final GameCore engine() {
        return mEngine;
    }

    //for GameObject, the only meaning of this is whether simulate() should be
    //  called; that's also the reason why the getter/setter is protected
    protected final void internal_active(bool set) {
        if (set == mInternalActive)
            return;
        mInternalActive = set;
        if (mInternalActive) {
            if (!mIsAlive)
                throw new CustomException("setting active=true for a dead object");
            engine.ensureAdded(this);
        }
        updateInternalActive();
    }

    protected final bool internal_active() {
        return mInternalActive;
    }

    //called after internal_active-value updated
    protected void updateInternalActive() {
    }

    //return true if its active in the sense of a game-round
    abstract bool activity();

    //only called when internal_active == true
    void simulate() {
    }

    final bool objectAlive() {
        return mIsAlive;
    }

    protected void onKill() {
    }

    //when kill() is called, the object is considered to be deallocated on the
    //  next game frame (actually, it may be left to the GC or something, but
    //  we need explicit lifetime for scripting)
    //questionable whether this should be public or protected; public for now,
    //  because it was already public before
    final void kill() {
        if (!mIsAlive)
            return;
        mIsAlive = false;
        onKill();
        internal_active = false;
        engine._object_killed(this);
    }

    //this is a hack
    //some code (wcontrol.d) wants to keep the sprite around, even if it's dead
    //for now I didn't want to change this; but one other hack clears all memory
    //  of a game object to make sure anyone using it will burn his fingers, so
    //  the possibility of not stomping an object had to be introduced
    //Note that this doesn't change semantics (the object will be dead even with
    //  "vetos" added), it just disables the stomping debug code for this object
    //to remove this hack, either...
    //  1. disable stomping, remove this call, and go on normally, or
    //  2. search for code calling killVeto() and fix it
    package Object[] dontDieOnMe;
    final void killVeto(Object user) {
        dontDieOnMe ~= user;
    }

    void hash(Hasher hasher) {
        hasher.hash(mInternalActive);
    }

    //can be used to draw for debugging
    //why not use it for normal game rendering, instead of using that crap in
    //  gamepublic.d? I have no ducking clue...
    void debug_draw(Canvas c) {
    }
}

//abstract TeamMember - required hack for now to do the following things:
//- get TeamTheme for team dependend sprite rendering (e.g. mines)
//- get double damage on explosions
//- crate spy
//if there are better ways to do any of these things, feel free to change them
abstract class Actor : GameObject {
    this(GameCore a, char[] b) { super(a, b); }

    TeamTheme team_theme;
    float damage_multiplier = 1.0f;
    bool crate_spy;
}

//for now, this is the base class of GameEngine
//use GameEngine.fromCore to convert this to GameEngine
//it makes some parts of GfxSet uneeded as well
//in the future, this class should replace both GameEngine and GfxSet
//- there may be some stuff that doesn't really belong here, but as long as it
//  doesn't cause dependency trouble, it's ok
abstract class GameCore {
    private {
        Object[ClassInfo] mSingletons;
        TimeSourcePublic mGameTime, mInterpolateTime;
        Scene mScene;
        Random mRnd;
        Events mEvents;
        InputGroup mInput;
        ScriptingState mScripting;
        GameConfig mGameConfig; //not so good dependency
        PhysicWorld mPhysicWorld;
        ResourceSet mResources;
        ParticleWorld mParticleWorld;
        Log mLog;
        //blergh
        bool mBenchMode;
        int mBenchFramesMax;
        int mBenchFramesCur;
        Time mBenchDrawTime;
        PerfTimer mBenchRealTime, mBenchSimTime;
        //for neutral text, I use GameCore as key (hacky but simple)
        FormattedText[Object] mTempTextThemed;
    }

    protected {
        ObjectList!(GameObject, "all_node") mAllObjects, mKillList;
        ObjectList!(GameObject, "sim_node") mActiveObjects;
    }

    //helper for profiling
    //returns the real time or thread time (depends from utils/perf.d) spent
    //  while drawing the game and non-GUI parts of the game hud (worm labels)
    Time delegate() getRenderTime;

    //render some more stuff for debugging
    bool enableDebugDraw;

    //I don't like this
    ConfigNode persistentState;

    //xxx maybe the GameConfig should be available only in a later stage of the
    //  game loading
    this(GameConfig a_config, TimeSourcePublic a_gameTime,
        TimeSourcePublic a_interpolateTime)
    {
        mLog = registerLog("game");

        mGameConfig = a_config;
        mGameTime = a_gameTime;
        mInterpolateTime = a_interpolateTime;

        mAllObjects = new typeof(mAllObjects)();
        mKillList = new typeof(mKillList)();
        mActiveObjects = new typeof(mActiveObjects)();

        mInput = new InputGroup();

        //random seed will be fixed later during intialization
        //(currently in game.d)
        mRnd = new Random(1);

        mPhysicWorld = new PhysicWorld(rnd);

        mScene = new Scene();

        mEvents = new Events();

        mParticleWorld = new ParticleWorld(mInterpolateTime);
        //xxx rest of particle initialization in game.d

        mResources = new ResourceSet();

        mScripting = createScriptingState();

        scripting.addSingleton(this); //doesn't work as expected, see GameEngine
        scripting.addSingleton(rnd);
        scripting.addSingleton(physicWorld);
        scripting.addSingleton(physicWorld.collide);
        scripting.addSingleton(level);
        scripting.addSingleton(mParticleWorld);

        events.setScripting(scripting);

        scripting.onError = &scriptingObjError;
    }

    override void dispose() {
        super.dispose();
        delete mScripting;
        delete mResources;
        delete mParticleWorld;
        delete mEvents;
        delete mAllObjects;
        delete mActiveObjects;
        delete mKillList;
        delete mScene;
        delete mGameConfig.level;
        foreach (ClassInfo k, ref Object v; mSingletons) {
            v = null;
        }
    }

    //-- boring getters (but better than making everything world-writeable)

    ///looks like scene is now used for both deterministic and undeterministic
    /// stuff - normally shouldn't matter
    final Scene scene() { return mScene; }
    final Random rnd() { return mRnd; }
    final Events events() { return mEvents; }
    final InputGroup input() { return mInput; }
    final ScriptingState scripting() { return mScripting; }
    ///level being played, must not modify returned object
    final Level level() { return mGameConfig.level; }
    final GameConfig gameConfig() { return mGameConfig; }
    final PhysicWorld physicWorld() { return mPhysicWorld; }
    final ResourceSet resources() { return mResources; }
    ///time of last frame that was simulated (fixed framerate, deterministic)
    final TimeSourcePublic gameTime() { return mGameTime; }
    ///indeterministic time synchronous to gameTime, which interpolates between
    /// game engine frames
    final TimeSourcePublic interpolateTime() { return mInterpolateTime; }
    ///indeterministic particle engine
    final ParticleWorld particleWorld() { return mParticleWorld; }
    final Log log() { return mLog; }

    //-- can be used to avoid static module dependencies

    final void addSingleton(Object o) {
        auto key = o.classinfo;
        assert (!(key in mSingletons), "singleton exists already");
        mSingletons[key] = o;
    }

    //return singleton for class T if it exists, or null
    final T querySingleton(T)() {
        auto ps = T.classinfo in mSingletons;
        if (!ps)
            return null;
        //cast must always succeed, else addSingleton is broken
        return castStrict!(T)(*ps);
    }

    //like querySingleton, but it must exist
    final T singleton(T)() {
        T r = querySingleton!(T)();
        if (!r)
            throwError("singleton {} doesn't exist", T.classinfo.name);
        return r;
    }

    //-- crap and hacks

    TeamTheme teamThemeOf(GameObject obj) {
        auto actor = actorFromGameObject(obj);
        return actor ? actor.team_theme : null;
    }

    abstract void explosionAt(Vector2f pos, float damage, GameObject cause,
        bool effect = true, bool damage_landscape = true,
        bool delegate(PhysicObject) selective = null);

    Actor actorFromGameObject(GameObject obj) {
        while (obj) {
            if (auto a = cast(Actor)obj)
                return a;
            obj = obj.createdBy;
        }
        return null;
    }

    //remove all objects etc. from the scene
    void kill() {
        //xxx figure out why this is needed etc. etc.
        //must iterate savely
        //foreach (GameObject o; mObjects) {
        //    o.kill();
        //}
    }

    //determine round-active objects
    //just another loop over all GameObjects :(
    //warning: right now overridden in GameEngine to check some other crap
    bool checkForActivity() {
        foreach (GameObject o; mAllObjects) {
            if (o.activity)
                return true;
        }
        return false;
    }

    //benchmark mode over simtime game time
    void benchStart(Time simtime) {
        mBenchMode = true;
        mBenchFramesMax = simtime/cFrameLength;
        log.notice("Start benchmark, {} => {} frames...", simtime,
            mBenchFramesMax);
        mBenchFramesCur = 0;
        mBenchDrawTime = getRenderTime();
        if (!mBenchSimTime)
            mBenchSimTime = new PerfTimer(true);
        mBenchSimTime.reset();
        if (!mBenchRealTime)
            mBenchRealTime = new PerfTimer(true);
        mBenchRealTime.reset();
        mBenchRealTime.start();
    }

    bool benchActive() {
        return mBenchMode;
    }

    private void benchEnd() {
        assert(mBenchMode);
        mBenchMode = false;
        mBenchRealTime.stop();
        mBenchDrawTime = getRenderTime() - mBenchDrawTime;
        log.notice("Benchmark done ({} frames)", mBenchFramesCur);
        log.notice("  Real time (may or may not include sleep() calls): {}",
            mBenchRealTime.time());
        log.notice("  Game time: {}", mBenchSimTime.time());
        log.notice("  Draw time (without GUI): {}", mBenchDrawTime);
    }

    //-- scripting

    private void scriptingObjError(ScriptingException e) {
        scriptingError("in delegate call", e);
    }

    private void scriptingError(char[] where, ScriptingException e) {
        log.error("Scripting error ({}): {}", where, e.msg);
        traceException(log, e, "for scripting error");
    }

    //-- GameObject managment

    void frame() {
        if (mBenchSimTime)
            mBenchSimTime.start();

        auto physicTime = globals.newTimer("game_physic");
        physicTime.start();
        physicWorld.simulate(gameTime.current);
        physicTime.stop();

        objects_simulate();

        //this will handle all script timers
        try {
            updateTimers(mScripting, gameTime.current);
        } catch (ScriptingException e) {
            scriptingError("running scripting timers", e);
        }

        objects_cleanup();

        //NOTE: it would probably be better to call this, like, every second (in
        //  realtime), instead of every game simulation frame
        mScripting.periodicCleanup();

        if (mBenchSimTime)
            mBenchSimTime.stop();

        if (mBenchMode) {
            mBenchFramesCur++;
            if (mBenchFramesCur >= mBenchFramesMax)
                benchEnd();
        }

        debug {
            globals.setCounter("active_gameobjects", mActiveObjects.count);
            globals.setCounter("all_gameobjects", mAllObjects.count);
            globals.setByteSizeStat("game_lua_vm", scripting.vmsize());
            globals.setCounter("Lua->D calls", gLuaToDCalls);
            globals.setCounter("D->Lua calls", gDToLuaCalls);
            globals.setCounter("D->Lua refs", scripting.reftableSize());
            globals.setCounter("D->Lua refs (total)", gDLuaRefs);
            globals.setCounter("Lua->D refs", scripting.objtableSize());
            globals.setCounter("Lua->D refs (total)", gLuaDRefs);
        }
    }

    //update game objects
    protected void objects_simulate() {
        //NOTE: objects might be inserted/removed while iterating
        //      List.opApply can deal with that
        foreach (GameObject o; mActiveObjects) {
            if (o.mIsAlive) {
                o.simulate();
            }
        }
    }

    //per-frame cleanup of GameObjects
    protected void objects_cleanup() {
        //remove inactive objects from list before killing the game objects,
        //  just needed because of debugging memory stomp
        foreach (GameObject o; mActiveObjects) {
            if (!o.internal_active()) {
                //remove (it's done lazily, and here it's actually removed)
                mActiveObjects.remove(o);
            }
        }

        //the promise is, that dead objects get invalid only in the "next" game
        //  frame - and this is here
        foreach (GameObject o; mKillList) {
            log.trace("killed GameObject: {}", o);
            mKillList.remove(o);
            scripting().call("game_kill_object", o);
        }
        mKillList.clear();
    }

    //only for gobject.d
    private void _object_created(GameObject obj) {
        mAllObjects.add(obj);
    }
    private void _object_killed(GameObject obj) {
        mAllObjects.remove(obj);
        mKillList.add(obj);
    }
    private void ensureAdded(GameObject obj) {
        assert(obj.mIsAlive);
        //in case of lazy removal
        //note that .contains is O(1) if used with .node
        if (!mActiveObjects.contains(obj))
            mActiveObjects.add(obj);
    }

    //calculate a hash value of the game engine state
    //this is a just quick & dirty test to detect diverging client simulation
    //it should always prefer speed over accuracy
    void hash(Hasher hasher) {
        hasher.hash(rnd.state());
        foreach (GameObject o; mAllObjects) {
            o.hash(hasher);
        }
    }

    void debug_draw(Canvas c) {
        if (!enableDebugDraw)
            return;
        mPhysicWorld.debug_draw(c);
        foreach (GameObject o; mAllObjects) {
            o.debug_draw(c);
        }
    }

    //this is for iteration from Lua
    GameObject gameObjectFirst() {
        return mAllObjects.head();
    }

    GameObject gameObjectNext(GameObject obj) {
        if (!obj)
            return null;
        //contains is O(1)
        if (!mAllObjects.contains(obj))
            throw new CustomException("gameObjectNext() on dead object");
        return mAllObjects.next(obj);
    }

    //-- indeterministic drawing functions


    //draw some text with a border around it, in the usual worms label style
    //see getTempLabel()
    //the bad:
    //- slow, may trigger memory allocations (at the very least it will use
    //  slow array appends, even if no new memory is really allocated)
    //- does a lot more work than just draw text and a box
    //- slow because it formats text on each frame
    //- it sucks, maybe I'll replace it by something else
    //=> use FormattedText instead with GfxSet.textCreate()
    //the good:
    //- uses the same drawing code as other _game_ labels
    //- for very transient labels, this probably performs better than allocating
    //  a FormattedText and keeping it around
    //- no need to be deterministic
    final void drawTextFmt(Canvas c, Vector2i pos, char[] fmt, ...) {
        auto txt = getTempLabel();
        txt.setTextFmt_fx(true, fmt, _arguments, _argptr);
        txt.draw(c, pos);
    }

    //return a temporary label in worms style
    //see drawTextFmt() for the why and when to use this
    //how to use:
    //- use txt.setTextFmt() to set the text on the returned object
    //- possibly call txt.textSize() to get the size including label border
    //- call txt.draw()
    //- never touch the object again, as it will be used by other code
    //- you better not change any obscure properties of the label (like font)
    //if theme is !is null, the label will be in the team's color
    final FormattedText getTempLabel(TeamTheme theme = null) {
        //xxx: AA lookup could be avoided by using TeamTheme.colorIndex
        Object idx = theme ? theme : this;
        if (auto p = idx in mTempTextThemed)
            return *p;

        FormattedText res;
        if (theme) {
            res = theme.textCreate();
        } else {
            res = WormLabels.textCreate();
        }
        res.shrink = ShrinkMode.none;
        mTempTextThemed[idx] = res;
        return res;
    }

    final void animationEffect(Animation ani, Vector2i at, AnimationParams p) {
        //if this function gets used a lot, maybe it would be worth it to fuse
        //  this with the particle engine (cf. showExplosion())
        Animator a = new Animator(interpolateTime);
        a.auto_remove = true;
        a.setAnimation(ani);
        a.pos = at;
        a.params = p;
        a.zorder = GameZOrder.Effects;
        scene.add(a);
    }

    void nukeSplatEffect() {
        scene.add(new NukeSplatEffect());
    }
}
