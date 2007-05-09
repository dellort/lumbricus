module game.animation;

import game.scene;
import game.common;
import framework.framework;
import utils.configfile;
import utils.time;

class Animation {
    private FrameInfo[] mFrames;
    private Vector2i size;

    private struct FrameInfo {
        int durationMS;
        Surface surface;
    }

    this (ConfigNode node) {
        assert(node !is null);
        int duration = node.getIntValue("duration", 10);
        Surface bmp = gCommon.loadGraphic(node.getStringValue("image"));
        assert(bmp !is null);
        int frames = node.getIntValue("frames", 0);
        size.x = node.getIntValue("width", 0);
        size.y = node.getIntValue("height", 0);
        mFrames.length = frames;
        for (int n = 0; n < frames; n++) {
            mFrames[n].surface = bmp.getSubSurface(Vector2i(size.x*n, 0),
                Vector2i(size.x, size.y));
            mFrames[n].durationMS = duration;
        }
    }
}

//does animation
class Animator : SceneObjectPositioned {
    private Animation mAni, mAniNext;
    private bool mAniRepeat, mAniNextRepeat;
    private uint mLastFrame;
    private Time mLastFrameTime;
    private void delegate(Animator sender) mOnNoAnimation;

    //animation to play after current animation finished
    void setNextAnimation(Animation next, bool repeating) {
        if (mAni) {
            mAniNext = next;
            mAniNextRepeat = repeating;
            //cancel repeating of current animation
            mAniRepeat = false;
        } else {
            setAnimation(next, repeating);
        }
    }

    void setAnimation(Animation ani, bool repeating) {
        mAni = ani;
        mAniRepeat = repeating;
        mAniNext = null;
        mLastFrame = 0;
        mLastFrameTime = gCommon.gameTimeAnimations;
    }

    void setOnNoAnimation(void delegate(Animator) cb) {
        mOnNoAnimation = cb;
    }

    this(Scene s) {
        super(s);
    }

    void draw(Canvas canvas) {
        if (!mAni || mAni.mFrames.length == 0)
            return;
        Animation.FrameInfo fi = mAni.mFrames[mLastFrame];
        if ((gCommon.gameTimeAnimations - mLastFrameTime).msecs > fi.durationMS) {
            mLastFrame = (mLastFrame + 1) % mAni.mFrames.length;
            mLastFrameTime = gCommon.gameTimeAnimations;
            if (mLastFrame == 0) {
                //end of animation, check what to do now...
                if (mAniNext) {
                    setAnimation(mAniNext, mAniRepeat);
                } else if (mAniRepeat) {
                    //ok.
                } else {
                    //hum...
                    if (mOnNoAnimation)
                        mOnNoAnimation(this);
                }
            }
        }

        //draw it.
        //xxx: this is the last frame... should draw the current one
        canvas.draw(fi.surface, pos);
    }
}
