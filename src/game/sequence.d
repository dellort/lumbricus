module game.sequence;

enum SeqType {
    //Enter, Leave = transition from/to other sub-states
    //Normal = what is looped when entering was done
    //TurnAroundY = played when worm rotation changes left/right side
    None, Enter, Leave, Normal, TurnAroundY,
}

import common.animation;
import common.common;
import common.scene;
import common.resset;
import utils.configfile;
import utils.math;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.random;
import utils.reflection;
import utils.vector2;

import game.gamepublic;
import game.game;
import game.gfxset;

import math = tango.math.Math;
import ieee = tango.math.IEEE;
import str = utils.string;

static void function(GameEngine engine, ConfigNode from)[char[]]
    loaders;

///all states, one instance per GameEngine, get via GameEngine.sequenceStates
class SequenceStateList {
    private {
        SequenceState[char[]] mStates;
    }

    this () {
    }
    this (ReflectCtor c) {
    }

    ///return a state by name; return null if not found, if !allow_notfound,
    ///then raise an error instead of returning null
    final SequenceState findState(char[] name, bool allow_notfound = false) {
        auto pstate = name in mStates;
        if (pstate) {
            assert(!!*pstate);
            return *pstate;
        }
        if (!allow_notfound)
            throw new Exception("state not found: " ~ name);
        return null;
    }

    final void addState(SequenceState state) {
        assert(!!state);
        if (findState(state.name, true))
            assert(false, "double state: "~state.name);
        mStates[state.name] = state;
        state.fixup();
    }

    void fixup() {
        foreach (SequenceState s; mStates) {
            s.fixup();
        }
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
    final GameEngine engine;
    private {
        char[] mName;
    }
    protected {
        //if the leave transition is always played by default
        bool forceLeaveTransitions;

        struct Transition {
            //name used temporarily to deal with cirular dependencies etc.
            char[] dest_name; //set to "" when resolved
            SequenceState dest;
        }

        //states for which the leave transition of this state should be played
        Transition[] playLeaveTransitions;
    }

    //if leave transition should be played when switching to this state
    bool hasLeaveTransition(SequenceState new_state) {
        if (!new_state)
            return false;
        if (forceLeaveTransitions)
            return true;
        foreach (ref t; playLeaveTransitions) {
            assert(!!t.dest, "forgot state.fixup() call?");
            if (t.dest is new_state)
                return true;
        }
        return false;
    }

    //(takes a name for being able to do forward referencing, must call fixup()
    // after it and before using it)
    void enableLeaveTransition(char[] other_state) {
        Transition t;
        t.dest_name = other_state;
        playLeaveTransitions ~= t;
    }

    final char[] name() {
        return mName;
    }

    void fixup() {
        foreach (ref t; playLeaveTransitions) {
            t.dest = engine.sequenceStates.findState(t.dest_name);
        }
    }

    private final bool displayObjectOk(StateDisplay o) {
        return getDisplayType().classinfo is o.classinfo;
    }

    protected abstract DisplayType getDisplayType();

    this(GameEngine a_engine, char[] name) {
        engine = a_engine;
        mName = name;
    }

    this (ReflectCtor c) {
    }
}

//xxx: what's the point of this class? why not use physics or sprite directly?
//     or make the sprite update the sequence fields
//   - and all of WormSequenceUpdate could be merged into this
class SequenceUpdate {
    Vector2f position;
    Vector2f velocity;
    float rotation_angle; //worm itself, always 0 .. PI*2
    float lifePercent;  //percent of initial life remaining, may go > 1.0
    //bool visible;

    this () {
    }
    this (ReflectCtor c) {
    }
}

//special update class for worm sequence, which allows to introduce custom
//sequence modifiers without changing GObjectSprite
//xxx why is this in this module?
class WormSequenceUpdate : SequenceUpdate {
    float pointto_angle; //for weapon angle, always 0 .. PI
    //just used to display jetpack exhaust flames
    Vector2f selfForce;

    this () {
    }
    this (ReflectCtor c) {
    }
}

///A sprite (but it's named Sequence because the name sprite is already used in
///game.sprite for a game logic thingy). Displays animations and also can
///trigger sound and particle effects (not yet).
///This is the public interface to it.
class Sequence : SceneObject {
    final GameEngine engine;

