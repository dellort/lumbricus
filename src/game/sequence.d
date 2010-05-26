module game.sequence;

import common.animation;
import common.common;
import common.scene;
import common.resset;
import gui.rendertext;
import utils.configfile;
import utils.factory;
import utils.math;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.random;
import utils.randval;
import utils.vector2;

import game.core;
import game.teamtheme;

import math = tango.math.Math;
import ieee = tango.math.IEEE;
import str = utils.string;

alias StaticFactory!("SequenceStates", SequenceState, SequenceType, ConfigNode)
    SequenceStateFactory;

//just a namespace for SequenceState
final class SequenceType {
    private {
        GameCore mEngine;
        SequenceState[char[]] mStates;
        char[] mName;
    }

    //source = one sequence entry, e.g. wwwp.conf/sequences/s_worm
    //will be added to engine.resources by the caller (or so)
    this (GameCore a_engine, ConfigNode source) {
        mEngine = a_engine;
        mName = source.name;
        //substates
        foreach (ConfigNode sub; source) {
            char[] sname = sub.name;
            assert(!(sname in mStates), "double state name: "~sname);
            char[] type = "simple_animation";
            if (sub.hasSubNodes())
                type = sub.getValue!(char[])("type");
            assert(type != "", "blergh: "~sub.filePosition.toString());
            mStates[sname] = SequenceStateFactory.instantiate(type, this, sub);
        }
    }

    final char[] name() { return mName; }
    final GameCore engine() { return mEngine; }

    //helper; may return null
    final SequenceState normalState() {
        auto pstate = "normal" in mStates;
        return pstate ? *pstate : null;
    }

    ///return a state by name; return null if not found, if !allow_notfound,
    ///then raise an error instead of returning null
    final SequenceState findState(char[] sname, bool allow_notfound = false) {
        auto pstate = sname in mStates;
        if (pstate) {
            assert(!!*pstate);
            return *pstate;
        }
        if (!allow_notfound)
            throw new CustomException(myformat("state not found: {} in {}",
                sname, name));
        return null;
    }
}

//this emulates Delphi style virtual constructors
//in Delphi, this would just be a class variable of T (or whatever it's called)
//if you think this is too convoluted, send me hate-mail
//T = class type common to all objects constructed (e.g. Object)
//Params = parameter types for the constructor call
struct VirtualCtor(T, Params...) {
    private {
        ClassInfo mInfo;
        T delegate(Params p) mCtor;
    }

    static VirtualCtor Init(T2 : T)() {
        VirtualCtor res;
        res.mInfo = T2.classinfo;
        res.mCtor = (Params p) { T r = new T2(p); return r; };
        return res;
    }

    T ctor(Params p) {
        return mCtor(p);
    }

    ClassInfo classinfo() {
        return mInfo;
    }
}

//the object type that can created by this is a class derived from StateDisplay
//the ctor of that class takes a Sequence parameter
alias VirtualCtor!(StateDisplay, Sequence) DisplayType;

///static data about a single state
///(at least used as a handle for the state by the Sequence owner... could use a
/// a simple string to identify the state, but I haet simple strings)
class SequenceState {
    private {
        SequenceType mOwner;
    }

    //node is used by derived classes
    this(SequenceType a_owner, ConfigNode node) {
        mOwner = a_owner;
    }

    final SequenceType owner() { return mOwner; }
    final GameCore engine() { return mOwner.engine; }

    protected abstract DisplayType getDisplayType();

    //convenience function
    Animation loadanim(ConfigNode node, char[] name) {
        return engine.resources.get!(Animation)(node.getValue!(char[])(name));
    }

    char[] toString() {
        foreach (char[] name, SequenceState val; owner.mStates) {
            if (val is this)
                return "[SequenceState:"~name~"]";
        }
        return "?";
    }
}

///A sprite (but it's named Sequence because the name sprite is already used in
///game.sprite for a game logic thingy). Displays animations and also can
///trigger sound and particle effects (not yet).
///This is the public interface to it.
final class Sequence : SceneObject {
    final GameCore engine;

