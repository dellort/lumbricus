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

    private struct FrameInfo {
        int durationMS;
        TextureRef frametex;
    }

    this (ConfigNode node, char[] relPath = "") {
        assert(node !is null);
        int duration = node.getIntValue("duration", 10);
        Surface bmp = globals.loadGraphic(relPath ~ node.getStringValue("image"));
        if (!bmp)
            throw new Exception("Failed to load animation bitmap");
        Texture tex = bmp.createTexture();
        int frames = node.getIntValue("frames", 0);
        mSize.x = node.getIntValue("width", 0);
        mSize.y = node.getIntValue("height", 0);
        mRepeat = node.getBoolValue("repeat", false);
        mReverse = node.getBoolValue("backwards", false);
        mFrames.length = frames;
        for (int n = 0; n < frames; n++) {
            mFrames[n].frametex.texture = tex;
            mFrames[n].frametex.pos = Vector2i(mSize.x*n, 0);
            mFrames[n].frametex.size = mSize;
            mFrames[n].durationMS = duration;
        }
    }

    public Vector2i size() {
        return mSize;
    }

    public uint frameCount() {
        return mFrames.length;
    }
}

//does animation
class Animator : SceneObjectPositioned {
    protected Animation mAni, mAniNext;
    private bool mAniRepeat, mAniReverse;
    private uint mLastFrame;
    private Time mLastFrameTime;
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
        mLastFrame = 0;
        mLastFrameTime = globals.gameTimeAnimations;

        if (ani) {
            thesize = ani.mSize;
        }
    }

    void setOnNoAnimation(void delegate(Animator) cb) {
        mOnNoAnimation = cb;
    }

    void setFrame(uint frameIdx) {
        if (mAni && frameIdx<mAni.frameCount)
            mLastFrame = frameIdx;
    }

    void draw(Canvas canvas) {
        if (!mAni || mAni.mFrames.length == 0)
            return;
        Animation.FrameInfo fi = mAni.mFrames[mLastFrame];
        if ((globals.gameTimeAnimations - mLastFrameTime).msecs > fi.durationMS
            && !paused)
        {
            if (mReversed) {
                if (mLastFrame > 0)
                    mLastFrame = mLastFrame - 1;
            } else
                mLastFrame = (mLastFrame + 1) % mAni.mFrames.length;
            mLastFrameTime = globals.gameTimeAnimations;
            if (mLastFrame == 0) {
                //end of animation, check what to do now...
                if (mAniReverse && !mReversed) {
                    mLastFrame = mAni.mFrames.length - 1;
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
        }

        //draw it.
        //xxx: this is the next frame... should draw the current one
        canvas.draw(fi.frametex, pos);
    }
}
