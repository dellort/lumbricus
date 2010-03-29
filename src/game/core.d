module game.core;

//should not be part of the game module import cycle
//will kill anyone who makes this module a part of the cycle

import common.animation;
import common.scene;
import common.resset;
import framework.framework;
import game.effects;
import game.events;
import game.particles;
import game.setup; //: GameConfig
import game.teamtheme;
import game.temp;
import game.levelgen.level;
import game.lua.base;
import gui.rendertext;
import physics.world;
import utils.list2;
import utils.log;
import utils.misc;
import utils.random;
import utils.timesource;

import net.marshal; // : Hasher;

//xxx: sender is a dummy object, should be controller or something
alias DeclareEvent!("game_start", GameObject) OnGameStart;
//init plugins
alias DeclareEvent!("game_init", GameObject) OnGameInit;
alias DeclareEvent!("game_end", GameObject) OnGameEnd;
alias DeclareEvent!("game_sudden_death", GameObject) OnSuddenDeath;
//add a HUD object to the GUI;
//  char[] id = type of the HUD object to add
//  Object info = status object, that is used to pass information to the HUD
alias DeclareEvent!("game_hud_add", GameObject, char[], Object) OnHudAdd;
//called when the game is loaded from savegame
//xxx this event is intederministic and must not have influence on game state
alias DeclareEvent!("game_reload", GameObject) OnGameReload;
//called on a non-fatal game error, with a message for the gui
alias DeclareEvent!("game_error", GameObject, char[]) OnGameError;


abstract class GameObject : EventTarget {
    private bool mIsAlive, mInternalActive;
    private GameCore mEngine;

    //creator object
    GameObject createdBy;

    //for GameCore
    ObjListNode!(typeof(this)) sim_node, all_node;

    //event_target_type: not needed anymore, but leaving it in for now
    //  basically should give the type of the game object as a string
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

//dummy object *sigh*
class GlobalEvents : GameObject {
    this(GameCore a_engine) { super(a_engine, "root"); }
    override bool activity() { return false; }
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
        GlobalEvents mGlobalEvents;
        ScriptingObj mScripting;
        GameConfig mGameConfig; //not so good dependency
        PhysicWorld mPhysicWorld;
        ResourceSet mResources;
        ParticleWorld mParticleWorld;
        Object[char[]] mHudRequests;
        //for neutral text, I use GameCore as key (hacky but simple)
        FormattedText[Object] mTempTextThemed;
    }

    protected {
        ObjectList!(GameObject, "all_node") mAllObjects, mKillList;
        ObjectList!(GameObject, "sim_node") mActiveObjects;

        static LogStruct!("game.game") log;
    }

    //xxx maybe the GameConfig should be available only in a later stage of the
    //  game loading
    this(GameConfig a_config, TimeSourcePublic a_gameTime,
        TimeSourcePublic a_interpolateTime)
    {
        mAllObjects = new typeof(mAllObjects)();
        mKillList = new typeof(mKillList)();
        mActiveObjects = new typeof(mActiveObjects)();

        //random seed will be fixed later during intialization
        mRnd = new Random();
        mRnd.seed(1);

        mPhysicWorld = new PhysicWorld(rnd);

        mScene = new Scene();

        mEvents = new Events();
        mGlobalEvents = new GlobalEvents(this);

        mParticleWorld = new ParticleWorld();

        mResources = new ResourceSet();

        mGameConfig = a_config;
        mGameTime = a_gameTime;
        mInterpolateTime = a_interpolateTime;

        OnHudAdd.handler(events, &onHudAdd);

        mScripting = createScriptingObj();
        scripting.addSingleton(this); //doesn't work as expected, see GameEngine
        scripting.addSingleton(rnd);
        scripting.addSingleton(physicWorld);
        scripting.addSingleton(physicWorld.collide);
        scripting.addSingleton(level);
    }

    //-- boring getters (but better than making everything world-writeable)

    ///looks like scene is now used for both deterministic and undeterministic
    /// stuff - normally shouldn't matter
    final Scene scene() { return mScene; }
    final Random rnd() { return mRnd; }
    final Events events() { return mEvents; }
    final GameObject globalEvents() { return mGlobalEvents; }
    final ScriptingObj scripting() { return mScripting; }
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

    //-- can be used to avoid static module dependencies

    final void addSingleton(Object o) {
        auto key = o.classinfo;
        assert (!(key in mSingletons), "singleton exists already");
        mSingletons[key] = o;
    }

    final T singleton(T)() {
        auto ps = T.classinfo in mSingletons;
        if (!ps)
            assert(false, "singleton doesn't exist");
        //cast must always succeed, else addSingleton is broken
        return castStrict!(T)(*ps);
    }

    //-- crap and hacks

    //needed for rendering team specific stuff (crate spies)
    Actor delegate() getControlledTeamMember;

    abstract void error(char[] fmt, ...);

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

    private void onHudAdd(GameObject sender, char[] id, Object obj) {
        assert(!(id in mHudRequests), "id must be unique?");
        mHudRequests[id] = obj;
    }

    //just needed for game loading (see gameframe.d)
    //(actually, this is needed even on normal game start)
    Object[char[]] allHudRequests() {
        return mHudRequests;
    }

    //-- GameObject managment

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
            if (!o.mIsAlive) {
                //remove (it's done lazily, and here it's actually removed)
                mActiveObjects.remove(o);
            }
        }

        //the promise is, that dead objects get invalid only in the "next" game
        //  frame - and this is here
        foreach (GameObject o; mKillList) {
            log("killed GameObject: {}", o);
            mKillList.remove(o);
            scripting().call("game_kill_object\0", o);
            //for debugging: clear the object by memory stomping it
            //scripting could still access the object, violating the rules; but
            //  we have to stay memory safe, so that evil scripts can't cause
            //  security issues
            //but clearing with 0 should be fine... maybe
            //ok, case 1 where this will cause failure:
            //  1. shoot at something (bazooka on barrel)
            //  2. on explosion, it will crash in Sprite.physDamage, because
            //     the "cause" parameter refers to an outdated GameObject (the
            //     dynamic cast will segfault if stomping is enabled)
            //  3. the "cause" is saved by some PhysicForce object, and that
            //     object probably exploded and was "killed" (creating that
            //     PhysicForce with the explosion)
            //  - not assigning a "cause" in explosionAt() works it around
            //case 2:
            //  worm dies => everyone uses a dead sprite
            //case 3:
            //  mLastCrate in controller.d
            //case 4:
            //  throwing a carpet bomb (don't know why)
            if (o.dontDieOnMe.length) {
                log("don't stomp, those still need it: {}", o.dontDieOnMe);
                continue;
            }
            //can uncomment this to enable delicious crashes whenever dead
            //  objects are being accessed
            //(cast(ubyte*)cast(void*)o)[0..o.classinfo.init.length] = 0;
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
}