    private {
        SequenceState mCurrentState;
        SequenceState mQueuedState;
        StateDisplay mDisplay;
        StateDisplay mOthers;
        TeamTheme mTeam;

        //transient/indeterministic interpolation state
        //just in a struct to make this more clear (and simpler to register)
        struct Interpolate {
            Vector2i pos;
            Time time;
        }

        Interpolate mIP;
    }

    //was: SequenceUpdate
    //(or: read directly from a sprite??)
    Vector2f position;
    Vector2f velocity;
    float rotation_angle; //worm itself, always 0 .. PI*2
    float lifePercent;  //percent of initial life remaining, may go > 1.0
    //bool visible;

    //was: WormSequenceUpdate
    //just used to display jetpack exhaust flames
    Vector2f selfForce;

    //xxx: move the following stuff into extra objects
    //  e.g. the user should be able to add a weapon to a Sequence by adding a
    //  WeaponPart. this WeaponPart would contain variables and methods specific
    //  to weapons. Same for text; a TextPart would add text to a Sequence.

    char[] weapon;
    float weapon_angle; //always 0 .. PI
    bool weapon_firing;
    //many weapons don't have a time duration while they're "firing"
    //this variable is reset to false by the Sequence animation code
    //to wait until animation end, worm.d could wait until this is false
    bool weapon_fire_oneshot;

    //feedback from weapon display to game logic, if weapon can be properly
    //  displayed (if not, the HUD renders a weapon icon near the worm)
    bool weapon_ok;


    //and this is a hack... but I guess it's good enough for now
    FormattedText attachText;

    //another hack until I can think of something better
    //if non-null, this is visible only if true is returned
    //remember that the delegate is called in a non-deterministic way
    bool delegate(Sequence) textVisibility;

    this(GameCore a_engine, TeamTheme a_team) {
        engine = a_engine;
        mTeam = a_team;
    }

    final TeamTheme team() { return mTeam; }
    final SequenceState currentState() { return mCurrentState; }

    //interpolated position, where object will be drawn
    //non-deterministic (deterministic one is SequenceUpdate.position)
    final Vector2i interpolated_position() {
        return mIP.pos;
    }
    final Time interpolated_time() {
        return mIP.time;
    }

    ///the animation-system can signal readyness back to the game logic with
    ///this (as requested by d0c)
    ///by default, it is signaled on the end of a state change
    final bool readyflag() {
        //xxx checkQueue();
        return !mDisplay || mDisplay.isDone();
    }

    //NOTE:
    //  Why is there simulate() and draw()?
    //  - because simulate() is called each game frame, while draw() is called
    //    randomly (at least in practice). stuff in draw() must not change any
    //    game state (including sequence state), so you have to do that in
    //    simulate(). on the other hand, draw() may do non-deterministic stuff.

    //should be called every frame
    void simulate() {
        checkQueue();
        if (mDisplay)
            mDisplay.simulate();
    }

    private void checkQueue() {
        if (!mQueuedState)
            return;
        if (mDisplay && !mDisplay.isDone())
            return;
        //current state is done; make the queued state current
        setState(mQueuedState);
    }

    bool somethingQueued() {
        return !!mQueuedState;
    }

    override void draw(Canvas c) {
        const cInterpolate = true;

        static if (cInterpolate) {
            mIP.time = engine.interpolateTime.current;
            Time diff = mIP.time - engine.gameTime.current;
            mIP.pos = toVector2i(position + velocity * diff.secsf);
        } else {
            mIP.time = engine.gameTime.current;
            mIP.pos = toVector2i(position);
        }

        if (mDisplay)
            mDisplay.draw(c);

        if (attachText && (!textVisibility || textVisibility(this))) {
            Vector2i p = interpolated_position();
            //so that it's on the top of the object
            //we don't really have a real bounding box, so this will have to do
            p.y -= 15;
            auto s = attachText.size();
            attachText.draw(c, p + Vector2i(-s.x/2, -s.y));
        }
    }

    void remove() {
        mCurrentState = mQueuedState = null;
        updateDisplay();
        removeThis();
    }

