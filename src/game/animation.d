module game.animation;

import game.scene;
import game.common;
import framework.framework;
import game.resources;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.log;
import math = std.math;
import str = std.string;

//handlers to load specialized animation descriptions
//(because the generic one is too barfed)
private alias AnimationData function(ConfigNode node) AnimationLoadHandler;
private AnimationLoadHandler[char[]] gAnimationLoadHandlers;

ProcessedAnimationData parseAnimation(ConfigNode from) {
    auto name = from.getStringValue("handler", "old");
    assert(name in gAnimationLoadHandlers, "unknown animation load handler");
    return gAnimationLoadHandlers[name](from).preprocess();
}

Animation loadAnimation(ProcessedAnimationData data) {
    return new Animation(data);
}

//slightly overengeneered, but actually not that argh.
private alias int function(int p, int count) ParamConvertDelegate;
private ParamConvertDelegate[char[]] gParamConverters;

void initAnimations() {
    //documentation on this stuff see implementations

    gParamConverters["none"] = &paramConvertNone;
    gParamConverters["step3"] = &paramConvertStep3;
    gParamConverters["twosided"] = &paramConvertTwosided;
    gParamConverters["rot360"] = &paramConvertFreeRot;
    gParamConverters["rot180"] = &paramConvertFreeRot2;

    //normal worm, standing or walking
    gAnimationLoadHandlers["worm"] = &loadWormAnimation;
    /*
    //worm holding a weapon (with weapon-angle as param2)
    gAnimationLoadHandlers["worm_weapon"] = &loadWormWeaponAnimation;
    //360 degrees graphic, not animated
    gAnimationLoadHandlers["360"] = &loadWormWeaponAnimation;
    */

    gAnimationLoadHandlers["generic"] = &loadGenericAnimation;
    gAnimationLoadHandlers["old"] = &loadOldAnimation;
}

public enum AnimationParamType {
    Null = 0,
    Time = 1,
    P1 = 2,
    P2 = 3,
}

//data for yet-to-be-loaded animations
struct AnimationData {
    //an animation can consists by several sections, which are played in order
    //i.e. there can be an entry and loop animation
    //(used for get-weapon animation)
    AnimationSection[] sections;

    //create internal data for resources
    ProcessedAnimationData preprocess() {
        ProcessedAnimationData res;
        res.mData = *this;
        foreach (inout AnimationSection s; res.mData.sections) {
            s.preprocess();
        }
        return res;
    }
}
struct AnimationSection {
    //loop: replay animation on end, else stop on last frame (or go to next
    //      animation/section if there's one)
    //loop_reverse: play backwards on each 2nd loop (only used if loop is true)
    bool loop = true, loop_reverse = false;

    //method to convert param values into index values
    ParamConvertDelegate[2] paramConvert
        = [&paramConvertNone, &paramConvertNone];

    //offset added to each param before conversion
    int[2] paramOffset;

    //where index A and B map to; A is the frame index, and B the file index
    //i.e. if AB[0] is AnimationParamType.P1, param1 maps to the frame index
    AnimationParamType[2] AB = [AnimationParamType.Time, AnimationParamType.P1];

    int frameTimeMs = 50;

    //frameSize/frameCount is for the frames in the following bitmaps
    Vector2i frameSize;
    int frameCount;
    BitmapResource[] bitmaps;

    //append mirrored (on Y axis) bitmaps to bitmaps list
    bool mirror_Y_B = false;
    //append mirrored (on Y axis) bitmaps to frame rows
    bool mirror_Y_A = false;

    private {
        bool mPreprocessed = false;
        BitmapResource[] mMirrors;

        void preprocess() {
            if (mPreprocessed)
                return;

            if (mirror_Y_B || mirror_Y_A) {
                //create mirrors of the yet existing surfaces
                for (int n = 0; n < bitmaps.length; n++) {
                    auto mirror = bitmaps[n];
                    assert(mirror !is null);
                    //sucks *g*
                    auto mirrored = mirror.createMirror();
                    mMirrors ~= mirrored;
                }
            }

            mPreprocessed = true;
        }
    }
}

//struct to assert only preprocessed animations are passed to Animation.this()
struct ProcessedAnimationData {
    private {
        AnimationData mData;
    }
}

//NOTE: no AnimationData necessary, because "createProcessedAnimation" is
//obsoleted by the features supported by this class
class Animation {
private:
    enum SectionType {
        Enter,
        Loop,
    }
    Section[] mSections;
    Section* mStartSection;

