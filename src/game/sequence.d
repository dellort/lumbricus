module game.sequence;

import common.animation;
import common.scene;
import common.resset;
import framework.drawing;
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

import std.math;
import str = utils.string;

alias StaticFactory!("SequenceStates", SequenceState, SequenceType, ConfigNode)
    SequenceStateFactory;

//just a namespace for SequenceState
final class SequenceType {
    private {
        GameCore mEngine;
        SequenceState[string] mStates;
        string mName;
    }

    //source = one sequence entry, e.g. wwwp.conf/sequences/s_worm
    //will be added to engine.resources by the caller (or so)
    this (GameCore a_engine, ConfigNode source) {
        mEngine = a_engine;
        mName = source.name;
        //substates
        foreach (ConfigNode sub; source) {
            string sname = sub.name;
            loadcheck(!(sname in mStates), "double state name: "~sname);
            string type = "simple_animation";
            if (sub.hasSubNodes())
                type = sub.getValue!(string)("type");
            loadcheck(type != "", "no 'type' field set: %s", sub.filePosition);
            try {
                mStates[sname] = SequenceStateFactory.instantiate(type, this,
                    sub);
            } catch (CustomException e) {
                //edit exception to include more information; because catching
                //  CustomExceptions is "safe", this should be fine too
                e.msg = myformat("While loading sequence '%s::%s': %s", name,
                    sname, e.msg);
                throw e;
            }
        }
    }

    final string name() { return mName; }
    final GameCore engine() { return mEngine; }

    //if cond is false, throw load-error as CustomException
    void loadcheck(T...)(bool cond, cstring fmt, T args) {
        if (!cond)
            throw new CustomException(myformat(fmt, args));
    }

    //helper; may return null
    final SequenceState normalState() {
        auto pstate = "normal" in mStates;
        return pstate ? *pstate : null;
    }

