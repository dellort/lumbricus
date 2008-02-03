module game.sequence;

import common.animation;
import common.common;
import common.scene;
import framework.resset;
import utils.configfile;
import utils.math;
import utils.misc;
import utils.rect2;
import utils.time;
import utils.vector2;

import game.clientengine;
import game.gamepublic;

import std.math : PI;

//--- interface, including implementations of the generic static data classes

///static data about an object with all its states, e.g. a worm
///
class SequenceObject {
    private {
        char[] mName;
        SequenceState[char[]] mStates;
    }

    final char[] name() {
        return mName;
    }

    this(char[] a_name) {
        mName = a_name;
    }

    ///return an approximate bounding box; for use by graphics attached to a
    ///sequence (e.g. target cross or worm labels)
    ///the box is centered around (0, 0)
    abstract Rect2i bb();

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
    }

    void fixup() {
        foreach (SequenceState s; mStates) {
            s.fixup();
        }
    }

    abstract AbstractSequence instantiate(GraphicsHandler owner);
}

///static data about a single state
///(at least used as a handle for the state by the Sequence owner... could use a
/// a simple string to identify the state, but I haet simple strings)
class SequenceState {
    private {
        SequenceObject mOwner;
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

    final SequenceObject owner() {
        return mOwner;
    }

    void fixup() {
        foreach (ref t; playLeaveTransitions) {
            t.dest = owner.findState(t.dest_name);
        }
    }

    this(SequenceObject a_owner, char[] name) {
        mOwner = a_owner;
        mName = name;
    }
}

struct SequenceUpdate {
    Vector2i position;
    Vector2f velocity;
    float rotation_angle; //worm itself, always 0 .. PI*2
    float pointto_angle; //for weapon angle, always 0 .. PI
    //bool visible;
}

///A sprite (but it's named Sequence because the name sprite is already used in
///game.sprite for a game logic thingy). Displays animations and also can
///trigger sound and particle effects (not yet).
///This is the public interface to it.
interface Sequence : Graphic {
    ///as what this Sequence was instantiated; never changes (SequenceObject is
    ///possibly bound to the class implementing this interface)
    abstract SequenceObject type();

    ///modify position etc.; uses only information for which sth. is implemented
    ///(e.g. it won't use velocity most time)
    abstract void update(ref SequenceUpdate v);

    ///initiate state change, which might be changed lazily
    ///only has an effect if the state is different from the currently targeted
    ///state
    abstract void setState(SequenceState state);

    ///query current position etc.
    //(e.g. target cross needs infos about the weapon angle)
    abstract void getInfos(ref SequenceUpdate v);

    ///the animation-system can signal readyness back to the game logic with
    ///this (as requested by d0c)
    ///by default, it is signaled on the end of a state change
    abstract bool readyflag();
}

///blergh
abstract class AbstractSequence : ClientGraphic, Sequence {
    private {
        SequenceObject mType;
    }

    this(GraphicsHandler a_owner, SequenceObject a_type) {
        super(a_owner);
        mType = a_type;
    }

    final override SequenceObject type() {
        return mType;
    }

    //yay factory pattern again
    //from.name defines the name
    static SequenceObject delegate(ResourceSet res, ConfigItem from)[char[]]
        loaders;
}

///--- stuff needed for wwp worms
//(this all can be completely hidden from the rest of the game due to the
// factory pattern...)

private:

class WormSequenceObject : SequenceObject {
    this(char[] a_name) {
        super(a_name);
    }

    AbstractSequence instantiate(GraphicsHandler owner) {
        return new WormSequence(owner, this);
    }