    //indexed by the FrameInfo.texture field
    BitmapResource[] mSurfaces;
    //created on demand (?)
    Texture[] mTextures;

    //largest of all frames
    Vector2i mSize;

    //finish the current animation, if new animation is set with force == false
    bool mFinishAnimationOnReplace = false;

    alias AnimationParamType ParamType;

    //enter, loop or exit section (depending from what's happening)
    struct Section {
        Section* next;
        //loop_reverse is only used when loop is true
        bool loop, loop_reverse;

        //per frame and per loop
        int frameTimeMs, lengthMs;
        //from the time dependant count field
        int frameCount;

        ParamConvertDelegate[2] convertParam;
        int[2] Poffset; //offset value added to each of the params
        int[2] usedfor; //reverse for "from", indexed by parameter

        //number of frames (must be the same in all strips)
        //please note that it isn't indexed by the parameter-nr., but A or B
        int[2] count; //count of items for index A (0) and B (1)
        //where the indices A and B come from
        ParamType[2] from;
        bool timeDependant;     //if one of Afrom or Bfrom is the time

        //xxx: if we don't need this (different sized frames etc.), the
        //     following could be greatly simplified, i.e. B == FrameInfo.texture
        //2D-array, length frameCount*stripCount, see getFrame()
        FrameInfo[] strips;
        //A, B = as in the config file; A selects frame index, B selects strip
        FrameInfo* framePtr(int A, int B) {
            assert(A >= 0);
            assert(A < count[0]);
            assert(B >= 0);
            assert(B < count[1]);
            return &strips[count[0]*B + A];
        }
    }

    struct FrameInfo {
        //sub-rectangle of a texture
        Vector2i pos;
        Vector2i size;
        //the following can be different for each frame
        //index into mSurfaces/mTextures
        int texture;
    }

    public this(ProcessedAnimationData ani) {
        AnimationData data = ani.mData;

        void loadSection(inout AnimationSection section, inout Section to) {
            assert(section.mPreprocessed, "must call AnimationData.preprocess");
            //copy and possibly verify
            to.frameTimeMs = section.frameTimeMs;
            to.loop = section.loop;
            to.loop_reverse = to.loop ? section.loop_reverse : false;
            to.convertParam[] = section.paramConvert;
            to.from[] = section.AB;
            to.Poffset[] = section.paramOffset;

            int bitmapoffset = mSurfaces.length;
            int mirroredoffset;
            mSurfaces ~= section.bitmaps;

            to.count[0] = section.frameCount;
            to.count[1] = section.bitmaps.length;
            assert(to.count[0] > 0);
            assert(to.count[1] > 0);

            if (section.mirror_Y_B || section.mirror_Y_A) {
                mirroredoffset = mSurfaces.length;
                mSurfaces ~= section.mMirrors;
                if (section.mirror_Y_A) {
                    to.count[0] *= 2; //by A
                }
                if (section.mirror_Y_B) {
                    to.count[1] *= 2; //mirrored surfaces addressed by B
                }
            }

            //maximum size => size of the animation
            mSize.x = max(section.frameSize.x, mSize.x);
            mSize.y = max(section.frameSize.y, mSize.y);

            //create frame infos
            to.strips.length = to.count[0] * to.count[1];
            for (int a = 0; a < to.count[0]; a++) {
                auto pos = Vector2i(a*section.frameSize.x, 0);
                int start = bitmapoffset;
                if (section.mirror_Y_A && a >= to.count[0]/2) {
                    //extends along the x-axis only virtually
                    //actually map to another bitmap with same x-offsets
                    pos.x = pos.x - (to.count[0]/2)*section.frameSize.x;
                    start = mirroredoffset;
                }
                for (int b = 0; b < to.count[1]; b++) {
                    FrameInfo* info = to.framePtr(a, b);
                    if (section.mirror_Y_B && b >= to.count[1]/2) {
                        //mirror on x-axis (so it's not played backwards)
                        pos.x = (to.count[0]-1)*section.frameSize.x - pos.x;
                    }
                    info.pos = pos;
                    info.size = section.frameSize;
                    info.texture = start + b;
                }
            }

            //precalculate some infos
            int fortime = -1;
            fortime = (to.from[0] == ParamType.Time) ? 0 : fortime;
            fortime = (to.from[1] == ParamType.Time) ? 1 : fortime;
            to.timeDependant = (fortime != -1);
            to.frameCount = to.timeDependant ? to.count[fortime] : 1;
            to.lengthMs = to.frameCount * to.frameTimeMs;

            to.usedfor[0] = -1; to.usedfor[1] = -1;
            //for each parameter (P1, P2)
            for (int n = 0; n < 2; n++) {
                if (to.from[0] == ParamType.P1+n) {
                    to.usedfor[n] = 0;
                }
                if (to.from[1] == ParamType.P1+n) {
                    if (to.usedfor[n] >= 0) {
                        gDefaultLog("error: parameter %d used twice", n);
                        assert(false);
                    }
                    to.usedfor[n] = 1;
                }
            }
        }

        mSections.length = data.sections.length;
        foreach (int n, inout AnimationSection section; data.sections) {
            loadSection(section, mSections[n]);
        }

        //link the sections (sigh, why do I do that)
        Section* prev_ptr = null;
        foreach_reverse(inout Section s; mSections) {
            s.next = prev_ptr;
            prev_ptr = &s;
        }
        mStartSection = prev_ptr;
    }