    //make current state display some leave animation (if available), and only
    //  if this is done, the state gets current
    //xxx this is unused; need to fix sprite.d and worm.d
    void queueState(SequenceState state) {
        if (!mCurrentState) {
            setState(state);
            return;
        }

        mQueuedState = state;

        assert(!!mDisplay); //if mCurrentState is set, mDisplay should be there
        mDisplay.leave();

        checkQueue();
    }

    //set new state immediately
    void setState(SequenceState state) {
        //game logic calls this function every frame; do not reset
        if (state is mCurrentState)
            return;
        mQueuedState = null;
        mCurrentState = state;
        updateDisplay();
    }

    //set mDisplay to an object that can show newstate, and .init() it
    private void updateDisplay() {
        //mOthers is a singly linked list, that contains all display objects
        // which were created for this Sequence object
        //insert old mDisplay into this list, search the list for a useable
        // object, and remove that object from the list
        //this is intended to avoid reallocation of display objects
        bool displayObjectOk(StateDisplay b) {
            return mCurrentState.getDisplayType().classinfo is b.classinfo;
        }
        if (mDisplay) {
            mDisplay.cleanup(); //clear old state
            //common case: doesn't change
            if (mCurrentState && displayObjectOk(mDisplay)) {
                mDisplay.init(mCurrentState);
                return;
            }
            mDisplay.mNext = mOthers;
            mOthers = mDisplay;
        }
        mDisplay = null;
        if (!mCurrentState)
            return;
        StateDisplay* cur = &mOthers;
        while (*cur && !displayObjectOk(*cur)) {
            cur = &(*cur).mNext;
        }
        if (*cur) {
            mDisplay = *cur;
            *cur = (*cur).mNext;
        } else {
            mDisplay = mCurrentState.getDisplayType().ctor(this);
        }
        assert(displayObjectOk(mDisplay));
        mDisplay.init(mCurrentState);
    }
}

//xxx: could be made a SceneObject (for fun and profit)
abstract class StateDisplay {
    final Sequence owner;
    //only for Sequence.setDisplay()
    private StateDisplay mNext;

    this (Sequence a_owner) {
        owner = a_owner;
    }

    //actually the constructor, but because StateDisplay objects are "cached",
    //  this is a normal method (so you should do all initialization here)
    //note that unlike in a ctor, you must reset all class members manually
    void init(SequenceState state) {
        //initialize animation
        simulate();
    }
    //opposite to init; called when the current sequence state changes
    void cleanup() {
    }

    //play leave transition animation, if available
    //this is called EVERY FRAME when the user used Sequence.queueState()
    //isDone() is checked to see when the leave animation was finished
    //note that Sequence.setState() forces the abortion of the current state
    void leave() {
    }

    //use in conjunction with leave()
    //if this stuff is unused, return true, so that queueing doesn't block up
    bool isDone() {
        return true;
    }

    void simulate() {
    }
    void draw(Canvas c) {
    }

    final Time now() {
        return owner.engine.gameTime.current();
    }
}

//render an animation
//the code here is just for use further classes derived from this class
//  (because I'm paranoid about moving this code into a separate object)
class AniStateDisplay : StateDisplay {
    private {
        Time mStart; //engine time when animation was started
        Animation mAnimation;
    }

    AnimationParams ani_params;
    //simple queueing mechanism
    //Animation next_animation;

    this (Sequence a_owner) {
        super(a_owner);
    }

    override void init(SequenceState state) {
        mAnimation = null;
        mStart = Time.Null;
        super.init(state);
    }

    final void std_anim_params() {
        ani_params.p1 = cast(int)(owner.rotation_angle/math.PI*180f);
        //this is quite WWP specific
        ani_params.p3 = owner.team ? owner.team.colorIndex + 1 : 0;
    }

    final Animation animation() {
        return mAnimation;
    }