    protected {
        //state from Sequence (I didn't bother to support several queued states,
        //because we'll maybe never need them)
        SequenceState mQueuedState;
        StateDisplay mDisplay;
        StateDisplay mOthers;
        SequenceUpdate mUpdate;
        TeamTheme mOwner; //xxx make this go away
    }

    this(GameEngine a_engine, SequenceUpdate v, TeamTheme owner) {
        engine = a_engine;
        mUpdate = v;
        mOwner = owner;
    }

    this (ReflectCtor c) {
    }

    ///query current position etc. - fields change as the simulation progresses
    //(e.g. target cross needs infos about the weapon angle)
    final SequenceUpdate getInfos() {
        return mUpdate;
    }

    //xxx belongs into SequenceUpdate? stupid separation
    final TeamTheme teamOwner() {
        return mOwner;
    }

    //interpolated position, where object will be drawn
    //non-deterministic (deterministic one is SequenceUpdate.position)
    final Vector2i interpolated_position() {
        if (!mDisplay) //huh?
            return toVector2i(mUpdate.position);
        return mDisplay.interpolated_position();
    }

    ///the animation-system can signal readyness back to the game logic with
    ///this (as requested by d0c)
    ///by default, it is signaled on the end of a state change
    final bool readyflag() {
        return !mDisplay || mDisplay.readyFlag();
    }

    //NOTE:
    //  Why is there simulate() and draw()?
    //  - because simulate() is called each game frame, while draw() is called
    //    randomly (at least in practice). stuff in draw() must not change any
    //    game state (including sequence state), so you have to do that in
    //    simulate(). on the other hand, draw() may do non-deterministic stuff.

    //should be called every frame
    void simulate() {
        if (mDisplay)
            mDisplay.simulate();
    }

    override void draw(Canvas c) {
        if (mDisplay)
            mDisplay.draw(c);
    }

    //don't need it anymore
    void remove() {
        setDisplay(null);
        removeThis();
    }

    ///query the "real" (i.e. currently being displayed) state
    ///may return null
    final SequenceState getCurrentState() {
        return mDisplay ? mDisplay.getCurrentState() : null;
    }

    ///initiate state change, which might be executed lazily
    ///only has an effect if the state is different from the currently targeted
    ///state
    public void setState(SequenceState state) {
        if (!state)
            return;
        if (state is mQueuedState)
            return;
        SequenceState curstate = getCurrentState();
        if (curstate is state) {
            //got request to go back to current state while still in transition
            //to different mQueuedState -> change target to current
            if (mQueuedState !is null)
                mQueuedState = curstate;
            return;
        }
        //Trace.formatln("set state: ", sstate.name);
        //possibly start state change
        //look if the leaving sequence should play
        bool play_leave = false;
        if (curstate) {
            play_leave |= curstate.hasLeaveTransition(state);
        }
        //Trace.formatln("play leave: ", play_leave);
        if (!curstate || !play_leave) {
            //start new state, skip whatever did go on before
            mQueuedState = null;
            setDisplay(state);
            mDisplay.enterState(state);
        } else if (curstate && play_leave) {
            //current -> leave
            mQueuedState = state;
            mDisplay.leaveState();
        } else {
            //only queue it
            mQueuedState = state;
        }
    }

    //set mDisplay to an object that can show newstate
    private void setDisplay(SequenceState newstate) {
        //mOthers is a singly linked list, that contains all display objects
        // which were created for this Sequence object
        //insert old mDisplay into this list, search the list for a useable
        // object, and remove that object from the list
        //this is intended to avoid reallocation of display objects
        StateDisplay old = mDisplay;
        if (mDisplay) {
            //common case: doesn't change
            if (newstate && newstate.displayObjectOk(mDisplay))
                return;
            mDisplay.mNext = mOthers;
            mOthers = mDisplay;
            mDisplay = null;
        }
        if (old)
            old.disable();
        if (!newstate)
            return;
        StateDisplay* cur = &mOthers;
        while (*cur && !newstate.displayObjectOk(*cur)) {
            cur = &(*cur).mNext;
        }
        if (*cur) {
            mDisplay = *cur;
            *cur = (*cur).mNext;
        } else {
            mDisplay = newstate.getDisplayType().ctor(this);
        }
        assert (newstate.displayObjectOk(mDisplay));
        mDisplay.enable();
    }
}

//xxx: could be made a SceneObject (for fun and profit)
class StateDisplay {
    final Sequence owner;
    //only for Sequence.setDisplay()
    private StateDisplay mNext;