    ///return a state by name; return null if not found, if !allow_notfound,
    ///then raise an error instead of returning null
    final SequenceState findState(string sname, bool allow_notfound = false) {
        auto pstate = sname in mStates;
        if (pstate) {
            assert(!!*pstate);
            return *pstate;
        }
        if (!allow_notfound)
            throw new CustomException(myformat("state not found: %s in %s",
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

    //same as owner.loadcheck
    void loadcheck(T...)(bool cond, cstring fmt, T args) {
        if (cond)
            return;
        //meh, varargs not chainable
        owner.loadcheck(false, "%s", myformat(fmt, args));
    }

    protected abstract DisplayType getDisplayType();

    //convenience function
    //load a named animation from node
    Animation loadanim(ConfigNode node, string name, bool optional = false) {
        try {
            return engine.resources.get!(Animation)(
                node.getValue!(string)(name), optional);
        } catch (CustomException e) {
            //same "trick" as in SequenceType ctor
            e.msg = myformat("While loading animation from %s / '%s': %s",
                node.locationString(), name, e.msg);
            throw e;
        }
    }

    //load Animation "name" as resource
    Animation loadanim(string name, bool optional = false) {
        return engine.resources.get!(Animation)(name, optional);
    }

    override string toString() {
        foreach (string name, SequenceState val; owner.mStates) {
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
    GameCore engine;

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

    //xxx there's too much overly specific crap in there, maybe componentize
    //  (as described in Game Programming Gems 6 chapter 4.6)

    //was: SequenceUpdate
    //(or: read directly from a sprite??)
    Vector2f position;
    Vector2f velocity;
    float rotation_angle; //worm itself, always 0 .. PI*2
    float lifepower;    //absolute hp
    float lifePercent;  //percent of initial life remaining, may go > 1.0
    //bool visible;
    float poisoned = 0;  //request animation for being poisoned, e.g. skunk

    //was: WormSequenceUpdate
    //just used to display jetpack exhaust flames
    Vector2f selfForce;

    //if true, draw out-of-camera arrows instead of out-of-level arrows
    bool cameraArrows;

    //if true, the arrow is oriented by the position of the Sequence, not by its
    //  velocity
    bool positionArrow;

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
        enum cInterpolate = true;

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

        argcheck(!!mDisplay); //if mCurrentState is set mDisplay should be there
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

    StateDisplay stateDisplay() {
        return mDisplay;
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

    //draw out of level/out of camera arrows
    void drawArrowStuff(Canvas c) {
        Animation arrow = team ? team.cursor : null;
        if (arrow) {
            auto ipos = interpolated_position();

            //if object is out of world boundaries, show arrow
            Rect2i bounds = engine.level.worldBounds;
            if (cameraArrows)
                bounds = c.visibleArea();
            if (!bounds.isInside(ipos) && ipos.y < bounds.p2.y) {
                enum int cMargin = 20; //est. size for arrow / 2

                auto itime = interpolated_time();

                auto posrect = bounds;
                posrect.extendBorder(Vector2i(-cMargin));
                auto apos = posrect.clip(ipos);
                Vector2f dir = void;
                if (positionArrow) {
                    //rotation so that it points to the position of the arrow
                    dir = toVector2f(ipos - apos);
                } else {
                    //use object velocity for arrow rotation
                    dir = velocity;
                }
                int a = 90;
                if (dir.quad_length > float.epsilon)
                    a = cast(int)(dir.toAngle()*180.0f/PI);
                AnimationParams aparams;
                //arrow animation seems rotated by 180° <- no it's not!!1
                aparams.p[0] = (a+180)%360;
                //arrows used to have zorder GameZOrder.RangeArrow
                //now they have the zorder of the object; I think it's ok
                arrow.draw(c, apos, aparams, itime);

                //label for distance between outer border and object
                posrect.extendBorder(Vector2i(-cMargin));
                FormattedText txt = engine.getTempLabel(team);
                txt.setTextFmt(false, "%s", (ipos-apos).length - cMargin);
                Vector2i s = txt.textSize();
                Rect2i rn = posrect.moveInside(Rect2i(s).centeredAt(ipos));
                txt.draw(c, rn.p1);
            }
        }
    }
}

//xxx: could be made a SceneObject (for fun and profit)
abstract class StateDisplay {
    Sequence owner;
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
        float mSpeed = 1.0f;  //animation speed modifier
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
        ani_params.p[0] = cast(int)(owner.rotation_angle/PI*180f);
        //this is quite WWP specific
        ani_params.p[2] = owner.team ? owner.team.colorIndex + 1 : 0;
    }

    final Animation animation() {
        return mAnimation;
    }

    override void draw(Canvas c) {
        if (!mAnimation)
            return;

        auto ipos = owner.interpolated_position();
        auto itime = owner.interpolated_time();

        mAnimation.draw(c, ipos, ani_params, (itime - mStart) * mSpeed);

        owner.drawArrowStuff(c);
    }

    final void setAnimation(Animation a_animation, Time startAt = Time.Null) {
        mAnimation = a_animation;
        mStart = now() + startAt;
    }

    //like above, but startAt will be a random position if random == true
    final void setAnimationRnd(Animation a_animation, bool random = true) {
        setAnimation(a_animation, random ? timeMsecs(owner.engine.rnd.nextRange(
            0, cast(int)(a_animation.duration.msecs))) : Time.Null);
    }

    final bool hasFinished() {
        if (!mAnimation)
            return true;
        return mAnimation.finished((now() - mStart) * mSpeed);
    }

    final bool isRepeating() {
        if (!mAnimation)
            return false;
        return mAnimation.repeat;
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

    //set animation speed
    //use with care: mAnimation.lengthMs will be unaffected
    final float speed() {
        return mSpeed;
    }
    final void speed(float sp) {
        mSpeed = sp;
    }
}

class SimpleAnimationDisplay : AniStateDisplay {
    SimpleAnimationState myclass;

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(SimpleAnimationState)(state);
        super.init(state);
        setAnimationRnd(myclass.animation, myclass.random_start);
        if (myclass.random_speed != 0) {
            speed = owner.engine.rnd.nextRange(1.0f - myclass.random_speed,
                1.0f + myclass.random_speed);
        }
    }

    override void simulate() {
        std_anim_params();
        //not always done, because one could imagine alternative "wirings"
        if (myclass.wire_p2_to_damage) {
            ani_params.p[1] = cast(int)((1.0f-owner.lifePercent)*100);
        }
    }
}

class SimpleAnimationState : SequenceState {
    Animation animation;
    bool wire_p2_to_damage;
    bool random_start;
    //StateDisplay.speed will be in [1.0f - random_speed, 1.0f + random_speed]
    float random_speed = 0;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        string ani;
        if (!node.hasSubNodes()) {
            ani = node.value;
        } else {
            ani = node["animation"];
            wire_p2_to_damage = node.getValue!(bool)("wire_p2_to_damage");
            random_start = node.getValue!(bool)("random_start");
            random_speed = node.getValue("random_speed", random_speed);
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
    enum cTresholdVelocity = 300.0f;
    //velocity where fly animation is at maximum
    enum cFullVelocity = 450.0f;
    enum cVelDelta = cFullVelocity - cTresholdVelocity;

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
            ani_params.p[1] = cast(int)owner.lifePercent; //0-100
        } else {
            //fast napalm
            new_animation = myclass.animFly;
            ani_params.p[0] = cast(int)(owner.rotation_angle*180.0f/PI);
            ani_params.p[1] = cast(int)(100
                * (speed-cTresholdVelocity) / cVelDelta);
        }
        if (animation() !is new_animation) {
            setAnimationRnd(new_animation);
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

class EnterLeaveDisplay : AniStateDisplay {
    EnterLeaveState myclass;
    Time mNextIdle; //just an offset

    this (Sequence a_owner) { super(a_owner); }

    override void init(SequenceState state) {
        myclass = castStrict!(EnterLeaveState)(state);
        mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
        super.init(state);
        setAnimation(myclass.enter ? myclass.enter : myclass.normal);
    }

    override void simulate() {
        assert(!!myclass);

        std_anim_params();

        //set idle animations
        if (animation is myclass.normal && myclass.idle_animations.length) {
            if (animation_start + mNextIdle <= now()) {
                mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
                Animation[] arr = myclass.idle_animations;
                setAnimation(arr[owner.engine.rnd.next(cast(uint)arr.length)]);
            }
        }

        if (hasFinished()) {
            if (animation is myclass.enter) {
                setAnimation(myclass.normal);
            }
            if (animation !is myclass.normal && animation !is myclass.leave) {
                //leave idle animation
                setAnimation(myclass.normal);
            }
        }
    }

    override void leave() {
        if (myclass.leave && animation !is myclass.leave)
            setAnimation(myclass.leave);
    }
}

class EnterLeaveState : SequenceState {
    //enter and leave can be null
    Animation normal, enter, leave;
    //idle animations (xxx: maybe should moved into a more generic class?)
    RandomValue!(Time) idle_wait;
    Animation[] idle_animations;

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);
        normal = loadanim(node, "normal");
        enter = loadanim(node, "enter", true);
        leave = loadanim(node, "leave", true);

        ConfigNode idlenode = node.findNode("idle_animations");
        if (idlenode) {
            idle_wait = node.getValue!(typeof(idle_wait))("idle_wait");
            foreach (string k, string value; idlenode) {
                idle_animations ~= loadanim(value);
            }
        }
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(EnterLeaveDisplay);
    }
}


//xxx uninteresting rant follows
    //somehow, worm.d needs to set weapon parameters, query the weapon animation
    //  state, etc....
    //here are ways how you could implement this
    //- put them directly into Sequence
    //- some sort of WeaponPart object, that gets added to Sequence, and that
    //  carries the parameters
    //- add it directly into the AniStateDisplay descendant (WwpWeaponDisplay)
    //- like above, but use an interface instead of the direct class
    //- like above, but use an abstract class derived from AniStateDisplay that
    //  defines the API, and derive WwpWeaponDisplay from it (best if you want
    //  to implement a new type of weapon animations)
    //- actually implement everything as a Sequence subclass, instead of using
    //  AniStateDisplay indirection (no clue why I didn't do this in the first
    //  place, maybe because of state transitions or something)
    //- some better idea you have and which you should add here
    //I picked the simplest one that doesn't clutter up Sequence and keeps out
    //  the special cases
    //generally, the Sequence design doesn't make much sense, but I blame WWP's
    //  way of putting worm and weapon animation into the same image
    //obvious design errors:
    //- every weapon could need different animation code, but that isn't
    //  possible with Sequence; we don't need this right now, because the WWP
    //  are uniform, and don't allow the addition of new weapons (you'd need
    //  their source graphics)
    //- too specific to worms weapons and Sprite is forced to use Sequence
    //- just a single state string, instead of multiple properties that somehow
    //  define behaviour in a declarativ way (including transition animations);
    //  obviously you have to implement much by yourself in D code, like in
    //  WwpWeaponDisplay
    //- animation code should be composeable: e.g. if you have code for idle-
    //  animations, it should be useable by any "state"; actually any animation
    //  should be customizable to have additional functionality such as idle
    //  animations, without having to write additional code for it
    //- animation -> game logic (Sequence -> WormSprite) feedback is extremely
    //  awkward, you get the feeling putting it all into WormSprite would be
    //  much simpler
    //- ...
//rant end (writing comments is simpler than fixing stuff)


//this handles the normal "stand" state as well as armed worms (stand+weaoon)
//xxx the idle animation code is duplicated in EnterLeaveState/Display; I found
//  the code too messy to factor them out; if you ever rewrite the weapon
//  animation code, think of it
class WwpWeaponDisplay : AniStateDisplay {
    //Phase.Normal has two animations, one normal and one for sick worms
    //Phase.FireEnd has two possible transitions; which is chosen depends
    //  whether the Sequence config provides a "release" or "fire_end"
    //  animation; if "release" is provided (auto-release weapon such as
    //  baseball bat), it uses the FireEndRot one
    private enum Phase {
        Normal,     //no weapon held
        Idle,       //no weapon held, but idle animation displayed
        Get,        //transition None->Hold
        GetRot,     //rotate weapon angle from resting angle -> actual angle
        Hold,       //weapon ready
        UngetRot,   //same as GetRot, but reversed direction
        Unget,      //transition Hold->None
        Prepare,    //transition Hold->Fire (prepare for firing)
        Fire,       //during firing
        FireEndRot, //transition Fire->FireEnd (similar to UngetRot)
        FireEnd,    //transition Fire->Hold or FireEndRot->None
    }

    alias void delegate() DG;

    private {
        WwpWeaponState myclass;
        //invariant: mCurrent is null/non-null synchronous to mPhase
        //  it is null for Phase.Normal, Phase.Idle
        WwpWeaponState.Weapon mCurrent, mRequested;
        Time mNextIdle; //just an offset
        float mAngle = 0.0f; //always 0 .. PI
        Phase mPhase = Phase.Normal;
        Time mRotStart;
        //temporary, from game logic
        DG mOnFireReady;
        //stop fire animation when next possible
        bool mRequestStopFire;
    }

    enum cLowHpTreshold = 30f;   //different (ill-looking) animation below

    this (Sequence a_owner) { super(a_owner); }

    //-------- public API

    //always -PI/2 .. PI/2
    void angle(float a) {
        mAngle = clampRangeC!(typeof(a))(a, -PI/2, PI/2);
    }
    float angle() {
        return mAngle;
    }

    private WwpWeaponState.Weapon findWeapon(string name) {
        if (name.length == 0)
            return null;
        if (auto p = name in myclass.weapons)
            return *p;
        return myclass.weapon_unknown;
    }

    //empty string means no weapon selected
    void weapon(string weapon) {
        auto w = findWeapon(weapon);
        if (mCurrent is w) {
            //reset the weapon state if needed (at the very least stop
            //  "ungetting" animations that will clear the weapon)
            if (w && ungetting()) {
                //not perfect, just resets
                mPhase = Phase.Hold;
                setAnimation(mCurrent.hold);
            }
            return;
        }

        if (!w) {
            //unarm (start rotate-back)
            mRequested = null;
            if (!busy())
            {
                unget();
            }
        } else {
            //get armed
            mRequested = w;
            //if idle, set it immediately
            if (!busy())
            {
                setNormalAnim();
            }
        }
    }

    //if a weapon is displayed as selected (used for auto-release animations)
    bool weaponSelected() {
        return !!mCurrent;
    }

    //weapon animation can be displayed as requested
    bool ok() {
        return mCurrent !is myclass.weapon_unknown;
    }

    //if fire() was called, and the passed dgs yet have to be called
    //worm.d uses this to poll stuff
    bool preparingFire() {
        return mPhase == Phase.Prepare;
    }

    //start firing animation (starting with prepare, then go to firing)
    //onFireReady = called as soon as the prepare animation is done
    //returns success
    bool fire(DG onFireReady, bool isRefire) {
        //an unget of the old weapon might still be playing, and will be aborted
        mCurrent = mRequested;
        if (!mCurrent)
            return false;
        //xxx Proposal: return false if the current Phase does not agree
        //    with starting firing (like when there is still an unget playing)
        //    But this would mean noticable delays when pressing space
        //    Decision: Delays for user vs. visible animation jumps
        /+if (mPhase != Phase.Get && mPhase != Phase.GetRot
            && mPhase != Phase.Hold)
        {
            return false;
        }+/
        mOnFireReady = onFireReady;
        mRequestStopFire = false;
        if (isRefire && !mCurrent.animate_refire) {
            //instant fire without animation (e.g. super banana)
            doFireReady();
        } else {
            mPhase = Phase.Prepare;
            setAnimation(mCurrent.prepare);
            advance();
        }
        return true;
    }

    //if fire animation is running, stop it and play the cleanup animations
    //onFireAllDone = called after fire_end has been played
    //returns success
    bool stopFire() {
        if (!mCurrent)
            return false;
        if (mPhase != Phase.Fire)
            return false;
        mRequestStopFire = true;
        return true;
    }

    //-------- end public API

    override void init(SequenceState state) {
        myclass = castStrict!(WwpWeaponState)(state);
        mPhase = Phase.Normal;
        mCurrent = null;
        mRequested = null;
        mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
        super.init(state);
        setNormalAnim();
    }

    private bool hasLowHp() {
        return owner.lifepower < cLowHpTreshold;
    }

    private void setNormalAnim() {
        mPhase = Phase.Normal;
        mCurrent = mRequested;
        Animation ani = myclass.normal;
        if (owner.poisoned > 0 && myclass.poisoned) {
            ani = myclass.poisoned;
        } else if (hasLowHp && myclass.lowhp) {
            ani = myclass.lowhp;
        }
        //a weapon is selected, display it
        if (mCurrent) {
            mPhase = Phase.Get;
            ani = mCurrent.get;
        }
        //don't reset the ani if it's already set
        if (ani !is animation)
            setAnimation(ani);
    }

    private void setIdleAnim() {
        mPhase = Phase.Idle;
        mNextIdle = myclass.idle_wait.sample(owner.engine.rnd);
        Animation[] arr = myclass.idle_animations;
        if (owner.poisoned > 0 && myclass.poisoned
            && myclass.idle_animations_poisoned.length > 0)
        {
            arr = myclass.idle_animations_poisoned;
        }
        setAnimation(arr[owner.engine.rnd.next(cast(uint)arr.length)]);
    }

    //deselect weapon (only does something if weapon is selected in any way)
    private void unget() {
        //rotate weapon back, then unget
        if (mCurrent && !ungetting()) {
            mPhase = Phase.UngetRot;
            mRotStart = now();
        }
    }

    private bool ungetting() {
        return mPhase == Phase.Unget || mPhase == Phase.UngetRot;
    }

    //are we playing something that should not be aborted
    //note: those states all should somehow lead to a setNormalAnim() call,
    //  or weapon changing won't work
    private bool busy() {
        return mPhase == Phase.UngetRot || mPhase == Phase.Unget
            || mPhase == Phase.Prepare || mPhase == Phase.Fire
            || mPhase == Phase.FireEndRot || mPhase == Phase.FireEnd;
    }

    private void doFireReady() {
        auto tmp = mOnFireReady;
        if (tmp) {
            mOnFireReady = null;
            tmp();
        }
    }

    private void advance() {
        assert(!!myclass);
        //execute doFrame() until there are (probably) no more state changes
        //this is to avoid 1-frame delays, mostly caused by animation with no
        //  length (time duration = 0ms)
        for (;;) {
            Animation ani = animation;
            Phase ph = mPhase;
            doFrame();
            if (ani is animation && ph is mPhase)
                break;
        }
    }

    private void doFrame() {
        if (!hasFinished())
            return;

        if (mPhase == Phase.Get) {
            mPhase = Phase.GetRot;
            setAnimation(mCurrent.hold);
            mRotStart = now();
        } else if (mPhase == Phase.Unget) {
            setNormalAnim();
        } else if (mPhase == Phase.Idle) {
            setNormalAnim();
        } else if (mPhase == Phase.Prepare) {
            mPhase = Phase.Fire;
            setAnimation(mCurrent.fire);
            doFireReady();
        } else if (mPhase == Phase.Fire) {
            //1. non-repeated animation -> sequence can handle display timing
            //2. the logic has notified us that the Shooter is done
            if (!isRepeating() || mRequestStopFire) {
                if (!mCurrent.fire_end_releases) {
                    mPhase = Phase.FireEnd;
                    setAnimation(mCurrent.fire_end);
                } else {
                    //special case for auto-release weapons
                    //they have this as in-between state, and it is assumed that
                    //  the fire animation doesn't repeat (so it doesn't look
                    //  stupid when the animation is unrotated)
                    mPhase = Phase.FireEndRot;
                    mRotStart = now();
                }
            }
        } else if (mPhase == Phase.FireEnd) {
            if (mCurrent.fire_end_releases) {
                //that's right, the fire_end animation has to include the
                //  unget animation
                setNormalAnim();
            } else {
                mPhase = Phase.Hold;
                setAnimation(mCurrent.hold);
                //maybe change weapon
                if (mCurrent !is mRequested) {
                    if (mRequested) {
                        //another weapon is waiting, change faster without unget
                        //xxx visible skip, could also do unget() but
                        //    takes longer
                        setNormalAnim();
                    } else {
                        //no weapon requested, we are in no hurry
                        unget();
                    }
                }
            }
        } else if (mPhase == Phase.Normal) {
            if (myclass.idle_animations.length
                && animation_start + mNextIdle <= now())
            {
                setIdleAnim();
            }
        }
    }

    override void simulate() {
        advance();

        float wangle = mAngle;

        bool rot_get = mPhase == Phase.GetRot;
        bool rot_unget = mPhase == Phase.UngetRot;
        bool rot_fireunget = mPhase == Phase.FireEndRot;

        //animate weapon angle after get animation or before unget
        if (mCurrent && (rot_get || rot_unget || rot_fireunget)) {
            auto timediff = now() - mRotStart;
            float a1 = 0, a2 = wangle;
            if (!rot_get)
                swap(a1, a2);
            auto anglediff = angleDistance(a1, a2);
            float dist;
            enum cFixedAngularTime = true;
            enum cAngularSpeed = 10f;
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
                if (rot_get) {
                    mPhase = Phase.Hold;
                } else if (rot_unget) {
                    mPhase = Phase.Unget;
                    setAnimation(mCurrent.unget);
                } else if (rot_fireunget) {
                    mPhase = Phase.FireEnd;
                    setAnimation(mCurrent.fire_end);
                } else {
                    assert(false);
                }
            } else {
                //xxx a2-a1 is wrong for angles, because angles are modulo 2*PI
                // for the current use (worm-weapon), this works by luck
                wangle = a1 + dist*copysign(1.0f, a2-a1);
            }
        }

        std_anim_params();
        ani_params.p[1] = cast(int)(wangle/PI*180);
    }

    override void leave() {
        unget();
    }

    override bool isDone() {
        return super.isDone() && !ungetting();
    }

    override void cleanup() {
        super.cleanup();
        mPhase = Phase.Normal;
        mCurrent = null;
        mRequested = null;
    }
}

class WwpWeaponState : SequenceState {
    Animation normal; //stand state, normal
    Animation lowhp; //stand state, "not feeling well"
    Animation poisoned; //stand state, poisoned by skunk or other weapons
    //indexed by the name, which is referred to by WeaponClass.animation
    Weapon[string] weapons;
    Weapon weapon_unknown;
    //idle animations (xxx: maybe should moved into a more generic class?)
    RandomValue!(Time) idle_wait;
    Animation[] idle_animations;
    Animation[] idle_animations_poisoned; //hacky

    class Weapon {
        string name;    //of the weapon
        //all of these are never null (may be 1-frame dummy animations, though)
        Animation get, hold, unget, prepare, fire, fire_end;
        //fire_end leads to weapon release, and the deselection animation is
        //  included in fire_end (e.g. baseball)
        bool fire_end_releases;
        //if true, refire will play the prepare->fire->fire_end animations again
        //  the problem here is that some weapons (shotgun) require an animation
        //  when refiring, and some others (super banana) don't
        bool animate_refire;
    }

    this(SequenceType a_owner, ConfigNode node) {
        super(a_owner, node);

        normal = loadanim(node, "animation");
        lowhp = loadanim(node, "lowhp_animation", true);
        poisoned = loadanim(node, "poisoned_animation", true);

        foreach (string key, string value; node.getSubNode("weapons")) {
            //this '+' thing is just to remind the user that value is a prefix
            if (!str.endsWith(value, "+"))
                loadcheck(false, "weapon entry doesn't end with '+': %s",value);
            value = value[0..$-1];
            auto w = new Weapon();
            w.name = key;
            if (str.eatStart(value, "refire;")) {
                w.animate_refire = true;
            }
            //xxx: this could be optional, there's code to handle that
            //  I guess I just wanted to require at least one valid animation?
            w.get = loadanim(value ~ "get");
            //optional, will create derived replacement animations
            w.hold = loadanim(value ~ "hold", true);
            w.unget = loadanim(value ~ "unget", true);
            w.fire = loadanim(value ~ "fire", true);
            //really optional
            w.prepare = loadanim(value ~ "prepare", true);
            auto fire_end = loadanim(value ~ "fire_end", true);
            auto release = loadanim(value ~ "release", true);
            loadcheck(!(fire_end && release), "can have only either fire_end or"
                " release animation for weapon entry: %s", value);
            if (release) {
                w.fire_end = release;
                w.fire_end_releases = true;
            } else {
                w.fire_end = fire_end;
            }
            weapons[key] = w;
        }

        enum string cUnknown = "#unknown";

        loadcheck(!!(cUnknown in weapons), "no "~cUnknown~" field.");
        weapon_unknown = weapons[cUnknown];

        //NOTE: using these animations may lead to 1-frame delays, which usually
        //  shouldn't matter because they're invisible; and they simplify the
        //  animation state machine code a lot
        //such a 1-frame animation has a length of 0 seconds, but typically, the
        //  animation code will check hasFinished() only in the following frame
        //often, multiple 1-frame delays are introduced (but still small
        //  enough), and hold -> fire_end can be up to 4 chained 1-frame anis
        Animation lastframe(Animation a) {
            //gross hack? I call it elegant!
            return new SubAnimation(a, a.frameCount() - 1);
        }

        loadcheck(!!weapon_unknown.get, "need get animation for %s", cUnknown);
        //fix up other weapons that don't have some animations
        foreach (ref w; weapons) {
            if (!w.get)
                w.get = weapon_unknown.get;
            //no hold animation -> show last frame of get animation
            if (!w.hold)
                w.hold = lastframe(w.get);
            if (!w.unget)
                w.unget = w.get.reversed;
            if (!w.prepare)
                w.prepare = lastframe(w.hold);
            if (!w.fire)
                w.fire = lastframe(w.prepare);
            if (!w.fire_end)
                w.fire_end = lastframe(w.fire);
        }

        idle_wait = node.getValue!(typeof(idle_wait))("idle_wait");

        Animation[] load_idle(string subnode) {
            Animation[] res;
            foreach (string k, string value; node.getSubNode(subnode)) {
                res ~= loadanim(value);
            }
            return res;
        }
        idle_animations = load_idle("idle_animations");
        idle_animations_poisoned = load_idle("idle_animations_poisoned");
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WwpWeaponDisplay);
    }
}


static this() {
    SequenceStateFactory.register!(SimpleAnimationState)("simple_animation");
    SequenceStateFactory.register!(EnterLeaveState)("enter_leave");
    SequenceStateFactory.register!(WwpNapalmState)("wwp_napalm");
    SequenceStateFactory.register!(WwpJetpackState)("wwp_jetpack");
    SequenceStateFactory.register!(WwpWeaponState)("wwp_weapon_select");
}

