module game.hud.messageviewer;

import framework.framework;
import framework.font;
import framework.i18n;
import common.scene;
import game.gobject;
import game.hud.teaminfo;
import game.controller_events;
import gui.widget;
import gui.label;
import utils.misc;
import utils.time;
import utils.queue;
import utils.interpolate;

//Linear up -> wait -> down -> wait
float msgAnimate(float x) {
    if (x < 0.1f)
        return x/0.1f;
    else if (x < 0.75f)
        return 1.0f;
    else if (x < 0.85f)
        return (0.85f - x)/0.1f;
    else
        return 0;
}

class MessageViewer : Label {
    private {
        struct QueuedMessage {
            char[] text;
            Team teamForColor;
        }

        GameInfo mGame;
        Queue!(QueuedMessage) mMessages;

        Translator mLocaleMsg;

        InterpolateFnTime!(int, msgAnimate) mInterp;

        //blergh
        Font mStdFont;
        Font[Team] mPerTeamFont;
    }

    this(GameInfo game) {
        mGame = game;
        mLocaleMsg = localeRoot.bindNamespace("game_msg");

        styles.id = "preparebox";
        font = gFontManager.loadFont("messages");
        mStdFont = font;

        //make sure it's hidden initially
        mInterp.init(timeSecs(0), -200, 0);

        mMessages = new typeof(mMessages);
        OnGameMessage.handler(mGame.cevents, &showMessage);
    }

    void addMessage(char[] msg, Team t = null) {
        mMessages.push(QueuedMessage(msg, t));
    }

    //return true as long messages are displayed
    bool working() {
        return !mMessages.empty || mInterp.inProgress;
    }

    bool idle() {
        return !working();
    }

    private void showMessage(GameObject sender, GameMessage msg) {
        if (msg.viewer) {
            //if the message is only for one team, check if it is ours
            bool show = false;
            foreach (Team t; mGame.control.getOwnedTeams()) {
                if (t is msg.viewer) {
                    show = true;
                    break;
                }
            }
            if (!show)
                return;
        }
        //translate and queue
        addMessage(mLocaleMsg.translateLocalizedMessage(msg.lm), msg.actor);
    }

    override void simulate() {
        if (!mInterp.inProgress && !mMessages.empty) {
            //put new message
            auto curMsg = mMessages.pop();
            text = curMsg.text;
            auto team = curMsg.teamForColor;
            if (team) {
                auto ptf = team in mPerTeamFont;
                if (!ptf) {
                    //ok, there should be a way to get a Font instance by
                    // FontProperties; in such a way that FontManager manages
                    // a cache of weak references to Font objects blablabla
                    auto p = mStdFont.properties;
                    p.fore = team.color.color;
                    Font f = new Font(p);
                    mPerTeamFont[team] = f;
                    ptf = &f;
                }
                font = *ptf;
            } else {
                font = mStdFont;
            }
            mInterp.init(timeSecs(1.5f),
                -containedBorderBounds.p1.y - containedBorderBounds.size.y, 0);
        }
        visible = working;
        setAddToPos(Vector2i(0, mInterp.value()));
    }
}