    override void draw(Canvas c) {
        if (!mAnimation)
            return;

        auto ipos = owner.interpolated_position();
        auto itime = owner.interpolated_time();

        mAnimation.draw(c, ipos, ani_params, itime - mStart);

        Animation arrow = owner.team ? owner.team.cursor : null;
        if (arrow) {
            //if object is out of world boundaries, show arrow
            Rect2i worldbounds = owner.engine.level.worldBounds;
            if (!worldbounds.isInside(ipos) && ipos.y < worldbounds.p2.y) {
                const int cMargin = 20; //est. size for arrow / 2
                auto posrect = worldbounds;
                posrect.extendBorder(Vector2i(-cMargin));
                auto apos = posrect.clip(ipos);
                //use object velocity for arrow rotation
                int a = 90;
                if (owner.velocity.quad_length > float.epsilon)
                    a = cast(int)(owner.velocity.toAngle()*180.0f/math.PI);
                AnimationParams aparams;
                //arrow animation seems rotated by 180° <- no it's not!!1
                aparams.p1 = (a+180)%360;
                //arrows used to have zorder GameZOrder.RangeArrow
                //now they have the zorder of the object; I think it's ok
                arrow.draw(c, apos, aparams, itime - mStart);

                //label for distance between outer border and object
                posrect.extendBorder(Vector2i(-cMargin));
                FormattedText txt = owner.engine.getTempLabel(owner.team);
                txt.setTextFmt(false, "{}", (ipos-apos).length - cMargin);
                Vector2i s = txt.textSize();
                Rect2i rn = posrect.moveInside(Rect2i(s).centeredAt(ipos));
                txt.draw(c, rn.p1);
            }
        }
    }

    final void setAnimation(Animation a_animation, Time startAt = Time.Null) {
        mAnimation = a_animation;
        mStart = now() + startAt;
    }

    final bool hasFinished() {
        if (!mAnimation)
            return true;
        return mAnimation.finished(now() - mStart);
    }

    override bool isDone() {
        if (!mAnimation)
            return true;
        if (mAnimation.repeat) {
            //repeated => always done (more robust, don't wait forever...)
            return true;
        } else {
            return hasFinished();
        }
    }

    final Time animation_start() {
        return mStart;
    }
}

class SimpleAnimationDisplay : AniStateDisplay {
    SimpleAnimationState myclass;

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(SimpleAnimationState)(state);
        super.init(state);
        setAnimation(myclass.animation);
    }

    override void simulate() {
        std_anim_params();
        //not always done, because one could imagine alternative "wirings"
        if (myclass.wire_p2_to_damage) {
            ani_params.p2 = cast(int)((1.0f-owner.lifePercent)*100);
        }
    }
}

class SimpleAnimationState : SequenceState {
    Animation animation;
    bool wire_p2_to_damage;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        char[] ani;
        if (!node.hasSubNodes()) {
            ani = node.value;
        } else {
            ani = node["animation"];
            wire_p2_to_damage = node.getValue!(bool)("wire_p2_to_damage");
        }
        animation = engine.resources.get!(Animation)(ani);
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(SimpleAnimationDisplay);
    }
}

class WwpNapalmDisplay : AniStateDisplay {
    WwpNapalmState myclass;

    //xxx make this configurable
    //velocity where fly animation begins
    const cTresholdVelocity = 300.0f;
    //velocity where fly animation is at maximum
    const cFullVelocity = 450.0f;
    const cVelDelta = cFullVelocity - cTresholdVelocity;

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(WwpNapalmState)(state);
        super.init(state);
    }

    override void simulate() {
        assert(!!myclass);
        float speed = owner.velocity.length;
        Animation new_animation;
        if (speed < cTresholdVelocity) {
            //slow napalm
            new_animation = myclass.animFall;
            ani_params.p2 = cast(int)owner.lifePercent; //0-100
        } else {
            //fast napalm
            new_animation = myclass.animFly;
            ani_params.p1 = cast(int)(owner.rotation_angle*180.0f/math.PI);
            ani_params.p2 = cast(int)(100
                * (speed-cTresholdVelocity) / cVelDelta);
        }
        if (animation() !is new_animation) {
            setAnimation(new_animation,
                timeMsecs(owner.engine.rnd.nextRange(0,
                    cast(int)(new_animation.duration.msecs))));
        }
    }
}

class WwpNapalmState : SequenceState {
    Animation animFly, animFall;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        animFall = loadanim(node, "fall");
        animFly = loadanim(node, "fly");
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WwpNapalmDisplay);
    }
}