    public Vector2i size() {
        return mSize;
    }

    //load the textures (and bitmaps) if they weren't already
    public void assertStuffLoaded() {
        if (!mTextures) {
            mTextures.length = mSurfaces.length;
            for (int n = 0; n < mTextures.length; n++) {
                mTextures[n] = mSurfaces[n].get().createTexture();
            }
        }
    }
}

//private animation state
struct AnimationState {
private:
    alias Animation.Section Section;
    alias Animation.ParamType ParamType;
    bool mLoopBack; //looping back for loop_reverse
    bool mStopTime; //animation is on end, keep showing last frame
    Animation mAnimation, mNextAnimation;
    Section* mCurrentSection;
    bool mParamCacheValid; //mParams[] reflects state in mP[]
    int[2] mP;  //parameters (mostly angle + unused or secundary angle)
    int[ParamType.max+1] mParams; //cached parameters (including time)
    int mTimeMs; //time before how many ms the animation(-section) was started
    Time mLast;  //last time check
public:
    void setParams(int p1, int p2) {
        if (mP[0] != p1 || mP[1] != p2) {
            mP[0] = p1; mP[1] = p2;
            mParamCacheValid = false;
        }
    }
    private bool needTime() {
        return mCurrentSection && mCurrentSection.timeDependant && !mStopTime;
    }
    //force = replace current animation immediately
    //  else respect animarion-settings, i.e. wait until animation done
    void setAnimation(Animation animation, bool force) {
        if (mAnimation && !force && mAnimation.mFinishAnimationOnReplace
            && needTime())
        {
            //just set this animation "next" time
            mNextAnimation = animation;
            return;
        }
        initAnimation(animation);
    }
    private void initAnimation(Animation animation) {
        mAnimation = animation;
        mNextAnimation = null;
        mCurrentSection = null;
        if (animation) {
            mCurrentSection = mAnimation.mStartSection;
            mLast = globals.gameTimeAnimations;
            mTimeMs = 0;
            mLoopBack = false;
            mStopTime = false;
            mParamCacheValid = false;
            //initialize i.e. frame indices
            updateTime();
        }
    }
    //current loop of mCurrentSection has ended
    //decide what's next and return it
    //all parameters from the loop are still valid, and not reset after this
    //currently these is just mLoopBack: play current animation backwards
    private Section* onNextAnimation() {
        if (mNextAnimation) {
            mLoopBack = false;
            mAnimation = mNextAnimation;
            mNextAnimation = null;
            return mAnimation.mStartSection;
        } else if (mCurrentSection.loop) {
            if (mCurrentSection.loop_reverse)
                mLoopBack = !mLoopBack;
            return mCurrentSection;
        } else if (mCurrentSection.next) {
            mLoopBack = false;
            return mCurrentSection.next;
        }
        //keep showing last frame (special case)
        return null;
    }
    //next frame
    public void updateTime() {
        if (!needTime())
            return;

        auto time = globals.gameTimeAnimations;
        mTimeMs += (time - mLast).msecs;
        mLast = time;

        while (!mStopTime) {
            //normal case
            if (mTimeMs < mCurrentSection.lengthMs) {
                int nframe = mTimeMs / mCurrentSection.frameTimeMs;
                assert(nframe < mCurrentSection.frameCount);
                if (mLoopBack) { //play backwards
                    nframe = mCurrentSection.frameCount - nframe - 1;
                }
                assert(nframe < mCurrentSection.frameCount);
                assert(nframe >= 0);
                mParams[ParamType.Time] = nframe;
                return;
            }

            //time flowed over; get next run (i.e. loop, next animation, etc.)
            Section* next = onNextAnimation();
            if (!next) {
                //fix to current frame and make sure this code is not executed
                //again (and leave mTimeMs to anything, don't care)
                mParams[ParamType.Time] =
                    mLoopBack ? 0 : mCurrentSection.frameCount - 1;
                mStopTime = true;
                return;
            }
            //remove time of the last animation-run, advance to next animation
            mTimeMs -= mCurrentSection.lengthMs;
            mCurrentSection = next;
            mParamCacheValid = false; //argh
        }
    }
    public void drawFrame(Canvas canvas, Vector2i at) {
        auto section = mCurrentSection;
        if (!section) {
            return;
        }

        assert(mAnimation !is null);

        if (!mParamCacheValid) {
            for (int n = 0; n < 2; n++) {
                int usedfor = section.usedfor[n];
                if (usedfor >= 0) {
                    auto convert = section.convertParam[n];
                    auto count = section.count[usedfor];
                    auto nval = convert(mP[n] + section.Poffset[n], count);
                    if (nval >= count)
                        nval = count - 1;
                    if (nval < 0)
                        nval = 0;
                    mParams[ParamType.P1+n] = nval;
                }
            }
            mParamCacheValid = true;
        }

        Animation.FrameInfo* fi = section.framePtr(mParams[section.from[0]],
            mParams[section.from[1]]);

        //origin is in "at", but center frame in animation itself
        at += (size - fi.size) / 2;
        mAnimation.assertStuffLoaded();
        canvas.draw(mAnimation.mTextures[fi.texture], at, fi.pos, fi.size);
    }
    public Animation currentAnimation() {
        return mAnimation;
    }
    public Vector2i size() {
        return mAnimation ? mAnimation.mSize : Vector2i(0, 0);
    }
}

