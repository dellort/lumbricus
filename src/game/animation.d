module game.animation;

import game.scene;
import game.common;
import framework.framework;
import utils.configfile;
import utils.time;

class Animation {
    private FrameInfo[] mFrames;
    private Vector2i mSize;
    private bool mRepeat, mReverse;
    private Surface mImage;
    private Surface mMirroredImage;
    private Texture mImageTex;
    private Texture mMirrorTex;

    private struct FrameInfo {
        int durationMS;
        //in image...
        Vector2i pos, size;
    }

    this (ConfigNode node, char[] relPath = "") {
        assert(node !is null);
        int duration = node.getIntValue("duration", 10);
        mImage = globals.loadGraphic(relPath ~ node.getStringValue("image"));
        if (!mImage)
            throw new Exception("Failed to load animation bitmap");
        mImageTex = mImage.createTexture();
        int frames = node.getIntValue("frames", 0);
        mSize.x = node.getIntValue("width", 0);
        mSize.y = node.getIntValue("height", 0);
        mRepeat = node.getBoolValue("repeat", false);
        mReverse = node.getBoolValue("backwards", false);
        mFrames.length = frames;
        for (int n = 0; n < frames; n++) {
            mFrames[n].pos = Vector2i(mSize.x*n, 0);
            mFrames[n].size = mSize;
            mFrames[n].durationMS = duration;
        }
    }

    public Vector2i size() {
        return mSize;
    }

    public uint frameCount() {
        return mFrames.length;
    }

    public void enableMirror() {
        //actually, one would need to mirror frame per frame, ignore for now
        //(can be solved by making the ani-strips vertical, not horizontal!)
        if (!mMirroredImage) {
            mMirroredImage = mImage.createMirroredY();
            mMirrorTex = mMirroredImage.createTexture();
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
    private bool mMirrored;

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

    void setMirror(bool mirror) {
        mMirrored = mirror;
        if (mAni)
            mAni.enableMirror();
    }

    void setAnimation(Animation ani) {
        mAni = ani;
        mAniRepeat = ani ? ani.mRepeat : false;
        mAniReverse = ani ? ani.mReverse : false;
        mReversed = false;
        mAniNext = null;
        setFrame(0);

        if (ani) {
            thesize = ani.mSize;
            if (mMirrored)
                mAni.enableMirror();
        }
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

    void draw(Canvas canvas) {
        if (!mAni || mAni.mFrames.length == 0)
            return;
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
                    if (mOnNoAnimation)
                        mOnNoAnimation(this);
                }
                mReversed = !mReversed;
            }
            fi = mAni.mFrames[mCurFrame];
        }

        //draw it.
        auto tex = mMirrored ? mAni.mMirrorTex : mAni.mImageTex;
        canvas.draw(tex, pos, fi.pos, fi.size);
    }
}