class WwpJetpackDisplay : AniStateDisplay {
    WwpJetpackState myclass;
    //for turnaround
    int mSideFacing; //-1 left, 0 unknown/new, +1 right
    //xxx: proper "compositing" of sub-animations would be nice; but this is a
    //  hack for now
    struct AniState {
        Animation ani;
        Time start;
    }
    AniState[2] mJetFlames;

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(WwpJetpackState)(state);
        mJetFlames[] = mJetFlames[0].init;
        mSideFacing = 0;
        super.init(state);
        setAnimation(myclass.enter);
    }

    override void simulate() {
        assert(!!myclass);

        std_anim_params();

        int curside = angleLeftRight(owner.rotation_angle, -1, +1);
        if (mSideFacing == 0) {
            mSideFacing = curside;
        }
        if (curside != mSideFacing) {
            //side changed => play turnaround animation
            mSideFacing = curside;
            //don't reset if in progress
            //(animation always picks right direction)
            if (animation !is myclass.turn) {
                setAnimation(myclass.turn);
            }
        }

        if (hasFinished()) {
            if (animation is myclass.enter || animation is myclass.turn) {
                setAnimation(myclass.normal);
            }
        }

        //jetpack flames (lit when user presses buttons)
        bool[2] down;
        down[0] = owner.selfForce.x != 0;
        down[1] = owner.selfForce.y < 0;
        if (animation is myclass.turn) {
            //no x-flame during turning (looks better)
            down[0] = false;
            mJetFlames[0] = AniState.init;
        }
        Time t = now();
        foreach (int n, ref cur; mJetFlames) {
            void set_ani(Animation ani, Time start = Time.Null) {
                cur.ani = ani;
                cur.start = t + start;
            }

            //for each direction: if the expected state does not equal the
            //needed animation, reverse the current animation, so
            //that the flame looks looks like it e.g. grows back
            //the animation start time is adjusted so that the switch to the
            //reversed animation is seamless
            auto needed = down[n] ? myclass.flames[n] : myclass.rflames[n];
            if (!cur.ani) {
                //so that the last frame is displayed
                set_ani(needed, -needed.duration());
            }
            if (cur.ani !is needed) {
                auto tdiff = t - cur.start;
                if (tdiff >= needed.duration()) {
                    set_ani(needed);
                } else {
                    set_ani(needed, -(needed.duration() - tdiff));
                }
            }
        }
    }

    override void leave() {
        if (animation !is myclass.leave)
            setAnimation(myclass.leave);
    }

    override void draw(Canvas c) {
        super.draw(c);
        //additions for exhaust flames (overlays normal animation)
        foreach (int idx, ref cur; mJetFlames) {
            assert(!!cur.ani);
            cur.ani.draw(c, owner.interpolated_position(), ani_params,
                owner.interpolated_time() - cur.start);
        }
    }
}

class WwpJetpackState : SequenceState {
    Animation normal, enter, leave, turn;
    Animation[2] flames, rflames;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        normal = loadanim(node, "normal");
        enter = loadanim(node, "enter");
        leave = enter.reversed();
        turn = loadanim(node, "turn");
        flames[0] = loadanim(node, "flame_x");
        flames[1] = loadanim(node, "flame_y");
        for (int i = 0; i < 2; i++)
            rflames[i] = flames[i].reversed();
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WwpJetpackDisplay);
    }
}

class WwpParachuteDisplay : AniStateDisplay {
    WwpParachuteState myclass;

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(WwpParachuteState)(state);
        super.init(state);
        setAnimation(myclass.enter);
    }

    override void simulate() {
        assert(!!myclass);

        std_anim_params();

        if (hasFinished()) {
            if (animation is myclass.enter) {
                setAnimation(myclass.normal);
            }
        }
    }

    override void leave() {
        if (animation !is myclass.leave)
            setAnimation(myclass.leave);
    }
}

class WwpParachuteState : SequenceState {
    Animation normal, enter, leave;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        normal = loadanim(node, "normal");
        enter = loadanim(node, "enter");
        leave = loadanim(node, "leave");
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WwpParachuteDisplay);
    }
}