//your friendly wrapper around the actual animation code
class Animator : SceneObjectPositioned {
    private AnimationState mState;
    //private void delegate(Animator sender) mOnNoAnimation;

    AnimationState* animationState() {
        return &mState;
    }

    //animation to play after current animation finished
    //force parameter is documented in at least two other places
    void setNextAnimation(Animation next, bool force) {
        mState.setAnimation(next, force);
        size = mState.size;
    }
    void setAnimation(Animation n) {
        setNextAnimation(n, true);
    }

    Animation currentAnimation() {
        return mState.currentAnimation;
    }

    //void onNoAnimation(void delegate(Animator) cb) {
    //    mOnNoAnimation = cb;
    //}

    void draw(Canvas canvas) {
       mState.updateTime();
       mState.drawFrame(canvas, pos);
       size = mState.size;
    }
}

//return the index of the angle in "angles" which is closest to "angle"
//all units in degrees, return values is always an index into angles
private uint pickNearestAngle(int[] angles, int iangle) {
    //pick best angle (what's nearer)
    uint closest;
    float angle = iangle/180.0f*math.PI;
    float cur = float.max;
    foreach (int i, int x; angles) {
        auto d = angleDistance(angle,x/180.0f*math.PI);
        if (d < cur) {
            cur = d;
            closest = i;
        }
    }
    return closest;
}

//param converters

//default
private int paramConvertNone(int angle, int count) {
    return angle;
}
//expects count to be 6 (for the 6 angles)
private int paramConvertStep3(int angle, int count) {
    static int[] angles = [90,90-45,90+45,270,270+45,270-45];
    return pickNearestAngle(angles, angle);
}
//expects count to be 2 (two sides)
private int paramConvertTwosided(int angle, int count) {
    return (angle % 360) < 180 ? 0 : 1;
}
//360 degrees freedom
private int paramConvertFreeRot(int angle, int count) {
    return cast(int)(((angle % 360) / 360.0f) * (count - 1));
}
//180 degrees
//(overflows, used for weapons, it's hardcoded that it can use 180 degrees only)
private int paramConvertFreeRot2(int angle, int count) {
    return cast(int)(((angle % 360) / 180.0f) * (count - 1));
}

//animation load handlers

private BitmapResource doLoadGraphic(char[] file) {
    //I don't get it how to properly use the res-manager
    //currently shut it up by using the filename as id...
    return globals.resources.createResourceFromFile!(BitmapResource)(file);
}

