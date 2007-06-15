module gui.messageviewer;

import framework.framework;
import framework.font;
import game.game;
import game.scene;
import game.common;
import game.visual;
import gui.guiobject;
import utils.misc;
import utils.time;

private class MessageViewer : GuiObject {
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

    void engine(GameEngine eng) {
        if (eng) {
            eng.controller.messageCb = &addMessage;
            eng.controller.messageIdleCb = &idle;
        } else {
            if (mEngine) {
                mEngine.controller.messageCb = null;
                mEngine.controller.messageIdleCb = null;
            }
        }
        super.engine(eng);
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

    void simulate(Time t, float deltaT) {
        Time phaseT = timeMsecs(cPhaseTimingsMs[mPhase]);
        Time diff = t - mPhaseStart;
        if (diff >= phaseT) {
            //end of current phase
            if (mPhase != 0) {
                mPhase++;
                mPhaseStart = t;
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
                    mPhaseStart = t;
                    mCurrentMessage = mMessages.pop();
                    mMessageSize = mFont.textSize(mCurrentMessage);
                    mMessagePos = -mMessageSize.y - cMessageBorders.y*2;
                    mMessageWay = -mMessagePos + cMessageOffset;
                }
                break;
            case 3:
                mMessagePos -= messagedelta * deltaT;
                break;
            case 1:
                mMessagePos += messagedelta * deltaT;
                break;
            case 4:
                //nothing
                break;
            case 2:
                mMessagePos = cMessageOffset;
                break;
        }
    }

    void draw(Canvas canvas) {
        //argh
        Time now = timeCurrentTime();
        float delta = (now - mLastFrame).toFloat();
        mLastFrame = now;
        simulate(now, delta);

        if (mPhase == 1 || mPhase == 2 || mPhase == 3) {
            auto org = scene.size.X / 2 - (mMessageSize+cMessageBorders*2).X / 2;
            org.y += cast(int)mMessagePos;
            drawBox(canvas, org, mMessageSize+cMessageBorders*2);
            mFont.drawText(canvas, org+cMessageBorders, mCurrentMessage);
        }
    }
}
