module game.animation;

import game.scene;
import game.common;
import framework.framework;
import utils.configfile;
import utils.misc;
import utils.time;
import utils.log;

struct AnimationData {
    int duration = 20;
    Transparency trans = Transparency.Colorkey;
    char[] imagePath = "(invalid)";
    int frames = 1;
    Vector2i size = {0, 0};
    bool repeat = false;
    bool reverse = false;

    public static AnimationData opCall(ConfigNode node) {
        AnimationData ret;
        ret.duration = node.getIntValue("duration", ret.duration);;
        char[] imgmode = node.getStringValue("transparency","colorkey");
        if (imgmode == "alpha") {
            ret.trans = Transparency.Alpha;
        }
        ret.imagePath = node.getStringValue("image",ret.imagePath);
        ret.frames = node.getIntValue("frames", ret.frames);
        ret.size.x = node.getIntValue("width", ret.size.x);
        ret.size.y = node.getIntValue("height", ret.size.y);
        ret.repeat = node.getBoolValue("repeat", ret.repeat);
        ret.reverse = node.getBoolValue("backwards", ret.reverse);
        return ret;
    }
}

class Animation {
    private FrameInfo[] mFrames;
    private Vector2i mSize;
    private bool mRepeat, mReverse;
    private Surface mImage;
    private Texture mImageTex;
    private Animation mMirrored, mBackwards;

    private struct FrameInfo {
        int durationMS;
        //in image...
        Vector2i pos, size;
    }

    /*this (ConfigNode node, char[] relPath = "") {
        assert(node !is null);
        AnimationData animData = AnimationData(node);
        this(animData, relPath);
    }*/

    this(AnimationData animData, char[] relPath = "") {
        mImage = globals.loadGraphic(relPath ~ animData.imagePath,
            animData.trans);
        if (!mImage)
            throw new Exception("Failed to load animation bitmap");
        mImageTex = mImage.createTexture();
        mSize = animData.size;
        mRepeat = animData.repeat;
        mReverse = animData.reverse;
        mFrames.length = animData.frames;
        for (int n = 0; n < animData.frames; n++) {
            mFrames[n].pos = Vector2i(mSize.x*n, 0);
            mFrames[n].size = mSize;
            mFrames[n].durationMS = animData.duration;
        }
    }

    //for getMirroredY()
    private this () {
    }

    public Vector2i size() {
        return mSize;
    }

    public uint frameCount() {
        return mFrames.length;
    }

    //xxx I don't like that, but it was simpler with the rest of the code
    //(+ I'm too lazy)
    Animation getBackwards() {
        if (!mBackwards) {
            auto n = new Animation();
            n.mFrames = this.mFrames.dup;
            n.mSize = this.mSize;
            n.mRepeat = this.mRepeat;
            n.mReverse = this.mReverse;
            n.mImage = this.mImage;
            n.mImageTex = this.mImageTex;
            n.mBackwards = this;

            n.doReverse();

            mBackwards = n;
        }
        return mBackwards;
    }

    //get an animation which contains this animation with mirrored frames
    //(mirrored across Y axis)
    Animation getMirroredY() {
        if (!mMirrored) {
            auto n = new Animation();
            n.mFrames = this.mFrames.dup;
            n.mSize = this.mSize;
            n.mRepeat = this.mRepeat;
            n.mReverse = this.mReverse;
            n.mImage = this.mImage.createMirroredY();
            n.mImageTex = n.mImage.createTexture();
            n.mMirrored = this;

            n.doReverse();

            mMirrored = n;
        }
        return mMirrored;
    }

    private void doReverse() {
        //reverse the frames, this should restore the correct frame order
        for (int i = 0; i < mFrames.length/2; i++) {
            swap(mFrames[i], mFrames[$-1-i]);
        }
    }
}

//does animation
class Animator : SceneObjectPositioned {
    protected Animation mAni, mAniNext;
    private bool mAniRepeat, mAniReverse;
    private uint mCurFrame;
    private Time mCurFrameTime;
    private void delegate(Animator sender) mOnNoAnimation;
    private bool mReversed = false;

    public bool paused;

    //animation to play after current animation finished
    void setNextAnimation(Animation next) {
        if (mAni) {
            mAniNext = next;
            //cancel repeating of current animation
            mAniRepeat = false;
        } else {
            setAnimation(next);
        }
    }

    void setAnimation(Animation ani) {
        mAni = ani;
        mAniRepeat = ani ? ani.mRepeat : false;
        mAniReverse = ani ? ani.mReverse : false;
        mReversed = false;
        mAniNext = null;
        setFrame(0);

        size = ani ? ani.mSize : Vector2i(0);
    }

    Animation currentAnimation() {
        return mAni;
    }

    void setOnNoAnimation(void delegate(Animator) cb) {
        mOnNoAnimation = cb;
    }

    void setFrame(uint frameIdx) {
        if (mAni && frameIdx<mAni.frameCount) {
            mCurFrame = frameIdx;
            mCurFrameTime = globals.gameTimeAnimations;
        }
    }

    void draw(Canvas canvas, SceneView parentView) {
        if (!mAni || mAni.mFrames.length == 0) {
            if (mOnNoAnimation)
                mOnNoAnimation(this);
            if (!mAni || mAni.mFrames.length == 0)
                return;
        }
        Animation.FrameInfo fi = mAni.mFrames[mCurFrame];
        while ((globals.gameTimeAnimations - mCurFrameTime).msecs > fi.durationMS
            && !paused)
        {
            if (mReversed) {
                if (mCurFrame > 0)
                    mCurFrame = mCurFrame - 1;
            } else
                mCurFrame = (mCurFrame + 1) % mAni.mFrames.length;
            mCurFrameTime += timeMsecs(fi.durationMS);
            if (mCurFrame == 0) {
                //end of animation, check what to do now...
                if (mAniReverse && !mReversed) {
                    mCurFrame = mAni.mFrames.length - 1;
                } else if (mAniNext) {
                    setAnimation(mAniNext);
                } else if (mAniRepeat) {
                    //ok.
                } else {
                    //hum...
                    if (mOnNoAnimation) {
                        mOnNoAnimation(this);
                        //xxx sorry that could have set a new animation, but we
                        //don't knoiw anything about the new one
                        //so recheck on the next frame
                        gDefaultLog("fool!");
                        return;
                    }
                }
                mReversed = !mReversed;
            }
            fi = mAni.mFrames[mCurFrame];
        }

        //draw it.
        canvas.draw(mAni.mImageTex, pos, fi.pos, fi.size);
    }
}