/+
//this is attached to a sequence and means, the sequence should render a weapon
class WeaponPart {
    private {
        float mWeaponAngle;
        //graphics independent weapon ID used to select the animation
        //it the same as WeaponClass.animation
        char[] mWeaponID;
        //angle value, that's animated to change to mWeaponAngle
        float mAnimatedAngle;
    }

    //reset to start position, start playing get-weapon animation
    void init() {
    }

    void setWeapon(char[] id) {
        mWeaponID = id;
    }

    void setAngle(float angle) {
        mWeaponAngle = angle;
        mAnimatedAngle = angle;
    }

    //can/could be used by weapon code to get the actual angle
    //xxx: should return point and direction where projectile gets fired
    float getAnimatedAngle() {
        return mAnimatedAngle;
    }
}
+/

//compilation fix for LDC - move back into WwpWeaponState as soon as it's fixed
struct WwpWeaponState_Weapon {
    //only "fire" and "hold" can be null
    Animation get, hold, fire, unget;
}

//this handles the normal "stand" state as well as armed worms (stand+weaoon)
class WwpWeaponDisplay : AniStateDisplay {
    WwpWeaponState myclass;
    char[] mCurrentW;
    WwpWeaponState_Weapon mCurrentAni;
    Time mNextIdle; //just an offset
    int mWeaponDir; //1: get, 0: nothing, -1: unget

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(WwpWeaponState)(state);
        mCurrentW = "";
        mCurrentAni = mCurrentAni.init;
        mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
        mWeaponDir = 0;
        super.init(state);
        setAnimation(myclass.normal);
    }

    override void simulate() {
        assert(!!myclass);

        if (!mCurrentW.length) {
            //xxx: always ack the one shot thing because buggy game logic
            owner.weapon_fire_oneshot = false;
        }

        //change weapon
        if (mCurrentW != owner.weapon) {
            if (!owner.weapon.length) {
                //unarm (start rotate-back)
                if (mWeaponDir != -1) {
                    mWeaponDir = -1;
                    //animation_start is abused as start time; need correct time
                    setAnimation(animation);
                }
            } else {
                //get armed
                mCurrentW = owner.weapon;
                auto w = mCurrentW in myclass.weapons;
                owner.weapon_ok = !!w;
                mCurrentAni = w ? *w : myclass.weapon_unknown;
                setAnimation(mCurrentAni.get);
                mWeaponDir = 0;
                owner.weapon_fire_oneshot = false;
            }
        }

        if (hasFinished()) {
            if (animation is mCurrentAni.get) {
                if (mCurrentAni.hold) {
                    setAnimation(mCurrentAni.hold);
                    mWeaponDir = 1;
                }
            }
            if (animation is mCurrentAni.fire && !owner.weapon_firing) {
                //stop firing after one-shot animation
                owner.weapon_fire_oneshot = false;
                setAnimation(mCurrentAni.hold);
            }
            if (animation !is myclass.normal && !mCurrentW.length) {
                //end of idle animation or weapon-unget => set to normal again
                setAnimation(myclass.normal);
            }
        }

        //set idle animations
        if (animation is myclass.normal && myclass.idle_animations.length) {
            if (animation_start + mNextIdle <= now()) {
                mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
                Animation[] arr = myclass.idle_animations;
                setAnimation(arr[owner.engine.rnd.next(arr.length)]);
            }
        }

        //set firing animation
        if (mCurrentAni.fire) {
            bool dofire = owner.weapon_firing | owner.weapon_fire_oneshot;
            if (dofire && animation is mCurrentAni.hold) {
                setAnimation(mCurrentAni.fire);
            } else if (!dofire && animation is mCurrentAni.fire) {
                //for immediate animation stop (don't wait for animation end)
                setAnimation(mCurrentAni.hold);
            }
        }

        float wangle = owner.weapon_angle;

        bool before_unget = mWeaponDir < 0;

        if (mWeaponDir) {
            //animate weapon angle after get animation or before unget
            auto timediff = now() - animation_start;
            float a1 = 0, a2 = wangle;
            if (mWeaponDir < 0)
                swap(a1, a2);
            auto anglediff = angleDistance(a1, a2);
            float dist;
            const cFixedAngularTime = true;
            const cAngularSpeed = 10f;
            if (cFixedAngularTime) {
                //delta_angle = delta_t * (rad/second)
                dist = timediff.secsf * cAngularSpeed;
            } else {
                //this... does it make sense at all?
                dist = anglediff * timediff.secsf * cAngularSpeed;
            }
            if (dist >= anglediff) {
                wangle = a2;
                //finished
                mWeaponDir = 0;
            } else {
                //xxx a2-a1 is wrong for angles, because angles are modulo 2*PI
                // for the current use (worm-weapon), this works by luck
                wangle = a1 + dist*ieee.copysign(1.0f, a2-a1);
            }
        }

        if (before_unget && !mWeaponDir) {
            //rotate-back has ended, start unget + reset
            setAnimation(mCurrentAni.unget);
            mCurrentAni = mCurrentAni.init;
            mCurrentW = "";
            //hm...?
            owner.weapon_ok = false;
        }

        std_anim_params();
        ani_params.p2 = cast(int)(wangle/math.PI*180);
    }

    override void leave() {
        //xxx: think about weapons that auto-unarm after firing
        //rotate weapon back, then unget
        if (mCurrentW.length && !!mWeaponDir) {
            if (animation !is mCurrentAni.unget)
                mWeaponDir = -1;
        }
    }

    override bool isDone() {
        return super.isDone() && !mWeaponDir;
    }

    override void cleanup() {
        super.cleanup();
        owner.weapon_ok = false;
        //is this ok?
        owner.weapon_fire_oneshot = false;
    }
}