    this (Sequence a_owner) {
        owner = a_owner;
    }

    this (ReflectCtor c) {
    }

    void enterState(SequenceState state) {
    }

    //play leave transition animation, if available
    void leaveState() {
    }

    abstract SequenceState getCurrentState();

    void simulate() {
    }
    void draw(Canvas c) {
    }

    bool readyFlag() {
        return true;
    }

    //prepare to use / don't use anymore this display object
    void enable() {
    }
    void disable() {
    }

    abstract Vector2i interpolated_position();

    final Time now() {
        return owner.engine.gameTime.current();
    }
}

//render an animation
//xxx: maybe the actual interpolation code should be moved into SequenceUpdate?
class AniStateDisplay : StateDisplay {
    //transient/indeterministic interpolation state
    //just in a struct to make this more clear (and simpler to register)
    struct Interpolate {
        Vector2i pos;
    }

    private {
        //GameEngine mOwner; //especially for gameTime
        Time mStart; //engine time when animation was started
        Interpolate mIP;
        Animation mAnimation;
    }

    AnimationParams ani_params;

    this (Sequence a_owner) {
        super(a_owner);
    }
    this (ReflectCtor c) {
        super(c);
        c.transient(this, &mIP);
    }

    private Time now() {
        return owner.engine.gameTime.current();
    }

    final TeamTheme owner_team() {
        return owner.mOwner;
    }

    final Animation animation() {
        return mAnimation;
    }

    final override Vector2i interpolated_position() {
        return mIP.pos;
    }