    Rect2i bb() {
        return Rect2i(-30, -30, 30, 30);
    }
}

SequenceObject loadWorm(ResourceSet res, ConfigItem fromitem) {
    alias WormState.SubSequence SubSequence;
    alias WormState.SeqType SeqType;

    auto from = castStrict!(ConfigNode)(fromitem);

    auto seq = new WormSequenceObject(from.name);
    foreach (ConfigNode sub; from) {
        if (sub.name == "normal") {
            foreach (ConfigValue s; sub) {
                //simple animation, state = animation
                auto state = new WormState(seq, s.name);
                SubSequence ss;
                ss.animation = res.get!(Animation)(s.value);
                state.seqs[SeqType.Normal] = [ss];
                seq.addState(state);
            }
        } else if (sub.name == "normal_weapons") {
            foreach (ConfigValue s; sub) {
                auto state = new WormState(seq, s.name);
                SubSequence ss;
                ss.animation = res.get!(Animation)(s.value);
                state.seqs[SeqType.Normal] = [ss];
                state.seqs[SeqType.Leave] = [ss];
                state.reverse_subsequence(SeqType.Leave);
                seq.addState(state);
                state.enableLeaveTransition("stand");
            }
        } else if (sub.name == "jetpack") {
            //special case because of enter/leave and turnaround anims
            auto state = new WormState(seq, "jetpack");
            SubSequence s_norm, s_enter, s_turn;
            s_norm.animation = res.get!(Animation)(sub["normal"]);
            state.seqs[SeqType.Normal] = [s_norm];
            s_enter.animation = res.get!(Animation)(sub["enter"]);
            state.seqs[SeqType.Enter] = [s_enter];
            state.seqs[SeqType.Leave] = state.seqs[SeqType.Enter];
            state.reverse_subsequence(SeqType.Leave);
            s_turn.animation = res.get!(Animation)(sub["turn"]);
            state.seqs[SeqType.TurnAroundY] = [s_turn];
            seq.addState(state);
            state.enableLeaveTransition("stand");
        } else if (sub.name == "weapons") {
            foreach (ConfigValue s; sub) {
                char[] get = s.value ~ "_get", hold = s.value ~ "_hold";
                auto state = new WormState(seq, s.name);
                SubSequence s_norm, s_enter1, s_enter2;
                s_norm.animation = res.get!(Animation)(hold);
                state.seqs[SeqType.Normal] = [s_norm];
                s_enter1.animation = res.get!(Animation)(get);
                s_enter2.animation = s_norm.animation;
                s_enter2.interpolate_angle_id = 1;
                s_enter2.angle_direction = 0;
                s_enter2.angle_fixed_value = 0;
                s_enter2.angular_speed = (PI/2)/0.5;
                s_enter2.dont_wait_for_animation = true;
                state.seqs[SeqType.Enter] = [s_enter1, s_enter2];
                state.seqs[SeqType.Leave] = state.seqs[SeqType.Enter];
                state.reverse_subsequence(SeqType.Leave);
                seq.addState(state);
                state.enableLeaveTransition("stand");
            }
        } else if (sub.name == "first_normal_then_empty") {
            foreach (ConfigValue s; sub) {
                auto state = new WormState(seq, s.name);
                SubSequence s1, s2;
                s1.animation = res.get!(Animation)(s.value);
                s1.ready = false;
                s2.reset_animation = true;
                s2.wait_forever = true;
                state.seqs[SeqType.Normal] = [s1, s2];
                seq.addState(state);
            }
        } else {
            assert(false);
        }
    }
    seq.fixup();
    return seq;
}

SequenceObject loadAnimation(ResourceSet res, ConfigItem fromitem) {
    alias WormState.SubSequence SubSequence;
    alias WormState.SeqType SeqType;

    auto val = castStrict!(ConfigValue)(fromitem).value;
    auto seq = new WormSequenceObject(fromitem.name);
    auto state = new WormState(seq, "normal");
    SubSequence s_normal;
    s_normal.animation = res.get!(Animation)(val);
    state.seqs[SeqType.Normal] = [s_normal];
    seq.addState(state);
    seq.fixup();
    return seq;
}

static this() {
    AbstractSequence.loaders["worm"] = toDelegate(&loadWorm);
    AbstractSequence.loaders["animations"] = toDelegate(&loadAnimation);
}

class WormState : SequenceState {
    enum SeqType {
        //Enter, Leave = transition from/to other sub-states
        //Normal = what is looped when entering was done
        //TurnAroundY = played when worm rotation changes left/right side
        None, Enter, Leave, Normal, TurnAroundY,
    }
    struct SubSequence {
        //readyness flag signaled back (Sequence.readyflag)
        bool ready = true;

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
        //the fixed start/end value
        float angle_fixed_value;
        //the interpolation interpolates between fixed_value and the user set
        //value - direction=0: fixed_value starts, =1: starts with user's value
        int angle_direction;

        //indices into to seqs array which point to this (for getNext)
        WormState owner;
        SeqType type;
        int index;

        SubSequence* getNext() {
            SubSequence[] cur = owner.seqs[type];
            if ((index+1) >= cur.length)
                return null;
            return &cur[index+1];
        }
    }

    SubSequence[][SeqType.max+1] seqs;
    //go to this state after the "enter" subseq. was played
    Transition auto_leave;

    this(SequenceObject a_owner, char[] name) {
        super(a_owner, name);
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
}

class WormSequence : AbstractSequence {
private:
    alias WormState.SubSequence SubSequence;
    alias WormState.SeqType SeqType;
    //state from Sequence (I didn't bother to support several queued states,
    //because we'll maybe never need them)
    WormState mQueuedState;
    //current subsequence, also defines current state (.owner param)
    SubSequence* mCurSubSeq;
    //start time for current SubSequence
    Time mSubSeqStart;
    // [worm, weapon]
    float[2] mAngles;
    //if interpolation for an angle is on, this is the user set angle
    // interpolation is between angle_user and SubSequence.fixed_value
    float mAngleUser;
    //for turnaround
    int mSideFacing;
    //and finally, something useful, which does real work!
    Animator mAnimator;

    Time now() {
        return globals.gameTimeAnimations.current();
    }

    this(GraphicsHandler a_owner, SequenceObject a_type) {
        super(a_owner, a_type);
        mAnimator = new Animator();
        init();
    }