private BitmapResource[] loadFooImages(char[] templ, int offset, int count) {
    BitmapResource[] res;
    res.length = count;
    for (int n = 0; n < count; n++) {
        char[] name = str.replace(templ, "#", str.toString(offset + n));
        res[n] = doLoadGraphic(name);
    }
    return res;
}

private AnimationData loadWormAnimation(ConfigNode node) {
    AnimationData res;
    AnimationSection section;
    section.bitmaps = loadFooImages(node.getPathValue("image"), node.getIntValue("offset"), 3);
    int[] dims = node.getValueArray!(int)("size");
    assert(dims.length == 2);
    section.frameSize.x = dims[0];
    section.frameSize.y = dims[1];
    section.frameCount = node.getIntValue("frames");
    section.paramConvert[0] = &paramConvertStep3;
    section.loop_reverse = true;
    section.mirror_Y_B = true;
    res.sections = [section];
    return res;
}

private AnimationData loadGenericAnimation(ConfigNode node) {
    AnimationSection loadSection(ConfigNode node) {
        AnimationSection to;

        //--- load/process files
        char[][] files = node.getSubNode("image").getValueList();
        foreach (inout char[] f; files) {
            f = node.fixPathValue(f);
        }
        to.bitmaps.length = files.length;
        foreach (int n, char[] file; files) {
            to.bitmaps[n] = doLoadGraphic(file);
        }

        to.mirror_Y_B = node.getBoolValue("mirror_Y_B");
        to.mirror_Y_A = node.getBoolValue("mirror_Y_A");

        //measures: width height framecount
        int[] measures = node.getValueArray!(int)("measures");
        assert(measures.length==3, "add error handling here");
        to.frameSize.x = measures[0];
        to.frameSize.y = measures[1];
        to.frameCount = measures[2];

        //--- book keeping for the angle stuff etc....

        void loadParamStuff(int index, char[] name) {
            auto val = node.getStringValue(name, "none");
            if (!(val in gParamConverters)) {
                assert(false, "not found; add error handling");
            }
            to.paramConvert[index] = gParamConverters[val];

            to.paramOffset[index] = node.getIntValue(name ~ "offset");
        }

        loadParamStuff(0, "param1");
        loadParamStuff(1, "param2");

        //what A/B is wired to

        void getAB(int index, char[] value, int def) {
            static const char[][] cAB = ["none", "time", "param1", "param2"];
            int ab = def;
            if (value) {
                ab = arraySearch(cAB, value, def);
            }
            assert(ab >= 0 && ab <= AnimationParamType.max, "TODO: error handling");
            to.AB[index] = cast(AnimationParamType)ab;
        }

        char[][] vals = node.getValueArray!(char[])("AB");
        getAB(0, vals.length >= 1 ? vals[0] : "", AnimationParamType.Time);
        getAB(1, vals.length >= 2 ? vals[1] : "", AnimationParamType.P1);

        to.loop = node.getBoolValue("loop");
        to.loop_reverse = node.getBoolValue("loop_reverse");

        return to;
    }

    AnimationData data;

    ConfigNode enter = node.findNode("enter");
    ConfigNode loop = node.findNode("loop");

    assert(loop !is null, "no loop section");
    if (enter) {
        data.sections.length = 2;
        data.sections[0] = loadSection(enter);
        data.sections[1] = loadSection(loop);
    } else {
        data.sections.length = 1;
        data.sections[0] = loadSection(loop);
    }

    return data;
}

//"old" format... these configfile are scattered everywhere...
private AnimationData loadOldAnimation(ConfigNode node) {
    AnimationData data;
    data.sections.length = 1;
    AnimationSection* section = &data.sections[0];
    section.bitmaps = [doLoadGraphic(node.getPathValue("image"))];
    section.loop = node.getBoolValue("repeat");
    section.loop_reverse = node.getBoolValue("backwards");
    section.frameSize.x = node.getIntValue("width");
    section.frameSize.y = node.getIntValue("height");
    section.frameTimeMs = node.getIntValue("duration", 50);
    section.frameCount = node.getIntValue("frames");
    return data;
}

//return distance of two angles in radians
float angleDistance(float a, float b) {
    auto r = math.abs(realmod(a, math.PI*2) - realmod(b, math.PI*2));
    if (r > math.PI) {
        r = math.PI*2 - r;
    }
    return r;
}