    override void draw(Canvas c) {
        if (!mAnimation)
            return;

        SequenceUpdate su = owner.getInfos();

        const cInterpolate = true;

        static if (cInterpolate) {
            Time itime = owner.engine.callbacks.interpolateTime.current;
            Time diff = itime - now();
            Vector2i ipos = toVector2i(su.position + su.velocity * diff.secsf);
        } else {
            Time itime = now();
            Vector2i ipos = toVector2i(su.position);
        }

        mIP.pos = ipos;

        mAnimation.draw(c, ipos, ani_params, itime - mStart);

        auto arrow = owner_team() ? owner_team.cursor : null;
        if (arrow) {
            //if object is out of world boundaries, show arrow
            //xxx actually, Sequence should be doing this
            Rect2i worldbounds = owner.engine.level.worldBounds;
            if (!worldbounds.isInside(ipos) && ipos.y < worldbounds.p2.y) {
                auto posrect = worldbounds;
                posrect.extendBorder(Vector2i(-20));
                auto apos = posrect.clip(ipos);
                //use object velocity for arrow rotation
                int a = 90;
                if (su.velocity.quad_length > float.epsilon)
                    a = cast(int)(su.velocity.toAngle()*180.0f/PI);
                AnimationParams aparams;
                //arrow animation seems rotated by 180° <- no it's not!!1
                aparams.p1 = (a+180)%360;
                //arrows used to have zorder GameZOrder.RangeArrow
                //now they have the zorder of the object; I think it's ok
                arrow.draw(c, apos, aparams, itime - mStart);
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

    final Time animation_start() {
        return mStart;
    }

    //just to make it not abstract, for jetpack flames
    override SequenceState getCurrentState() {
        return null;
    }
}

class NapalmStateDisplay : AniStateDisplay {
    NapalmState myclass;
    Animation last_animation;

    //xxx make this configurable
    //velocity where fly animation begins
    const cTresholdVelocity = 300.0f;
    //velocity where fly animation is at maximum
    const cFullVelocity = 450.0f;
    const cVelDelta = cFullVelocity - cTresholdVelocity;

    this (Sequence a_owner) {
        super(a_owner);
    }

    this (ReflectCtor c) {
        super(c);
    }

    void enterState(SequenceState state) {
        myclass = cast(NapalmState)state;
    }

    SequenceState getCurrentState() {
        return myclass;
    }

    override void simulate() {
        if (!myclass)
            return;
        SequenceUpdate v = owner.mUpdate;
        float speed = v.velocity.length;
        Animation new_animation;
        AnimationParams params;
        if (speed < cTresholdVelocity) {
            //slow napalm
            if (last_animation !is myclass.animFall)
                new_animation = myclass.animFall;
            //xxx controls size (0-100), use damage or whatever
            auto nsu = cast(NapalmSequenceUpdate)v;
            ani_params.p2 = nsu ? nsu.decay : 30;
        } else {
            //fast napalm
            if (last_animation !is myclass.animFly)
                new_animation = myclass.animFly;
            ani_params.p1 = cast(int)(v.rotation_angle*180.0f/math.PI);
            ani_params.p2 = cast(int)(100
                * (speed-cTresholdVelocity) / cVelDelta);
        }
        if (new_animation) {
            setAnimation(new_animation,
                timeMsecs(owner.engine.rnd.nextRange(0,
                    cast(int)(new_animation.duration.msecs))));
            last_animation = new_animation;
        }
    }
}

class NapalmSequenceUpdate : SequenceUpdate {
    int decay;

    this () {
    }
    this (ReflectCtor c) {
    }
}

class NapalmState : SequenceState {
    Animation animFly, animFall;

    this(GameEngine a_owner, char[] name) {
        super(a_owner, name);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(NapalmStateDisplay);
    }
}

class WormStateDisplay : AniStateDisplay {
    //current subsequence, also defines current state (.owner param)
    SubSequence mCurSubSeq;
    //start time for current SubSequence
    Time mSubSeqStart;
    // [worm, weapon]
    float[2] mAngles;
    //if interpolation for an angle is on, this is the user set angle
    // interpolation is between angle_user and SubSequence.fixed_value
    float mAngleUser;
    //for turnaround
    int mSideFacing;
    //only for jetpack
    //xxx: proper "compositing" of sub-animations would be nice; but this is a
    //  hack for now
    AniStateDisplay[2] mJetFlames;
    Time[2] mJetFlamesStart;

    this (Sequence a_owner) {
        super(a_owner);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void enterState(SequenceState state) {
        initSequence(cast(WormState)state, SeqType.Enter);
    }

    override void leaveState() {
        initSequence(mCurSubSeq ? mCurSubSeq.owner : null, SeqType.Leave);
    }

    SequenceState getCurrentState() {
        return mCurSubSeq ? mCurSubSeq.owner : null;
    }

    override bool readyFlag() {
        //if no state, consider it ready
        if (!mCurSubSeq || mCurSubSeq.ready)
            return true;
        if (mCurSubSeq.ready_at_end)
            return hasFinished();
        return false;
    }

    void initSequence(WormState state, SeqType seq) {
        SubSequence nseq;

        resetSubSequence();

        if (state) {
            if (state.seqs[seq].length > 0) {
                nseq = state.seqs[seq][0];
            } else if (seq == SeqType.Enter
                && state.seqs[SeqType.Normal].length > 0)
            {
                nseq = state.seqs[SeqType.Normal][0];
            }
        }

        initSubSequence(nseq);
    }

    void resetSubSequence() {
        //possibly deinitialize
        mCurSubSeq = null;
    }

    //make s the currently played thingy
    //xxx: remove updateSubSequence() call and guarantee it's called somewhere
    //  else (so that no recursion is possible)
    void initSubSequence(SubSequence s) {
        resetSubSequence();
        mCurSubSeq = s;
        mSubSeqStart = now();
        mSideFacing = 0;

        /+
        if (s) {
            Trace.formatln("substate {}/{}/{}", s.owner.name, cast(int)(s.type), s.index);
        } else {
            Trace.formatln("reset");
        }
        +/

        if (s && (s.animation || s.reset_animation)) {
            setAnimation(s.animation);
        }

        if (s && s.interpolate_angle_id >= 0) {
            mAngleUser = mAngles[s.interpolate_angle_id];
            if (s.angle_direction == 0) {
                mAngles[s.interpolate_angle_id] = s.angle_fixed_value;
            }
        }

        updateSubSequence();
    }

    void updateSubSequence() {
        if (!mCurSubSeq) {
            return;
        }

        assert (!!owner);

        //check if current animation/interpolation has ended
        //also, actually do angle interpolation if needed
        bool ended = true;
        //if keepLastFrame is set, don't look at hasFinished
        auto anim = mCurSubSeq.animation;
        if (anim && !hasFinished() &&
            !mCurSubSeq.dont_wait_for_animation)
        {
            ended = false;
        }
        if (mCurSubSeq.interpolate_angle_id >= 0) {
            auto timediff = now() - mSubSeqStart;
            auto a1 = mCurSubSeq.angle_fixed_value, a2 = mAngleUser;
            if (mCurSubSeq.angle_direction)
                swap(a1, a2);
            auto anglediff = angleDistance(a1, a2);
            float dist;
            if (!mCurSubSeq.fixed_angular_time) {
                dist = timediff.secsf * mCurSubSeq.angular_speed;
            } else {
                dist = anglediff * timediff.secsf/mCurSubSeq.angular_speed;
            }
            float nangle;
            if (dist >= anglediff) {
                nangle = a2;
            } else {
                ended = false;
                //xxx a2-a1 is wrong for angles, because angles are modulo 2*PI
                // for the current use (worm-weapon), this works by luck
                nangle = a1 + dist*ieee.copysign(1.0f, a2-a1);
            }
            mAngles[mCurSubSeq.interpolate_angle_id] = nangle;
            //updateAngle();
            //xxx: in the earlier version, angle was updated each frame
            //     now it waits for the next simulate()
        }

        ended &= !mCurSubSeq.wait_forever;

        //if (mCurSubSeq.type == SeqType.TurnAroundY)
            //Trace.formatln("side = {}", angleLeftRight(mAngles[0], -1, +1));

        if (!ended) {
            //check turnaround, as it is needed for the jetpack
            if (mCurSubSeq.type == SeqType.Normal
                && mCurSubSeq.owner.seqs[SeqType.TurnAroundY].length > 0)
            {
                int curside = angleLeftRight(mAngles[0], -1, +1);
                if (mSideFacing == 0) {
                    mSideFacing = curside;
                }
                if (curside != mSideFacing) {
                    //side changed => ack and enter the turnaround subsequence
                    mSideFacing = curside;
                    initSequence(mCurSubSeq.owner, SeqType.TurnAroundY);
                }
            }
            return;
        } else {
            //Trace.formatln("ended");
            //next step, either the following SubSequence or a new seq/state
            auto next = mCurSubSeq.getNext();
            if (next) {
                initSubSequence(next);
            } else {
                if (mCurSubSeq.type == SeqType.Enter
                    || mCurSubSeq.type == SeqType.Normal
                    || mCurSubSeq.type == SeqType.TurnAroundY)
                {
                    //entering/looping in normal state
                    //possibly go to new state instead of doing SeqType.Normal
                    auto leave_state = mCurSubSeq.owner.auto_leave.dest;
                    if (!leave_state) {
                        initSequence(mCurSubSeq.owner, SeqType.Normal);
                    } else {
                        resetSubSequence();
                        if (!owner.mQueuedState) {
                            owner.setState(leave_state);
                        } else {
                            auto nextstate = owner.mQueuedState;
                            owner.mQueuedState = null;
                            enterState(nextstate);
                        }
                    }
                } else if (mCurSubSeq.type == SeqType.Leave
                    && owner.mQueuedState)
                {
                    //actually enter new state
                    //xxx unclean
                    auto nextstate = owner.mQueuedState;
                    owner.mQueuedState = null;
                    enterState(nextstate);
                }
            }
        }
    }

    override void simulate() {
        updateSubSequence();
        WormState state = mCurSubSeq ? mCurSubSeq.owner : null;
        float[2] set_angle;
        auto v = owner.mUpdate;
        set_angle[0] = v.rotation_angle;
        auto wsu = cast(WormSequenceUpdate)v;
        if (state.p2_damage) {
            //lol, code below converts back to deg
            const float cDmgToRad = 100.0f/180.0f*math.PI;
            set_angle[1] = max(0f, (1.0f-v.lifePercent)*cDmgToRad);
        }
        else if (wsu)
            set_angle[1] = wsu.pointto_angle;
        else
            set_angle[1] = 0;
        //the angle which is interpolated should not be set directly
        auto exclude = mCurSubSeq ? mCurSubSeq.interpolate_angle_id : -1;
        if (exclude < 0) {
            mAngles[] = set_angle;
        } else {
            //really must not mess up the "excluded" angle
            for (int i = 0; i < 2; i++) {
                if (i != exclude)
                    mAngles[i] = set_angle[i];
            }
            //but save the excluded angle somewhere else
            mAngleUser = set_angle[exclude];
        }
        ani_params.p1 = cast(int)(mAngles[0]/math.PI*180);
        ani_params.p2 = cast(int)(mAngles[1]/math.PI*180);
        //all updates for jetpack flames
        //why is the jetpack so ridiculously complicated?

        if (!state.is_jetpack) {
            if (mJetFlames[0]) {
                //right now, are not added anywhere
                //mJetFlames[0].disable();
                //mJetFlames[1].disable();
            }
        } else if (wsu) {
            bool[2] down;
            down[0] = wsu.selfForce.x != 0;
            down[1] = wsu.selfForce.y < 0;
            Time t = now();
            foreach (int n, ref cur; mJetFlames) {
                if (!cur)
                    cur = new AniStateDisplay(owner);
                cur.ani_params = ani_params;
                //for each direction: if the expected state does not equal the
                //needed animation, reverse the current animation, so
                //that the flame looks looks like it e.g. grows back
                //the animation start time is adjusted so that the switch to the
                //reversed animation is seamless
                auto needed = down[n] ? state.flames[n] : state.rflames[n];
                if (!cur.animation) {
                    //so that the last frame is displayed
                    cur.setAnimation(needed, -needed.duration());
                }
                if (cur.animation is needed)
                    continue;
                auto tdiff = t - cur.animation_start;
                if (tdiff >= needed.duration()) {
                    cur.setAnimation(needed);
                } else {
                    cur.setAnimation(needed, -(needed.duration() - tdiff));
                }
            }
        }
    }

    override void draw(Canvas c) {
        super.draw(c);
        //additions for jetpack (overlays normal animation)
        WormState state = mCurSubSeq ? mCurSubSeq.owner : null;
        if (state && state.is_jetpack) {
            assert(!!mJetFlames[0]);
            mJetFlames[0].draw(c);
            mJetFlames[1].draw(c);
        }
    }
}

class SubSequence {
    //readyness flag signaled back (Sequence.readyflag)
    bool ready = true;
    //if ready==false, signal ready at end of subsequence (dumb hack)
    bool ready_at_end = false;

    //wait for an animation
    Animation animation; //if null, none set

    //yay even more hacks
    bool dont_wait_for_animation; //don't check animation for state transition
    bool reset_animation; //set animation even if that field null
    bool wait_forever; //state just never ends, unless it's aborted from outside

    //needed for that weapon thing
    //index of the angle interpolated
    int interpolate_angle_id = -1;
    //rotation speed
    float angular_speed; //rads/sec
    //select if angular_speed is speed or animation total time
    bool fixed_angular_time;
    //the fixed start/end value
    float angle_fixed_value;
    //the interpolation interpolates between fixed_value and the user set
    //value - direction=0: fixed_value starts, =1: starts with user's value
    int angle_direction;

    //indices into to seqs array which point to this (for getNext)
    WormState owner;
    SeqType type;
    int index;

    SubSequence getNext() {
        SubSequence[] cur = owner.seqs[type];
        if ((index+1) >= cur.length)
            return null;
        return cur[index+1];
    }

    //meh
    SubSequence copy() {
        SubSequence res = new SubSequence;
        foreach (int index, x; this.tupleof) {
            res.tupleof[index] = this.tupleof[index];
        }
        return res;
    }

    this () {
    }
    this (ReflectCtor c) {
    }
}

class WormState : SequenceState {
    SubSequence[][SeqType.max+1] seqs;
    //go to this state after the "enter" subseq. was played
    Transition auto_leave;
    //jetpack only
    bool is_jetpack, p2_damage;
    Animation[2] flames;
    Animation[2] rflames;

    this(GameEngine a_owner, char[] name) {
        super(a_owner, name);
    }

    this (ReflectCtor c) {
        super(c);
    }

    override void fixup() {
        super.fixup();
        foreach (i, inout s; seqs) {
            for (int x = 0; x < s.length; x++) {
                s[x].owner = this;
                s[x].type = cast(SeqType)i;
                s[x].index = x;
            }
        }
    }

    //reverse this one in time (data is copied if neccessary)
    void reverse_subsequence(SeqType type) {
        auto n = seqs[type].dup;
        foreach (ref x; n) {
            x = x.copy();
        }
        n.reverse; //is inplace
        //revert animations and angle-interpolation
        foreach (ref sub; n) {
            if (sub.animation)
                sub.animation = sub.animation.reversed();
            if (sub.angle_direction >= 0)
                sub.angle_direction = 1-sub.angle_direction;
        }
        seqs[type] = n;
    }

    override DisplayType getDisplayType() {
        return DisplayType.Init!(WormStateDisplay);
    }
}

//------------

///Load a bunch of sequences from a ConfigNode (like "sequences" in wwp.conf)
void loadSequences(GameEngine engine, ConfigNode seqList) {
    init_loaders();
    foreach (ConfigNode sub; seqList) {
        auto pload = sub.name in loaders;
        if (!pload) {
            throw new Exception("sequence loader not found: "~sub.name);
        }
        foreach (ConfigNode subsub; sub) {
            (*pload)(engine, subsub);
        }
    }
}

void addState(GameEngine engine, SequenceState state) {
    engine.sequenceStates.addState(state);
}

Animation getAni(GameEngine e, char[] name) {
    return e.gfx.resources.get!(Animation)(name);
}

char[] getValue(ConfigNode fromitem) {
    return fromitem.value;
}

void loadNormal(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    //simple animation, state = animation
    auto state = new WormState(engine, fromitem.name);
    auto ss = new SubSequence;
    ss.animation = getAni(engine, value);
    state.seqs[SeqType.Normal] = [ss];
    addState(engine, state);
}

void loadTeam(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    foreach (col; TeamTheme.cTeamColors) {
        auto state = new WormState(engine, fromitem.name ~ "_" ~ col);
        auto ss = new SubSequence;
        ss.animation = getAni(engine, value ~ "_" ~ col);
        state.seqs[SeqType.Normal] = [ss];
        addState(engine, state);
    }
}

void loadNormalDamage(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    //simple animation, state = animation, using damage for p2
    auto state = new WormState(engine, fromitem.name);
    auto ss = new SubSequence;
    ss.animation = getAni(engine, value);
    state.seqs[SeqType.Normal] = [ss];
    state.p2_damage = true;
    addState(engine, state);
}

void loadWormNormalWeapons(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    auto state = new WormState(engine, fromitem.name);
    auto ss = new SubSequence;
    ss.animation = getAni(engine, value);
    state.seqs[SeqType.Normal] = [ss];
    state.seqs[SeqType.Leave] = [ss];
    state.reverse_subsequence(SeqType.Leave);
    state.enableLeaveTransition("s_worm_stand");
    addState(engine, state);
}

//special case because of enter/leave and turnaround anims
void loadWormJetpack(GameEngine engine, ConfigNode fromitem) {
    auto sub = fromitem;
    auto state = new WormState(engine, fromitem.name);
    auto s_norm = new SubSequence;
    auto s_enter = new SubSequence;
    auto s_turn = new SubSequence;
    s_norm.animation = getAni(engine, sub["normal"]);
    state.seqs[SeqType.Normal] = [s_norm];
    s_enter.animation = getAni(engine, sub["enter"]);
    state.seqs[SeqType.Enter] = [s_enter];
    state.seqs[SeqType.Leave] = state.seqs[SeqType.Enter];
    state.reverse_subsequence(SeqType.Leave);
    s_turn.animation = getAni(engine, sub["turn"]);
    state.seqs[SeqType.TurnAroundY] = [s_turn];
    state.flames[0] = getAni(engine, sub["flame_x"]);
    state.flames[1] = getAni(engine, sub["flame_y"]);
    state.rflames[0] = state.flames[0].reversed();
    state.rflames[1] = state.flames[1].reversed();
    state.is_jetpack = true;
    state.enableLeaveTransition("s_worm_stand");
    addState(engine, state);
}

void loadWormWeapons(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    char[] get = value ~ "_get", hold = value ~ "_hold";
    auto state = new WormState(engine, fromitem.name);
    auto s_norm = new SubSequence;
    auto s_enter1 = new SubSequence;
    auto s_enter2 = new SubSequence;
    s_norm.animation = getAni(engine, hold);
    state.seqs[SeqType.Normal] = [s_norm];
    s_enter1.animation = getAni(engine, get);
    s_enter1.ready = false;
    s_enter2.animation = s_norm.animation;
    s_enter2.ready = false;
    s_enter2.interpolate_angle_id = 1;
    s_enter2.angle_direction = 0;
    s_enter2.angle_fixed_value = 0;
    //s_enter2.angular_speed = (PI/2)/0.5;
    s_enter2.angular_speed = 0.100;
    s_enter2.fixed_angular_time = true;
    s_enter2.dont_wait_for_animation = true;
    state.seqs[SeqType.Enter] = [s_enter1, s_enter2];
    state.seqs[SeqType.Leave] = state.seqs[SeqType.Enter];
    state.reverse_subsequence(SeqType.Leave);
    state.enableLeaveTransition("s_worm_stand");
    addState(engine, state);
}

void loadFirstNormalThenEmpty(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    auto state = new WormState(engine, fromitem.name);
    auto s1 = new SubSequence;
    auto s2 = new SubSequence;
    s1.animation = getAni(engine, value);
    s1.ready = false;
    s1.ready_at_end = true;
    s2.reset_animation = true;
    s2.wait_forever = true;
    state.seqs[SeqType.Normal] = [s1, s2];
    addState(engine, state);
}

void loadAnimation(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    auto state = new WormState(engine, fromitem.name);
    auto s_normal = new SubSequence;
    s_normal.animation = getAni(engine, value);
    state.seqs[SeqType.Normal] = [s_normal];
    addState(engine, state);
}

void loadAnimationWithDrown(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    auto val = str.split(value);
    if (val.length != 2)
        assert(false, "at "~fromitem.name);
    auto state = new WormState(engine, fromitem.name ~ "_normal");
    auto s_normal = new SubSequence;
    s_normal.animation = getAni(engine, val[0]);
    state.seqs[SeqType.Normal] = [s_normal];
    addState(engine, state);
    auto state2 = new WormState(engine, fromitem.name ~ "_drown");
    s_normal = new SubSequence;
    s_normal.animation = getAni(engine, val[1]);
    state2.seqs[SeqType.Normal] = [s_normal];
    addState(engine, state2);
}

void loadNapalm(GameEngine engine, ConfigNode fromitem) {
    auto value = getValue(fromitem);
    auto val = str.split(value);
    if (val.length != 2)
        assert(false, "at "~fromitem.name);
    auto state = new NapalmState(engine, fromitem.name);
    //load animations
    state.animFall = getAni(engine, val[0]);
    state.animFly = getAni(engine, val[1]);
    addState(engine, state);
}

private bool m_loaders_initialized;

private void init_loaders() {
    if (m_loaders_initialized)
        return;
    m_loaders_initialized = true;
    loaders["normal"] = &loadNormal;
    loaders["normal_damage"] = &loadNormalDamage;
    loaders["worm_normal_weapons"] = &loadWormNormalWeapons;
    loaders["worm_jetpack"] = &loadWormJetpack;
    loaders["worm_weapons"] = &loadWormWeapons;
    loaders["first_normal_then_empty"] = &loadFirstNormalThenEmpty;
    loaders["animations"] = &loadAnimation;
    loaders["simple_with_drown"] = &loadAnimationWithDrown;
    loaders["napalm"] = &loadNapalm;
    loaders["team"] = &loadTeam;
}