class WwpWeaponState : SequenceState {
    Animation normal; //stand state
    //indexed by the name, which is referred to by WeaponClass.animation
    WwpWeaponState_Weapon[char[]] weapons;
    WwpWeaponState_Weapon weapon_unknown;
    //idle animations (xxx: maybe should moved into a more generic class?)
    RandomValue!(Time) idle_wait;
    Animation[] idle_animations;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);

        Animation load(char[] name, bool optional = false) {
            return engine.resources.get!(Animation)(name, optional);
        }

        normal = loadanim(node, "animation");

        foreach (char[] key, char[] value; node.getSubNode("weapons")) {
            //this '+' thing is just to remind the user that value is a prefix
            if (!str.endsWith(value, "+"))
                assert(false, "weapon entry doesn't end with '+': "~value);
            value = value[0..$-1];
            WwpWeaponState_Weapon w;
            w.get = load(value ~ "get", false);
            w.unget = w.get.reversed;
            //optional
            w.hold = load(value ~ "hold", true);
            w.fire = load(value ~ "fire", true);
            //w.fire_end = load(value ~ "fire_end", true);
            weapons[key] = w;
        }

        const char[] cUnknown = "#unknown";

        assert(!!(cUnknown in weapons));
        weapon_unknown = weapons[cUnknown];

        assert(!!weapon_unknown.get, "need get animation for "~cUnknown);
        //fix up other weapons that don't have some animations
        foreach (ref w; weapons) {
            if (!w.get)
                w.get = weapon_unknown.get;
            //no hold animation -> show last frame of get animation
            //and to get such an animation, I'm doing some gross hack
            if (!w.hold) {
                auto fc = w.get.frameCount();
                w.hold = new SubAnimation(w.get, fc-1, fc);
            }
        }

        idle_wait = node.getValue!(typeof(idle_wait))("idle_wait");
        foreach (char[] k, char[] value; node.getSubNode("idle_animations")) {
            idle_animations ~= load(value);
        }
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WwpWeaponDisplay);
    }
}


static this() {
    SequenceStateFactory.register!(SimpleAnimationState)("simple_animation");
    SequenceStateFactory.register!(WwpNapalmState)("wwp_napalm");
    SequenceStateFactory.register!(WwpJetpackState)("wwp_jetpack");
    SequenceStateFactory.register!(WwpParachuteState)("wwp_parachute");
    SequenceStateFactory.register!(WwpWeaponState)("wwp_weapon_select");
}

