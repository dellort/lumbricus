module gui.messageviewer;

import framework.framework;
import framework.font;
import common.scene;
import common.common;
import common.visual;
import gui.widget;
import utils.misc;
import utils.time;
import utils.queue;

private class MessageViewer : Widget {
    private Queue!(char[]) mMessages;
    private char[] mCurrentMessage;
    private Font mFont;
    private Time mLastFrame;
    private int mPhase; //0 = nothing, 1 = blend in, 2 = show, 3 = blend out, 4 = wait
    private Time mPhaseStart; //start of current phase
    private Vector2i mMessageSize;
    private float mMessagePos;
    private float mMessageWay; //way over which message is scrolled

    static const int cPhaseTimingsMs[] = [0, 150, 1000, 150, 200];

    //offset of message from upper border
    const cMessageOffset = 5;
    const Vector2i cMessageBorders = {7, 3};

    this() {
        mFont = globals.framework.fontManager.loadFont("messages");
        mMessages = new Queue!(char[]);
        mLastFrame = timeCurrentTime();
    }

    void addMessage(char[] msg) {
        mMessages.push(msg);
    }

    //return true as long messages are displayed
    bool working() {
        return !mMessages.empty || mPhase != 0;
    }

    bool idle() {
        return !working();
    }

    override void simulate() {
        Time phaseT = timeMsecs(cPhaseTimingsMs[mPhase]);
        Time cur = timeCurrentTime;
        Time deltaT = cur - mLastFrame;
        mLastFrame = cur;
        Time diff = cur - mPhaseStart;
        if (diff >= phaseT) {
            //end of current phase
            if (mPhase != 0) {
                mPhase++;
                mPhaseStart = cur;
            }
            if (mPhase > 4) {
                //done, no current message anymore
                mCurrentMessage = null;
                mPhase = 0;
            }
        }

        //(division by zero and NaNs in some cases where the value isn't needed)
        auto messagedelta = mMessageWay / (cPhaseTimingsMs[mPhase]/1000.0f);

        //make some progress
        switch (mPhase) {
            case 0:
                if (!mMessages.empty) {
                    //put new message
                    mPhase = 1;
                    mPhaseStart = cur;
                    mCurrentMessage = mMessages.pop();
                    mMessageSize = mFont.textSize(mCurrentMessage);
                    mMessagePos = -mMessageSize.y - cMessageBorders.y*2;
                    mMessageWay = -mMessagePos + cMessageOffset;
                }
                break;
            case 3:
                mMessagePos -= messagedelta * deltaT.secsf;
                break;
            case 1:
                mMessagePos += messagedelta * deltaT.secsf;
                break;
            case 4:
                //nothing
                break;
            case 2:
                mMessagePos = cMessageOffset;
                break;
        }
    }

    Vector2i layoutSizeRequest() {
        return Vector2i(0);
    }

    override protected void onDraw(Canvas canvas) {
        if (mPhase == 1 || mPhase == 2 || mPhase == 3) {
            auto org = size.X / 2 - (mMessageSize+cMessageBorders*2).X / 2;
            org.y += cast(int)mMessagePos;
            drawBox(canvas, org, mMessageSize+cMessageBorders*2);
            mFont.drawText(canvas, org+cMessageBorders, mCurrentMessage);
        }
    }
}