    void initSequence(WormState state, SeqType seq) {
        SubSequence* nseq;

        if (state) {
            if (state.seqs[seq].length > 0) {
                nseq = &state.seqs[seq][0];
            } else if (seq == SeqType.Enter
                && state.seqs[SeqType.Normal].length > 0)
            {
                nseq = &state.seqs[SeqType.Normal][0];
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
    void initSubSequence(SubSequence* s) {
        resetSubSequence();
        mCurSubSeq = s;
        mSubSeqStart = now();
        mSideFacing = 0;

        if (s) {
            std.stdio.writefln("substate %s/%s/%s", s.owner.name, cast(int)(s.type), s.index);
        } else {
            std.stdio.writefln("reset");
        }

        if (s && (s.animation || s.reset_animation)) {
            mAnimator.setAnimation(s.animation);
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

        //check if current animation/interpolation has ended
        //also, actually do angle interpolation if needed
        bool ended = true;
        //if keepLastFrame is set, don't look at hasFinished
        if (mAnimator.animation &&
            (!mAnimator.hasFinished() || mAnimator.animation.keepLastFrame)
             && !mCurSubSeq.dont_wait_for_animation)
        {
            ended = false;
        }
        if (mCurSubSeq.interpolate_angle_id >= 0) {
            auto timediff = now() - mSubSeqStart;
            auto dist = timediff.secsf * mCurSubSeq.angular_speed;
            auto a1 = mCurSubSeq.angle_fixed_value, a2 = mAngleUser;
            if (mCurSubSeq.angle_direction)
                swap(a1, a2);
            auto anglediff = angleDistance(a1, a2);
            float nangle;
            if (dist >= anglediff) {
                nangle = a2;
            } else {
                ended = false;
                //xxx a2-a1 is wrong for angles, because angles are modulo 2*PI
                // for the current use (worm-weapon), this works by luck
                nangle = a1 + dist*math.copysign(1.0f, a2-a1);
            }
            mAngles[mCurSubSeq.interpolate_angle_id] = nangle;
            updateAngle();
        }

        ended &= !mCurSubSeq.wait_forever;

        if (mCurSubSeq.type == SeqType.TurnAroundY)
        std.stdio.writefln("side = %s", angleLeftRight(mAngles[0], -1, +1));

        if (!ended) {
            //check turnaround, as it is needed for the jetpack
            if (mCurSubSeq.owner.seqs[SeqType.TurnAroundY].length > 0) {
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
        }

        if (ended) {
            std.stdio.writefln("ended");
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
                        if (!mQueuedState) {
                            setState(leave_state);
                        } else {
                            auto nextstate = mQueuedState;
                            mQueuedState = null;
                            initSequence(nextstate, SeqType.Enter);
                        }
                    }
                } else if (mCurSubSeq.type == SeqType.Leave && mQueuedState) {
                    //actually enter new state
                    auto nextstate = mQueuedState;
                    mQueuedState = null;
                    initSequence(nextstate, SeqType.Enter);
                }
            }
        }
    }

    public override void simulate() {
        updateSubSequence();
    }

    void updateAngle() {
        mAnimator.params.p1 = cast(int)(mAngles[0]/PI*180);
        mAnimator.params.p2 = cast(int)(mAngles[1]/PI*180);
    }

    public void update(ref SequenceUpdate v) {
        mAnimator.pos = v.position;
        float[2] set_angle;
        set_angle[0] = v.rotation_angle;
        set_angle[1] = v.pointto_angle;
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
        updateAngle();
    }

    public void setState(SequenceState sstate) {
        auto state = castStrict!(WormState)(sstate);
        if (!state)
            return;
        if (state is mQueuedState)
            return;
        WormState curstate = mCurSubSeq ? mCurSubSeq.owner : null;
        if (curstate is state)
            return;
        std.stdio.writefln("set state: ", sstate.name);
        //possibly start state change
        //look if the leaving sequence should play
        bool play_leave = false;
        if (curstate) {
            play_leave |= curstate.hasLeaveTransition(sstate);
        }
        std.stdio.writefln("play leave: ", play_leave);
        if (!mCurSubSeq || !play_leave) {
            //start new state, skip whatever did go on before
            resetSubSequence();
            mQueuedState = null;
            initSequence(state, SeqType.Enter);
        } else if (mCurSubSeq && play_leave) {
            //current -> leave
            initSequence(curstate, SeqType.Leave);
            mQueuedState = state;
        } else {
            //only queue it
            mQueuedState = state;
        }
    }

    public void getInfos(ref SequenceUpdate v) {
        v.position = mAnimator.pos;
        v.rotation_angle = mAngles[0];
        v.pointto_angle = mAngles[1];
    }

    public bool readyflag() {
        //if no state, consider it ready
        return !mCurSubSeq || mCurSubSeq.ready;
    }

    public Rect2i bounds() {
        return type.bb + mAnimator.pos;
    }

    public SceneObject graphic() {
        return mAnimator;
    }
}
